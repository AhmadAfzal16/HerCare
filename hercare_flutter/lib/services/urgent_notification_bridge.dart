import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android bridge displays only fixed generic wording, never remote prose.
/// Background FCM notifications remain handled by the operating system.
class UrgentNotificationBridge {
  UrgentNotificationBridge({MethodChannel? channel, bool? supported})
      : _channel = channel ?? const MethodChannel('com.hercare/notifications'),
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  final MethodChannel _channel;
  final bool _supported;
  Future<void> _tail = Future.value();
  String? _accountId;
  int _generation = 0;
  final Set<String> _seen = {};
  void Function(Map<String, dynamic>)? onOpened;

  Future<T?> _queue<T>(Future<T?> Function() action) {
    final result = _tail.then<T?>((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Map<String, String>? urgentData(Map<String, dynamic> data,
      {required String userId, required String role}) {
    final alertId = data['alert_id'];
    if (role != 'guardian' ||
        data['recipient_id'] != userId ||
        data['type'] != 'guardian_alert' ||
        data['route'] != '/notifications' ||
        data['urgent'] != 'true' ||
        alertId is! String ||
        !RegExp(r'^[A-Za-z0-9-]{1,100}$').hasMatch(alertId)) {
      return null;
    }
    return {
      'alert_id': alertId,
      'recipient_id': userId,
      'type': 'guardian_alert',
      'route': '/notifications',
      'urgent': 'true',
    };
  }

  void _opened(Map<String, dynamic> data) {
    final recipient = data['recipient_id'];
    if (recipient is! String ||
        (_accountId != null && recipient != _accountId)) {
      return;
    }
    final allowed = urgentData(data, userId: recipient, role: 'guardian');
    if (allowed != null) onOpened?.call(allowed);
  }

  Future<void> initialize() async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationOpened' || call.arguments is! Map) return;
      final data = Map<String, dynamic>.from(call.arguments as Map);
      _opened(data);
    });
    // Keep cold-start routing private until normal authentication is restored.
    try {
      final data = await _channel
          .invokeMapMethod<String, dynamic>('consumeInitialNotification');
      if (data != null) _opened(data);
    } on PlatformException {
      // Push/snackbar and the server notifications list still work.
    } on MissingPluginException {
      // Unsupported test/desktop surfaces keep ordinary in-app notifications.
    }
  }

  Future<void> bindAccount(String? accountId) async {
    if (_accountId == accountId) return;
    _accountId = accountId;
    final generation = ++_generation;
    _seen.clear();
    if (!_supported) return;
    await _queue<void>(() async {
      if (generation != _generation) return;
      try {
        await _channel
            .invokeMethod<void>('bindAccount', {'account_id': accountId});
      } on PlatformException {
        // No permission bypass or alternate audible fallback.
      } on MissingPluginException {
        // The ordinary notifications list is independent of this bridge.
      }
    });
  }

  Future<bool> show(Map<String, dynamic> data,
      {required String userId, required String role}) async {
    final allowed = urgentData(data, userId: userId, role: role);
    if (!_supported || allowed == null || _accountId != userId) return false;
    final key = '$userId:${allowed['alert_id']}';
    if (_seen.contains(key)) return false;
    _seen.add(key);
    if (_seen.length > 100) _seen.remove(_seen.first);
    final generation = _generation;
    final result = await _queue<bool>(() async {
      if (generation != _generation || _accountId != userId) return false;
      try {
        return await _channel.invokeMethod<bool>('showUrgent', allowed) ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    });
    return result ?? false;
  }
}
