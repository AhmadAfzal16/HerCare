import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/routing/app_router.dart';
import '../data/services/api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = PushNotificationService.firebaseOptions;
  if (Firebase.apps.isEmpty) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
    } else if (options != null) {
      await Firebase.initializeApp(options: options);
    }
  }
}

class ReceivedPush {
  const ReceivedPush(
      {required this.title,
      required this.body,
      required this.receivedAt,
      required this.data});
  final String title;
  final String body;
  final DateTime receivedAt;
  final Map<String, dynamic> data;
}

class PushNotificationService extends ChangeNotifier {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static const _vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static FirebaseOptions? get firebaseOptions {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    if ([apiKey, appId, projectId, senderId].any((value) => value.isEmpty)) {
      return null;
    }
    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    );
  }

  final List<ReceivedPush> _messages = [];
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;
  bool _permissionGranted = false;
  String? _token;
  String? _configurationError;

  bool get isConfigured =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ||
      firebaseOptions != null;
  bool get permissionGranted => _permissionGranted;
  String? get configurationError => _configurationError;
  List<ReceivedPush> get messages => List.unmodifiable(_messages);

  Future<void> initialize() async {
    if (_initialized || !isConfigured) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await Firebase.initializeApp();
      } else {
        await Firebase.initializeApp(options: firebaseOptions!);
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _messageSubscription =
          FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _openedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openMessage(initial));
      }
      _initialized = true;
      _configurationError = null;
    } catch (_) {
      _configurationError = 'Push notifications could not be initialized.';
    }
    notifyListeners();
  }

  Future<void> onAuthenticated() async {
    if (!isConfigured) return;
    await initialize();
    if (!_initialized) return;
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      _permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!_permissionGranted) {
        notifyListeners();
        return;
      }
      _token = await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null);
      if (_token != null) await _register(_token!);
      await _tokenSubscription?.cancel();
      _tokenSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        _token = token;
        try {
          await _register(token);
        } catch (_) {/* retried on next authentication */}
      });
      _configurationError = null;
    } catch (_) {
      _configurationError =
          'This device could not be registered for push notifications.';
    }
    notifyListeners();
  }

  Future<void> beforeLogout() async {
    final token = _token;
    if (token != null) {
      try {
        await ApiService()
            .client
            .delete('/notifications/devices', data: {'token': token});
      } catch (_) {}
    }
    _token = null;
    _permissionGranted = false;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    notifyListeners();
  }

  Future<void> _register(String token) =>
      ApiService().post('/notifications/devices', data: {
        'token': token,
        'platform': kIsWeb
            ? 'web'
            : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
      });

  void _onForegroundMessage(RemoteMessage message) {
    final item = ReceivedPush(
      title: message.notification?.title ?? 'HerCare update',
      body: message.notification?.body ?? 'Open HerCare to view the update.',
      receivedAt: DateTime.now(),
      data: Map<String, dynamic>.from(message.data),
    );
    _messages.insert(0, item);
    if (_messages.length > 50) _messages.removeLast();
    notifyListeners();
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('${item.title}\n${item.body}'),
      behavior: SnackBarBehavior.floating,
      action:
          SnackBarAction(label: 'Open', onPressed: () => _openMessage(message)),
    ));
  }

  void _openMessage(RemoteMessage message) {
    if (message.data['route'] == AppRoutes.notifications) {
      AppRouter.router.go(AppRoutes.notifications);
    }
  }

  @override
  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    super.dispose();
  }
}
