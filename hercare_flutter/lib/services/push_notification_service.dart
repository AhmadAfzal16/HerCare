import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routing/app_router.dart';
import '../data/services/api_service.dart';
import '../data/models/user_model.dart';
import '../providers/auth_provider.dart';
import 'push_destination.dart';
import 'urgent_notification_bridge.dart';

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
  Map<String, dynamic>? _pendingData;
  final _urgentBridge = UrgentNotificationBridge();
  final Set<String> _foregroundSeen = {};
  String? _accountId;
  int _accountGeneration = 0;
  Future<void> _registrationTail = Future.value();

  static Map<String, dynamic> _routingData(Map<String, dynamic> data) => {
        for (final key in [
          'route',
          'type',
          'recipient_id',
          'alert_id',
          'urgent'
        ])
          if (data[key] is String && (data[key] as String).length <= 100)
            key: data[key],
      };

  UserModel? get _currentUser {
    final auth = AppRouter.router.routerDelegate.navigatorKey.currentContext
        ?.read<AuthProvider>();
    return auth?.isAuthenticated == true ? auth!.user : null;
  }

  void _bindAccount(UserModel? user) {
    if (_accountId == user?.id) return;
    _accountId = user?.id;
    ++_accountGeneration;
    _messages.clear();
    _foregroundSeen.clear();
    if (_pendingData != null && _pendingData!['recipient_id'] != _accountId) {
      _pendingData = null;
    }
    unawaited(_urgentBridge.bindAccount(_accountId));
  }

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
      _urgentBridge.onOpened = _openData;
      await _urgentBridge.initialize();
      _messageSubscription =
          FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _openedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Splash/login consumes this only after restoring the correct account.
        _pendingData = _routingData(initial.data);
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
    final user = _currentUser;
    _bindAccount(user);
    final generation = _accountGeneration;
    await initialize();
    if (!_initialized || user == null || generation != _accountGeneration) {
      return;
    }
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (generation != _accountGeneration || _currentUser?.id != user.id) {
        return;
      }
      _permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!_permissionGranted) {
        notifyListeners();
        return;
      }
      final token = await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null);
      if (generation != _accountGeneration || _currentUser?.id != user.id) {
        return;
      }
      _token = token;
      if (_token != null) await _register(_token!);
      if (generation != _accountGeneration || _currentUser?.id != user.id) {
        return;
      }
      await _tokenSubscription?.cancel();
      if (generation != _accountGeneration || _currentUser?.id != user.id) {
        return;
      }
      _tokenSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (generation != _accountGeneration || _currentUser?.id != user.id) {
          return;
        }
        _token = token;
        try {
          await _register(token);
        } catch (_) {/* retried on next authentication */}
      });
      _configurationError = null;
    } catch (_) {
      if (generation != _accountGeneration) return;
      _configurationError =
          'This device could not be registered for push notifications.';
    }
    notifyListeners();
  }

  Future<void> beforeLogout() async {
    final owner = _accountId;
    final token = _token;
    ++_accountGeneration;
    _accountId = null;
    _foregroundSeen.clear();
    _pendingData = null;
    _messages.clear();
    await _urgentBridge.bindAccount(null);
    // Do not let an earlier registration finish after token revocation.
    await _registrationTail;
    if (token != null) {
      try {
        await ApiService().client.delete('/notifications/devices',
            data: {'token': token},
            options: Options(headers: {'X-Notification-Account-Id': owner}));
      } catch (_) {}
    }
    _token = null;
    _permissionGranted = false;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    notifyListeners();
  }

  Future<void> _register(String token) {
    final owner = _accountId;
    final generation = _accountGeneration;
    final operation = _registrationTail.then((_) async {
      if (owner == null ||
          generation != _accountGeneration ||
          _currentUser?.id != owner) {
        return;
      }
      await ApiService().client.post('/notifications/devices',
          data: {
            'token': token,
            'platform': kIsWeb
                ? 'web'
                : (defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'android'),
          },
          options: Options(headers: {'X-Notification-Account-Id': owner}));
    });
    _registrationTail = operation.catchError((Object _) {});
    return operation;
  }

  void _onForegroundMessage(RemoteMessage message) {
    final data = _routingData(message.data);
    final user = _currentUser;
    if (user == null ||
        data['recipient_id'] != user.id ||
        pushDestination(data,
                userId: user.id,
                role: user.role,
                onboardingComplete: user.onboardingComplete) ==
            null) {
      return;
    }
    _bindAccount(user);
    final deduplicationId = data['alert_id'] ?? message.messageId;
    if (deduplicationId != null) {
      final key = '${user.id}:$deduplicationId';
      if (!_foregroundSeen.add(key)) return;
      if (_foregroundSeen.length > 100) {
        _foregroundSeen.remove(_foregroundSeen.first);
      }
    }
    unawaited(_urgentBridge.show(data, userId: user.id, role: user.role));
    final guardian = data['type'] == 'guardian_alert';
    final item = ReceivedPush(
      title: guardian ? 'HerCare support alert' : 'HerCare check-in reminder',
      body: guardian
          ? 'Open HerCare and check in with your linked mother.'
          : 'Open HerCare to view your scheduled check-in.',
      receivedAt: DateTime.now(),
      data: data,
    );
    _messages.insert(0, item);
    if (_messages.length > 50) _messages.removeLast();
    notifyListeners();
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text('${item.title}\n${item.body}'),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: 'Open', onPressed: () => _openData(data)),
    ));
  }

  void _openMessage(RemoteMessage message) {
    _openData(Map<String, dynamic>.from(message.data));
  }

  void _openData(Map<String, dynamic> data) {
    _pendingData = _routingData(data);
    final path = AppRouter.router.routeInformationProvider.value.uri.path;
    if ([
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.register,
      AppRoutes.languageSelection,
      AppRoutes.onboarding,
      AppRoutes.accountType
    ].contains(path)) {
      return;
    }
    final route = consumePendingRoute(_currentUser);
    if (route != null && route != path) AppRouter.router.push(route);
  }

  String? consumePendingRoute(UserModel? user) {
    if (user == null || _pendingData == null) return null;
    final data = _pendingData!;
    _pendingData = null;
    if (data['recipient_id'] != user.id) return null;
    return pushDestination(data,
        userId: user.id,
        role: user.role,
        onboardingComplete: user.onboardingComplete);
  }

  @override
  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    super.dispose();
  }
}
