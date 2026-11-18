import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hercare/services/mood_service.dart';
import 'package:hercare/data/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'M5 offline drafts bind owner/API and never replay another account or legacy unbound queue',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ApiService();
    final original = api.client.interceptors.toList();
    api.client.interceptors.clear();
    final requests = <RequestOptions>[];
    bool offline = true;
    api.client.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      if (offline) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else {
        handler
            .resolve(Response(requestOptions: request, statusCode: 200, data: {
          'success': true,
          'data': {
            'id': 'synthetic',
            'entry_type': 'text',
            'language': 'en',
            'processing_status': 'complete',
            'contains_danger': false,
            'created_at': '2026-10-11T00:00:00Z'
          }
        }));
      }
    }));
    addTearDown(() {
      api.client.interceptors
        ..clear()
        ..addAll(original);
    });
    final service = MoodService(api: api)..bindAccount('mother-a');
    final saved = await service.createJournal('PRIVATE_A');
    expect(saved.isSynced, false);
    expect(requests.single.headers['X-Mood-Account-Id'], 'mother-a');
    requests.clear();
    offline = false;
    service.bindAccount('mother-b');
    await service.syncPending();
    expect(requests, isEmpty);
    service.bindAccount('mother-a');
    await service.syncPending();
    expect(requests.single.data['content'], 'PRIVATE_A');
    expect(requests.single.headers['X-Mood-Account-Id'], 'mother-a');
    requests.clear();
    await service.syncPending();
    expect(requests, isEmpty);
  });
  test(
      'M5 a previous-account timeout cannot enqueue private text for the next account',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = ApiService();
    final original = api.client.interceptors.toList();
    api.client.interceptors.clear();
    final pending = Completer<void>();
    api.client.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      await pending.future;
      handler.reject(DioException(
          requestOptions: request, type: DioExceptionType.connectionError));
    }));
    addTearDown(() {
      api.client.interceptors
        ..clear()
        ..addAll(original);
    });
    final service = MoodService(api: api)..bindAccount('mother-a');
    final work = service.createJournal('PRIVATE_A');
    final expectation = expectLater(work, throwsA(isA<MoodAccountException>()));
    await Future<void>.delayed(Duration.zero);
    service.bindAccount('mother-b');
    pending.complete();
    await expectation;
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
}
