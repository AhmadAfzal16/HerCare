import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/data/services/api_service.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ids = [
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000012',
  '00000000-0000-4000-8000-000000000013',
  '00000000-0000-4000-8000-000000000014',
];
const _recommendation = TherapyRecommendation(
  activityType: 'breathing',
  activityId: 'box_breathing',
  reason: 'Daily practice',
  reasonUr: '',
  safetyPriority: false,
);
const _summary =
    TherapySummary(totalSessions: 1, completedSessions: 1, totalSeconds: 60);

Map<String, dynamic> _ack(RequestOptions request) => {
      'success': true,
      'data': <String, dynamic>{
        ...Map<String, dynamic>.from(request.data as Map),
        'id': (request.data as Map)['client_request_id'],
        'completed_at': (request.data as Map)['client_completed_at'],
      },
    };

Future<void> _seed(TherapyService service, String id) async {
  await service.record(
      type: 'meditation',
      activityId: 'body_scan',
      durationSeconds: 60,
      clientRequestId: id,
      clientCompletedAt: DateTime.utc(2026, 10, 12));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  ApiService apiWith(
      void Function(RequestOptions, RequestInterceptorHandler) callback) {
    final api = ApiService();
    final original = api.client.interceptors.toList();
    api.client.interceptors
      ..clear()
      ..add(InterceptorsWrapper(onRequest: callback));
    addTearDown(() => api.client.interceptors
      ..clear()
      ..addAll(original));
    return api;
  }

  test(
      'M9 terminal outbox rejections are retained and do not block valid records',
      () async {
    bool offline = true, acceptAll = false;
    final sent = <String>[];
    final api = apiWith((request, handler) {
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
        return;
      }
      final id = (request.data as Map)['client_request_id'] as String;
      sent.add(id);
      final index = _ids.indexOf(id);
      if (!acceptAll && index < 3) {
        final status = [400, 409, 422][index];
        handler.reject(DioException(
            requestOptions: request,
            response: Response(
                requestOptions: request,
                statusCode: status,
                data: {'message': 'synthetic terminal validation'})));
      } else {
        handler.resolve(Response(
            requestOptions: request, statusCode: 201, data: _ack(request)));
      }
    });
    final service = TherapyService(api: api)..bindAccount('mother-a');
    for (final id in _ids) {
      await _seed(service, id);
    }
    offline = false;
    await service.syncPending();
    expect(sent, _ids);
    expect(service.pendingIssues.map((issue) => issue.statusCode),
        [400, 409, 422]);
    expect(service.syncWarning, contains('3 unsent'));
    const secure = FlutterSecureStorage();
    final saved = jsonDecode((await secure.readAll()).values.single) as List;
    expect(saved.length, 3);
    expect(saved.first['rejection_status'], 400);
    sent.clear();
    await service.syncPending();
    expect(sent, isEmpty); // Known invalid records are not retried in a loop.
    await expectLater(
        service.discardPending(_ids.first, expectedAccountId: 'mother-b'),
        throwsA(isA<TherapyAccountException>()));
    expect(
        (jsonDecode((await secure.readAll()).values.single) as List).length, 3);
    acceptAll = true;
    await service.retryPending(_ids.first, expectedAccountId: 'mother-a');
    expect(sent, [_ids.first]);
    expect(service.pendingIssues.length, 2);
    await service.discardPending(_ids[1], expectedAccountId: 'mother-a');
    expect(service.pendingIssues.single.requestId, _ids[2]);
    await service.discardPending(_ids[2], expectedAccountId: 'mother-a');
    expect(await secure.readAll(), isEmpty);
    expect(service.syncWarning, isNull);
  });

  for (final status in [429, 503]) {
    test(
        'M9 transient $status retains progress and still permits fresh hub reads',
        () async {
      bool offline = true;
      int gets = 0;
      final api = apiWith((request, handler) {
        if (request.method == 'POST') {
          if (offline) {
            handler.reject(DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError));
          } else {
            handler.reject(DioException(
                requestOptions: request,
                response:
                    Response(requestOptions: request, statusCode: status)));
          }
          return;
        }
        gets++;
        final data = request.path.endsWith('/recommendation')
            ? <String, dynamic>{
                'activity_type': 'breathing',
                'activity_id': 'box_breathing',
                'reason': 'Fresh',
                'reason_ur': '',
                'safety_priority': false
              }
            : request.path.endsWith('/summary')
                ? <String, dynamic>{
                    'total_sessions': 0,
                    'completed_sessions': 0,
                    'total_seconds': 0
                  }
                : <dynamic>[];
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'success': true, 'data': data}));
      });
      final service = TherapyService(api: api)..bindAccount('mother-a');
      await _seed(service, _ids.first);
      offline = false;
      final provider = TherapyProvider(service: service)
        ..bindAccount('mother-a');
      await provider.load();
      expect(gets, 3);
      expect(provider.recommendation?.reason, 'Fresh');
      expect(provider.summary, isNotNull);
      expect(provider.isOffline, false);
      expect(provider.syncWarning, contains('retained'));
      expect(provider.pendingIssues, isEmpty);
      expect((await const FlutterSecureStorage().readAll()).length, 1);
      provider.dispose();
    });
  }

  test('M9 discard cannot remove an unreviewed in-flight or valid queued save',
      () async {
    final api = apiWith((request, handler) => handler.reject(DioException(
        requestOptions: request, type: DioExceptionType.connectionError)));
    final service = TherapyService(api: api)..bindAccount('mother-a');
    await _seed(service, _ids.first);
    await expectLater(
        service.discardPending(_ids.first, expectedAccountId: 'mother-a'),
        throwsA(isA<TherapyQueueException>()));
    expect((await const FlutterSecureStorage().readAll()).length, 1);
    service.bindAccount('mother-b');
    await expectLater(
        service.retryPending(_ids.first, expectedAccountId: 'mother-a'),
        throwsA(isA<TherapyAccountException>()));
  });

  test('M9 sync consent denial stops reads and clears the private view',
      () async {
    final service = _ReadService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await provider.load();
    expect(provider.summary, isNotNull);
    service.syncError = TherapyAccessException();
    service.reads = 0;
    await provider.load();
    expect(service.reads, 0);
    expect(provider.summary, isNull);
    expect(provider.recommendation, isNull);
    expect(provider.history, isEmpty);
    expect(provider.error, contains('sign in'));
    provider.dispose();
  });

  test('M9 retryable sync failure cannot prevent fresh reads', () async {
    final service = _ReadService()
      ..syncError = Exception('synthetic queue problem');
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await provider.load();
    expect(service.reads, 3);
    expect(provider.summary, isNotNull);
    expect(provider.recommendation, isNotNull);
    expect(provider.syncWarning, contains('synthetic queue problem'));
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('M9 mixed read freshness remains stale despite a later successful GET',
      () async {
    final service = _ReadService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    final recommendation = Completer<TherapyRecommendation?>();
    final summary = Completer<TherapySummary?>();
    service.delayedRecommendation = recommendation.future;
    service.delayedSummary = summary.future;
    final work = provider.load();
    await Future<void>.delayed(Duration.zero);
    recommendation.complete(null); // one network read was unavailable
    summary
        .complete(_summary); // a later successful read cannot clear staleness
    await work;
    expect(service.isOffline, false);
    expect(provider.isOffline, true);
    expect(provider.summary, _summary);
    expect(provider.recommendation, isNull);
    provider.dispose();
  });

  test('M9 one rejected read clears successful parallel private results',
      () async {
    final service = _ReadService()..summaryError = TherapyAccessException();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    await provider.load();
    expect(service.reads, 3);
    expect(provider.recommendation, isNull);
    expect(provider.summary, isNull);
    expect(provider.history, isEmpty);
    expect(provider.error, contains('sign in'));
    provider.dispose();
  });

  testWidgets('M9 production proxy binding safely clears during auth rebuilds',
      (tester) async {
    final auth = _Auth();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProxyProvider<AuthProvider, TherapyProvider>(
          create: (_) => TherapyProvider(service: _ReadService()),
          update: (_, actor, therapy) => therapy!..bindAccount(actor.user?.id),
        ),
      ],
      child: MaterialApp(
          home: Consumer<TherapyProvider>(builder: (_, therapy, __) {
        final id = therapy.accountId;
        final count = therapy.history.length;
        return Text('$id: $count');
      })),
    ));
    await tester.pumpAndSettle();
    auth.change('mother-b');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('mother-b: 0'), findsOneWidget);
    auth.change(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('null: 0'), findsOneWidget);
    auth.dispose();
  });
}

class _ReadService extends TherapyService {
  Object? syncError, summaryError;
  int reads = 0;
  Future<TherapyRecommendation?>? delayedRecommendation;
  Future<TherapySummary?>? delayedSummary;
  @override
  bool get isOffline => false;
  @override
  Future<void> syncPending() async {
    if (syncError != null) throw syncError!;
  }

  @override
  Future<TherapyRecommendation?> recommendation() async {
    reads++;
    return delayedRecommendation == null
        ? _recommendation
        : await delayedRecommendation!;
  }

  @override
  Future<TherapySummary?> summary() async {
    reads++;
    if (summaryError != null) throw summaryError!;
    return delayedSummary == null ? _summary : await delayedSummary!;
  }

  @override
  Future<List<TherapySession>> history({int limit = 30}) async {
    reads++;
    return const [];
  }
}

class _Auth extends AuthProvider {
  String? id = 'mother-a';
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026),
        );
  void change(String? value) {
    id = value;
    notifyListeners();
  }
}
