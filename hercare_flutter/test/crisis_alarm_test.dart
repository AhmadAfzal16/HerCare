import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/crisis/crisis_alarm.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final ur in [false, true]) {
    testWidgets('alarm is explicit and readable at 320px/200% ur=$ur',
        (tester) async {
      final audio = _FakeAudio();
      final controller = CrisisAlarmController(audio: audio);
      await _mount(tester, controller, isUrdu: ur);
      expect(audio.starts, 0);
      expect(controller.active, false);
      await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
      await tester.pump();
      expect(audio.starts, 1);
      expect(controller.active, true);
      await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
      await tester.pump();
      expect(controller.active, false);
      expect(audio.stops, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('15-second deadline includes delayed loading and cannot restart',
      (tester) async {
    final audio = _FakeAudio()..delay = Completer<bool>();
    final controller = CrisisAlarmController(audio: audio);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump(const Duration(seconds: 15));
    expect(controller.active, false);
    expect(audio.stops, greaterThan(0));
    audio.delay!.complete(true);
    await tester.pump();
    expect(controller.active, false);
    expect(audio.starts, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('background and return never restart sound', (tester) async {
    final audio = _FakeAudio();
    final controller = CrisisAlarmController(audio: audio);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.active, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(audio.starts, 1);
    expect(controller.active, false);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a covering route stops sound; popping never resumes',
      (tester) async {
    final audio = _FakeAudio();
    final controller = CrisisAlarmController(audio: audio);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    final context = tester.element(find.byType(CrisisAlarmCard));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page')))));
    await tester.pumpAndSettle();
    expect(controller.active, false);
    Navigator.of(tester.element(find.text('Another page'))).pop();
    await tester.pumpAndSettle();
    expect(controller.active, false);
    expect(audio.starts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('account replacement immediately stops and disables old page',
      (tester) async {
    final audio = _FakeAudio();
    final controller = CrisisAlarmController(audio: audio);
    final auth = _FakeAuth('mother-a');
    await _mount(tester, controller, auth: auth, accountId: 'mother-a');
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    auth.change('mother-b');
    await tester.pump();
    expect(controller.active, false);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('crisis-alarm-toggle')))
            .onPressed,
        isNull);
    expect(audio.starts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    auth.dispose();
  });

  testWidgets('hidden integration and disposal stop without a server action',
      (tester) async {
    final audio = _FakeAudio();
    final controller = CrisisAlarmController(audio: audio);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    await _mount(tester, controller, active: false);
    expect(controller.active, false);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(audio.disposed, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback failure is honest and remains retryable',
      (tester) async {
    final audio = _FakeAudio()..available = false;
    final controller = CrisisAlarmController(audio: audio);
    await _mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    expect(controller.active, false);
    expect(find.text('Sound is unavailable. Use the direct help options.'),
        findsOneWidget);
    audio.available = true;
    await tester.tap(find.byKey(const ValueKey('crisis-alarm-toggle')));
    await tester.pump();
    expect(controller.active, true);
    expect(controller.unavailable, false);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

Future<void> _mount(WidgetTester tester, CrisisAlarmController controller,
    {bool isUrdu = false,
    bool active = true,
    String? accountId,
    AuthProvider? auth}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget app = MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: Directionality(
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              child: child!)),
      home: Scaffold(
          body: SingleChildScrollView(
              child: CrisisAlarmCard(
                  isUrdu: isUrdu,
                  active: active,
                  accountId: accountId,
                  controller: controller))));
  if (auth != null) {
    app = ChangeNotifierProvider<AuthProvider>.value(value: auth, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('crisis-alarm-toggle')));
  await tester.pumpAndSettle();
}

class _FakeAudio implements CrisisAlarmAudio {
  int starts = 0, stops = 0;
  bool available = true, disposed = false;
  Completer<bool>? delay;
  @override
  Future<bool> start() async {
    starts++;
    if (delay != null) return await delay!.future;
    return available;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  void dispose() => disposed = true;
}

class _FakeAuth extends AuthProvider {
  _FakeAuth(this.accountId);
  String? accountId;
  @override
  UserModel? get user => accountId == null
      ? null
      : UserModel(
          id: accountId!,
          phone: '+923001234567',
          role: 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026, 10, 12));
  void change(String? value) {
    accountId = value;
    notifyListeners();
  }
}
