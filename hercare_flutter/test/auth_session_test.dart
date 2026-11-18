import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hercare/data/repositories/auth_repository.dart';
import 'package:hercare/data/services/local_storage_service.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/presentation/auth/session_connection_banner.dart';
import 'package:provider/provider.dart';

const identity = {
  'id': 'mother-one',
  'phone': 'test-only',
  'role': 'mother',
  'language': 'en',
  'onboarding_complete': true,
  'created_at': '2026-01-01T00:00:00Z'
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio client;
  late AuthRepository repo;
  Object result = identity;
  Future<void> seed(
      {int ageDays = 0,
      String role = 'mother',
      String origin = 'https://test.example/api/v1'}) async {
    await LocalStorageService().setSecureString(
        AuthRepository.sessionCacheKey,
        jsonEncode({
          'user': {...identity, 'role': role},
          'api_origin': origin,
          'verified_at': DateTime.now()
              .subtract(Duration(days: ageDays))
              .toUtc()
              .toIso8601String(),
        }));
  }

  DioException failure(DioExceptionType type, {int? status}) => DioException(
      requestOptions: RequestOptions(path: '/auth/me'),
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/auth/me'),
              statusCode: status));
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues(
        {'access_token': 'test-access', 'refresh_token': 'test-refresh'});
    client = Dio(BaseOptions(baseUrl: 'https://test.example/api/v1'));
    result = identity;
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (result is DioException) {
        handler.reject(result as DioException);
      } else {
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: {'data': result}));
      }
    }));
    repo = AuthRepository(client: client);
  });
  tearDown(() => client.close(force: true));
  test(
      'online verification creates encrypted cache and offline restore retains identity',
      () async {
    expect((await repo.getMe())?.id, 'mother-one');
    expect(
        await LocalStorageService()
            .getSecureString(AuthRepository.sessionCacheKey),
        isNotNull);
    expect(
        (await SharedPreferences.getInstance())
            .containsKey(AuthRepository.sessionCacheKey),
        false);
    result = failure(DioExceptionType.connectionError);
    expect((await repo.getMe())?.id, 'mother-one');
    expect(repo.restoredOffline, true);
    expect(await LocalStorageService().getSecureString('refresh_token'),
        'test-refresh');
  });
  test('timeout and temporary server failure preserve a recent session',
      () async {
    await seed();
    for (final error in [
      failure(DioExceptionType.receiveTimeout),
      failure(DioExceptionType.badResponse, status: 503)
    ]) {
      result = error;
      expect((await repo.getMe())?.id, 'mother-one');
    }
  });
  test('401 never restores a revoked session', () async {
    await seed();
    result = failure(DioExceptionType.badResponse, status: 401);
    expect(await repo.getMe(), isNull);
    expect(
        await LocalStorageService()
            .getSecureString(AuthRepository.sessionCacheKey),
        isNull);
    expect(await LocalStorageService().getSecureString('access_token'), isNull);
  });
  test('403 never restores a suspended session', () async {
    await seed();
    result = failure(DioExceptionType.badResponse, status: 403);
    expect(await repo.getMe(), isNull);
    expect(
        await LocalStorageService().getSecureString('refresh_token'), isNull);
  });
  testWidgets('offline banner wraps on a small phone with large text',
      (tester) async {
    result = failure(DioExceptionType.connectionError);
    final provider = AuthProvider(repo: repo);
    await tester.runAsync(() async {
      await seed();
      await provider.tryRestoreSession();
    });
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: SessionConnectionBanner(child: child!)),
            home: const Scaffold(body: Text('Saved session')))));
    await tester.pumpAndSettle();
    expect(find.text('Using saved sign-in. Reconnect for live features.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    result = identity;
    await tester.runAsync(() async {
      await provider.refreshCurrentUser();
    });
    await tester.pumpAndSettle();
    expect(provider.isOfflineSession, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
  test(
      'expired cache, changed server, and administrator cache require verification',
      () async {
    result = failure(DioExceptionType.connectionError);
    await seed(ageDays: 8);
    await expectLater(
        repo.getMe(), throwsA(isA<SessionUnavailableException>()));
    await seed(origin: 'https://other.example/api/v1');
    await expectLater(
        repo.getMe(), throwsA(isA<SessionUnavailableException>()));
    await seed(role: 'admin');
    await expectLater(
        repo.getMe(), throwsA(isA<SessionUnavailableException>()));
  });
  test('no cache on outage reports unavailable without erasing credentials',
      () async {
    result = failure(DioExceptionType.connectionError);
    await expectLater(
        repo.getMe(), throwsA(isA<SessionUnavailableException>()));
    expect(
        await LocalStorageService().getSecureString('access_token'), isNotNull);
  });
  test('TLS rejection must not be treated as ordinary offline restoration',
      () async {
    await seed();
    result = failure(DioExceptionType.badCertificate);
    await expectLater(repo.getMe(), throwsA(isA<DioException>()));
    expect(repo.restoredOffline, false);
  });
  test(
      'offline provider remains signed in; strict refresh cannot fake onboarding success',
      () async {
    await seed();
    result = failure(DioExceptionType.connectionError);
    final provider = AuthProvider(repo: repo);
    await provider.tryRestoreSession();
    expect(provider.isAuthenticated, true);
    expect(provider.isOfflineSession, true);
    expect(await provider.refreshCurrentUser(), isNull);
    expect(provider.user?.id, 'mother-one');
    provider.dispose();
  });
  test('logout deletes cached identity even with disconnected server',
      () async {
    await seed();
    result = failure(DioExceptionType.connectionError);
    await repo.logout();
    expect(
        await LocalStorageService()
            .getSecureString(AuthRepository.sessionCacheKey),
        isNull);
    expect(await repo.getMe(), isNull);
  });
}
