import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/data/services/api_service.dart';
import 'package:hercare/presentation/therapy/therapy_completion_sheet.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/mood_service.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = '00000000-0000-4000-8000-000000000001';
const _b = '00000000-0000-4000-8000-000000000002';
const _c = '00000000-0000-4000-8000-000000000003';
final _at = DateTime.utc(2026, 10, 12);

TherapySession _session(String id, {bool synced = true}) => TherapySession(
    id: id,
    activityType: 'meditation',
    activityId: 'body_scan',
    durationSeconds: 60,
    completed: true,
    completedAt: _at,
    isSynced: synced);

Map<String, dynamic> _body(RequestOptions request) => {
      'success': true,
      'data': <String, dynamic>{
        ...(request.data as Map),
        'id': (request.data as Map)['client_request_id'],
        'completed_at': (request.data as Map)['client_completed_at'],
      },
    };

Future<TherapySession> _record(TherapyService service, String id,
        {int? moodAfter}) =>
    service.record(
      type: 'meditation',
      activityId: 'body_scan',
      durationSeconds: 60,
      clientRequestId: id,
      clientCompletedAt: _at,
      moodAfter: moodAfter,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  ApiService apiWith(
      void Function(RequestOptions, RequestInterceptorHandler) requestHandler) {
    final api = ApiService();
    final original = api.client.interceptors.toList();
    final originalUrl = api.client.options.baseUrl;
    api.client.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: requestHandler));
    addTearDown(() {
      api.client.options.baseUrl = originalUrl;
      api.client.interceptors
        ..clear()
        ..addAll(original);
    });
    return api;
  }

  test('M9 encrypted outbox binds owner/API and ignores legacy ownerless queue',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'pending_therapy_sessions_v1',
        jsonEncode([
          {'client_request_id': 'old-private-record'}
        ]));
    final requests = <RequestOptions>[];
    bool offline = true;
    final api = apiWith((request, handler) {
      requests.add(request);
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 201, data: _body(request)));
      }
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    expect((await _record(service, _a)).isSynced, false);
    expect(requests.single.headers['X-Therapy-Account-Id'], 'mother-a');
    expect(requests.single.headers['Cache-Control'], 'no-store');
    final offlineHistory = await service.history();
    expect(offlineHistory.single.id, _a);
    expect(offlineHistory.single.isSynced, false);
    expect(offlineHistory.single.completedAt, _at);
    expect(prefs.getKeys(), {'pending_therapy_sessions_v1'});
    final secure = await const FlutterSecureStorage().readAll();
    expect(secure.length, 1);
    expect(secure.keys.single, startsWith('pending_therapy_sessions_v2:'));
    requests.clear();
    offline = false;
    service.bindAccount('mother-b');
    await service.syncPending();
    expect(requests, isEmpty);
    service.bindAccount('mother-a');
    final origin = api.client.options.baseUrl;
    api.client.options.baseUrl = 'https://different.example/api/v1';
    await service.syncPending();
    expect(requests, isEmpty);
    api.client.options.baseUrl = origin;
    await service.syncPending();
    expect(requests.length, 1);
    expect((requests.single.data as Map)['client_request_id'], _a);
    expect((requests.single.data as Map)['client_completed_at'],
        _at.toIso8601String());
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    expect(prefs.getString('pending_therapy_sessions_v1'), isNotNull);
  });

  test('M9 late old-account timeout cannot enqueue another owner', () async {
    final barrier = Completer<void>();
    final api = apiWith((request, handler) async {
      await barrier.future;
      handler.reject(DioException(
          requestOptions: request, type: DioExceptionType.receiveTimeout));
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    final work = _record(service, _a);
    final expected = expectLater(work, throwsA(isA<TherapyAccountException>()));
    await Future<void>.delayed(Duration.zero);
    service.bindAccount('mother-b');
    barrier.complete();
    await expected;
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('M9 serialized enqueue and UUID ACK preserve newer offline progress',
      () async {
    int mode = 0;
    final replayStarted = Completer<void>();
    final releaseReplay = Completer<void>();
    final requests = <RequestOptions>[];
    final api = apiWith((request, handler) async {
      requests.add(request);
      if (mode == 1 && (request.data as Map)['client_request_id'] == _a) {
        if (!replayStarted.isCompleted) replayStarted.complete();
        await releaseReplay.future;
        handler.resolve(Response(
            requestOptions: request, statusCode: 201, data: _body(request)));
      } else if (mode == 2) {
        handler.resolve(Response(
            requestOptions: request, statusCode: 201, data: _body(request)));
      } else {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      }
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await Future.wait([_record(service, _a), _record(service, _b)]);
    mode = 1;
    requests.clear();
    final firstSync = service.syncPending();
    final duplicateSync = service.syncPending();
    await replayStarted.future;
    await _record(service, _c);
    releaseReplay.complete();
    await Future.wait([firstSync, duplicateSync]);
    expect(
        requests
            .where((r) => (r.data as Map)['client_request_id'] == _a)
            .length,
        1);
    final secure = await const FlutterSecureStorage().readAll();
    final queue = jsonDecode(secure.values.single) as List;
    expect(queue.map((item) => item['payload']['client_request_id']), [_b, _c]);
    mode = 2;
    requests.clear();
    await service.syncPending();
    expect(requests.map((r) => (r.data as Map)['client_request_id']), [_b, _c]);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test(
      'M9 offline duplicate ID is deduplicated and conflicting payload retained',
      () async {
    final api = apiWith((request, handler) => handler.reject(DioException(
        requestOptions: request, type: DioExceptionType.connectionError)));
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await _record(service, _a, moodAfter: 3);
    await _record(service, _a, moodAfter: 3);
    await expectLater(_record(service, _a, moodAfter: 4),
        throwsA(isA<TherapyQueueException>()));
    final queue =
        jsonDecode((await const FlutterSecureStorage().readAll()).values.single)
            as List;
    expect(queue.length, 1);
    expect(queue.single['payload']['mood_after'], 3);
  });

  test('M9 full outbox does not evict the oldest unsent record', () async {
    final api = apiWith((request, handler) => handler.reject(DioException(
        requestOptions: request, type: DioExceptionType.connectionError)));
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await _record(service, _a);
    const storage = FlutterSecureStorage();
    final values = await storage.readAll();
    final initial = (jsonDecode(values.values.single) as List).single as Map;
    final full = List.generate(
        100,
        (index) => {
              ...initial,
              'payload': {
                ...initial['payload'] as Map,
                'client_request_id': index == 0 ? _a : MoodService.requestId()
              },
            });
    await storage.write(key: values.keys.single, value: jsonEncode(full));
    await expectLater(
        _record(service, _b), throwsA(isA<TherapyQueueException>()));
    final saved = jsonDecode((await storage.readAll()).values.single) as List;
    expect(saved.length, 100);
    expect(saved.first['payload']['client_request_id'], _a);
  });

  test('M9 revoked or malformed replay never deletes unsent progress',
      () async {
    int mode = 0;
    final api = apiWith((request, handler) {
      if (mode == 0) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else if (mode == 1) {
        handler.reject(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 403)));
      } else if (mode == 2) {
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'success': true, 'data': {}}));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 201, data: _body(request)));
      }
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await _record(service, _a);
    mode = 1;
    await expectLater(
        service.syncPending(), throwsA(isA<TherapyAccessException>()));
    expect((await const FlutterSecureStorage().readAll()).length, 1);
    mode = 2;
    await service.syncPending();
    expect(service.syncWarning, contains('could not be confirmed'));
    expect((await const FlutterSecureStorage().readAll()).length, 1);
    mode = 3;
    await service.syncPending();
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('M9 malformed storage is neither replayed nor silently removed',
      () async {
    final requests = <RequestOptions>[];
    final api = apiWith((request, handler) {
      requests.add(request);
      handler.reject(DioException(
          requestOptions: request, type: DioExceptionType.connectionError));
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await _record(service, _a);
    const storage = FlutterSecureStorage();
    final key = (await storage.readAll()).keys.single;
    await storage.write(key: key, value: '{"invalid": true}');
    requests.clear();
    await expectLater(
        service.syncPending(), throwsA(isA<TherapyQueueException>()));
    expect(requests, isEmpty);
    expect(await storage.read(key: key), '{"invalid": true}');
  });

  test('M9 unbound/logout queues are not persisted or dispatched', () async {
    int requests = 0;
    final api = apiWith((request, handler) {
      requests++;
      handler.reject(DioException(
          requestOptions: request, type: DioExceptionType.connectionError));
    });
    final service = TherapyService(api: api);
    await expectLater(
        _record(service, _a), throwsA(isA<TherapyQueueException>()));
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
    service.bindAccount(null);
    await expectLater(
        _record(service, _b), throwsA(isA<TherapyAccountException>()));
    expect(requests, 1);
  });

  test('M9 late account-bound reads are rejected before exposing history',
      () async {
    final barrier = Completer<void>();
    final started = Completer<void>();
    final api = apiWith((request, handler) async {
      started.complete();
      await barrier.future;
      handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {'success': true, 'data': <dynamic>[]}));
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    final work = service.history();
    final expected = expectLater(work, throwsA(isA<TherapyAccountException>()));
    await started.future;
    service.bindAccount('mother-b');
    barrier.complete();
    await expected;
  });

  test('M9 provider clears old history and discards a late load', () async {
    final service = _TestService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await provider.complete(
        type: 'meditation', activityId: 'body_scan', durationSeconds: 60);
    expect(provider.history, hasLength(1));
    final barrier = Completer<List<TherapySession>>();
    service.delayedHistory = barrier.future;
    final work = provider.load();
    await Future<void>.delayed(Duration.zero);
    provider.bindAccount('mother-b');
    barrier.complete([_session('PRIVATE_A')]);
    await work;
    expect(provider.history, isEmpty);
    expect(provider.summary, isNull);
    expect(provider.recommendation, isNull);
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('M9 provider discards late previous-account and disposed save results',
      () async {
    final service = _TestService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    final delayed = Completer<TherapySession>();
    service.pending = delayed.future;
    final work = provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: _a);
    provider.bindAccount('mother-b');
    delayed.complete(_session('PRIVATE_A'));
    expect(await work, isNull);
    expect(provider.history, isEmpty);
    expect(provider.error, isNull);
    final delayedDispose = Completer<TherapySession>();
    service.pending = delayedDispose.future;
    final after = provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: _b);
    provider.dispose();
    delayedDispose.complete(_session('PRIVATE_B'));
    expect(await after, isNull);
  });

  test('M9 provider coalesces duplicate submissions and deduplicates retry',
      () async {
    final service = _TestService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    final delayed = Completer<TherapySession>();
    service.pending = delayed.future;
    final first = provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: _a);
    final second = provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: _a);
    expect(service.calls.length, 1);
    delayed.complete(_session('server-session'));
    expect((await first)?.id, 'server-session');
    expect((await second)?.id, 'server-session');
    final at = service.calls.single['client_completed_at'];
    service.pending = null;
    service.returnId = 'server-session';
    await provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: _a);
    expect(service.calls.last['client_completed_at'], at);
    expect(provider.history.length, 1);
    expect(provider.isSaving, false);
    provider.dispose();
  });

  for (final urdu in [false, true]) {
    testWidgets('M9 optional completion stays overflow-free at 200% $urdu',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _TestService();
      final provider = TherapyProvider(service: service)
        ..bindAccount('mother-a');
      await _openSheet(tester, provider, urdu: urdu, scale: 2);
      final optional = find.text(urdu
          ? 'موڈ کی کیفیت شامل کریں (اختیاری)'
          : 'Add mood ratings (optional)');
      await tester.ensureVisible(optional);
      await tester.tap(optional);
      await tester.pumpAndSettle();
      final save = find.text(urdu ? 'مشق محفوظ کریں' : 'Save completion');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(service.calls.single['mood_before'], isNull);
      expect(service.calls.single['mood_after'], isNull);
      expect(tester.takeException(), isNull);
      provider.dispose();
    });
  }

  testWidgets('M9 retry keeps UUID/ratings/time and blocks duplicate taps',
      (tester) async {
    final service = _TestService()..fail = true;
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await _openSheet(tester, provider);
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save.'), findsOneWidget);
    final first = service.calls.single;
    final pending = Completer<TherapySession>();
    service.pending = pending.future;
    service.fail = false;
    await tester.tap(find.text('Retry save'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton).last, warnIfMissed: false);
    await tester.pump();
    expect(service.calls.length, 2);
    expect(service.calls.last, first);
    pending.complete(_session('saved'));
    await tester.pumpAndSettle();
    expect(find.text('Retry save'), findsNothing);
    expect(tester.takeException(), isNull);
    provider.dispose();
  });

  testWidgets('M9 account switch hides controls and cannot save new owner',
      (tester) async {
    final service = _TestService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await _openSheet(tester, provider);
    provider.bindAccount('mother-b');
    await tester.pump();
    expect(find.textContaining('Your account changed.'), findsOneWidget);
    expect(find.text('Save completion'), findsNothing);
    expect(service.calls, isEmpty);
    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    provider.dispose();
  });

  test(
      'M9 in-memory history is bounded while explicit retry timestamps survive eviction',
      () async {
    final service = _TestService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    for (var index = 0; index < 205; index++) {
      service.returnId = 'server-$index';
      await provider.complete(
          type: 'meditation',
          activityId: 'body_scan',
          durationSeconds: 60,
          clientRequestId: MoodService.requestId(),
          clientCompletedAt: _at);
    }
    expect(provider.history.length, 100);
    expect(provider.history.first.id, 'server-204');
    expect(provider.history.last.id, 'server-105');
    final oldestRequestId = service.calls.first['client_request_id'] as String;
    service.returnId = 'server-0';
    await provider.complete(
        type: 'meditation',
        activityId: 'body_scan',
        durationSeconds: 60,
        clientRequestId: oldestRequestId,
        clientCompletedAt: _at);
    expect(service.calls.last['client_completed_at'], _at);
    expect(provider.history.length, 100);
    provider.dispose();
  });

  testWidgets('M9 completion language and errors follow the live app toggle',
      (tester) async {
    final language = LanguageProvider();
    final service = _TestService()..fail = true;
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await _openSheet(tester, provider, language: language);
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save.'), findsOneWidget);
    await language.setLocale(const Locale('ur'));
    await tester.pumpAndSettle();
    expect(find.text('اپنی مشق محفوظ کریں'), findsOneWidget);
    expect(find.text('دوبارہ محفوظ کریں'), findsOneWidget);
    expect(find.textContaining('محفوظ نہیں ہوا۔'), findsOneWidget);
    expect(find.textContaining('Could not save.'), findsNothing);
    expect(tester.takeException(), isNull);
    provider.dispose();
    language.dispose();
  });

  testWidgets('M9 partial practice is incomplete and reports offline status',
      (tester) async {
    final service = _TestService()..synced = false;
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await _openSheet(tester, provider, completed: false);
    expect(find.text('Save partial practice'), findsOneWidget);
    await tester.tap(find.text('Save partial'));
    await tester.pumpAndSettle();
    expect(service.calls.single['completed'], false);
    expect(
        find.textContaining('Saved securely on this phone.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    provider.dispose();
  });
}

Future<void> _openSheet(WidgetTester tester, TherapyProvider provider,
    {bool urdu = false,
    double scale = 1,
    bool completed = true,
    LanguageProvider? language}) async {
  final app = ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: const EdgeInsets.only(bottom: 80)),
        child: child!,
      ),
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => showTherapyCompletionSheet(context,
                    type: 'meditation',
                    activityId: 'body_scan',
                    durationSeconds: 60,
                    isUrdu: urdu,
                    completed: completed),
                child: const Text('Open completion'),
              ))),
    ),
  );
  await tester.pumpWidget(language == null
      ? app
      : ChangeNotifierProvider<LanguageProvider>.value(
          value: language, child: app));
  await tester.tap(find.text('Open completion'));
  await tester.pumpAndSettle();
}

class _TestService extends TherapyService {
  final calls = <Map<String, dynamic>>[];
  Future<TherapySession>? pending;
  Future<List<TherapySession>>? delayedHistory;
  bool fail = false, synced = true;
  String returnId = 'saved';

  @override
  Future<void> syncPending() async {}
  @override
  Future<TherapyRecommendation?> recommendation() async => null;
  @override
  Future<TherapySummary?> summary() async => null;
  @override
  Future<List<TherapySession>> history({int limit = 30}) async =>
      delayedHistory == null ? [] : await delayedHistory!;

  @override
  Future<TherapySession> record(
      {required String type,
      required String activityId,
      required int durationSeconds,
      int? moodBefore,
      int? moodAfter,
      String? breathingParticipation,
      bool completed = true,
      String? clientRequestId,
      DateTime? clientCompletedAt}) async {
    calls.add({
      'client_request_id': clientRequestId,
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      'completed': completed,
      'client_completed_at': clientCompletedAt
    });
    if (pending != null) return pending!;
    if (fail) throw Exception('synthetic failure');
    return _session(returnId, synced: synced);
  }
}
