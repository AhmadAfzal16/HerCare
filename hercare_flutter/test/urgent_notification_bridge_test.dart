import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/services/urgent_notification_bridge.dart';

const _data = <String, dynamic>{
  'recipient_id': 'guardian-a',
  'alert_id': 'alert-a',
  'route': '/notifications',
  'type': 'guardian_alert',
  'urgent': 'true',
  'raw_text': 'NEVER FORWARD THIS',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.hercare/urgent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('urgent allowlist requires exact current guardian, route and bounded ID',
      () {
    Map<String, String>? parse(Map<String, dynamic> data,
            {String role = 'guardian'}) =>
        UrgentNotificationBridge.urgentData(data,
            userId: 'guardian-a', role: role);
    final allowed = parse(_data)!;
    expect(
        allowed.keys, ['alert_id', 'recipient_id', 'type', 'route', 'urgent']);
    expect(allowed.containsKey('raw_text'), false);
    for (final bad in [
      {..._data, 'recipient_id': 'guardian-b'},
      {..._data, 'recipient_id': null},
      {..._data, 'urgent': true},
      {..._data, 'urgent': 'false'},
      {..._data, 'route': '/admin'},
      {..._data, 'alert_id': 'x' * 101},
      {..._data, 'alert_id': 'unsafe/url'},
    ]) {
      expect(parse(bad), isNull);
    }
    expect(parse(_data, role: 'mother'), isNull);
  });

  test('foreground notice is generic, duplicate-safe and cleared on logout',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'showUrgent' ? true : null;
    });
    final bridge = UrgentNotificationBridge(channel: channel, supported: true);
    await bridge.bindAccount('guardian-a');
    expect(
        await bridge.show(_data, userId: 'guardian-a', role: 'guardian'), true);
    expect(await bridge.show(_data, userId: 'guardian-a', role: 'guardian'),
        false);
    final payload = calls
        .singleWhere((call) => call.method == 'showUrgent')
        .arguments as Map;
    expect(payload.containsKey('raw_text'), false);
    expect(payload.containsKey('body'), false);
    await bridge.bindAccount(null);
    expect(await bridge.show(_data, userId: 'guardian-a', role: 'guardian'),
        false);
    expect(calls.last.method, 'bindAccount');
    expect(calls.last.arguments, {'account_id': null});
  });

  test('queued old-account notification is discarded before native dispatch',
      () async {
    final binding = Completer<void>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'bindAccount' &&
          (call.arguments as Map)['account_id'] == 'guardian-a') {
        await binding.future;
      }
      return call.method == 'showUrgent' ? true : null;
    });
    final bridge = UrgentNotificationBridge(channel: channel, supported: true);
    final firstBinding = bridge.bindAccount('guardian-a');
    await Future<void>.delayed(Duration.zero);
    final showing = bridge.show(_data, userId: 'guardian-a', role: 'guardian');
    final secondBinding = bridge.bindAccount('guardian-b');
    binding.complete();
    await firstBinding;
    expect(await showing, false);
    await secondBinding;
    expect(calls.where((call) => call.method == 'showUrgent'), isEmpty);
    expect(calls.last.arguments, {'account_id': 'guardian-b'});
  });

  test('cold-start taps retain only safe routing until matching authentication',
      () async {
    messenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'consumeInitialNotification' ? _data : null);
    final opened = <Map<String, dynamic>>[];
    final bridge = UrgentNotificationBridge(channel: channel, supported: true)
      ..onOpened = opened.add;
    await bridge.initialize();
    expect(opened.single['recipient_id'], 'guardian-a');
    expect(opened.single.containsKey('raw_text'), false);
    await bridge.bindAccount('guardian-b');
    await bridge.initialize();
    expect(opened.length, 1);
  });

  test('permission or plugin failures do not invent successful sound',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'showUrgent') {
        throw PlatformException(code: 'PERMISSION');
      }
      return null;
    });
    final bridge = UrgentNotificationBridge(channel: channel, supported: true);
    await bridge.bindAccount('guardian-a');
    expect(await bridge.show(_data, userId: 'guardian-a', role: 'guardian'),
        false);
    final unsupported =
        UrgentNotificationBridge(channel: channel, supported: false);
    await unsupported.bindAccount('guardian-a');
    expect(
        await unsupported.show(_data, userId: 'guardian-a', role: 'guardian'),
        false);
  });
}
