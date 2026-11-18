import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/services/chat_service.dart';

const _account = '11111111-1111-4111-8111-111111111111';
const _conversation = '33333333-3333-4333-8333-333333333333';
const _request = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> _message() => {
      'id': '55555555-5555-4555-8555-555555555555',
      'sender_id': _account,
      'is_mine': true,
      'content': 'Private text',
      'conversation_id': _conversation,
      'client_request_id': _request,
      'cursor': 'opaque_cursor',
      'created_at': '2026-10-12T12:00:00.123456Z',
    };

void main() {
  test(
      'modern page pins account/conversation and opaque cursor with no redirect',
      () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      captured = options;
      handler.resolve(Response(requestOptions: options, data: {
        'data': {
          'conversation_id': _conversation,
          'messages': [_message()],
          'has_more': false,
          'older_cursor': 'opaque_cursor',
          'newer_cursor': 'opaque_cursor',
        },
      }));
    }));
    final page = await ChatService(client: dio).getMessagePage(
      accountId: _account,
      conversationId: _conversation,
      after: 'after_cursor',
    );
    expect(captured.path, '/chat/messages/page');
    expect(captured.headers['X-Chat-Account-Id'], _account);
    expect(captured.headers['Cache-Control'], 'no-store');
    expect(captured.queryParameters, {
      'conversation_id': _conversation,
      'after': 'after_cursor',
      'limit': 50,
    });
    expect(captured.followRedirects, false);
    expect(page.messages.single.createdAt.microsecond, 456);
    dio.close();
  });

  test('send and read requests carry immutable request and visible range',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(requestOptions: options, data: {
        'data': options.method == 'POST' ? _message() : {'updated': 1},
      }));
    }));
    final service = ChatService(client: dio);
    final message = await service.sendBound(
        accountId: _account,
        conversationId: _conversation,
        clientRequestId: _request,
        content: ' Private text ');
    expect(message.clientRequestId, _request);
    expect(requests.first.data, {
      'conversation_id': _conversation,
      'client_request_id': _request,
      'content': 'Private text',
    });
    await service.markReadBound(
        accountId: _account,
        conversationId: _conversation,
        throughCursor: 'opaque_cursor',
        fromCursor: 'first_cursor');
    expect(requests.last.data, {
      'conversation_id': _conversation,
      'through_cursor': 'opaque_cursor',
      'from_cursor': 'first_cursor',
    });
    expect(requests.every((r) => r.headers['X-Chat-Account-Id'] == _account),
        true);
    dio.close();
  });

  test('typed failures do not expose arbitrary server/private error payloads',
      () async {
    for (final entry in {
      401: ChatFailureKind.accessDenied,
      403: ChatFailureKind.accessDenied,
      409: ChatFailureKind.conversationChanged,
      422: ChatFailureKind.validation,
      429: ChatFailureKind.rateLimited,
      503: ChatFailureKind.server,
    }.entries) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: entry.key,
            data: {'message': 'RAW_PRIVATE_TEXT'},
          ),
          type: DioExceptionType.badResponse,
        ));
      }));
      try {
        await ChatService(client: dio).getStatusBound(accountId: _account);
        fail('Expected a typed failure');
      } on ChatFailure catch (failure) {
        expect(failure.kind, entry.value);
        expect(failure.toString(), isNot(contains('RAW_PRIVATE_TEXT')));
        expect(failure.deliveryUncertain, entry.key >= 500);
      }
      dio.close();
    }
  });

  test('timeout is uncertain and a mismatched committed response is rejected',
      () async {
    var timeout = true;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (timeout) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ));
      } else {
        handler.resolve(Response(requestOptions: options, data: {
          'data': {..._message(), 'client_request_id': 'other-request'},
        }));
      }
    }));
    final service = ChatService(client: dio);
    Future<void> send() async {
      await service.sendBound(
          accountId: _account,
          conversationId: _conversation,
          clientRequestId: _request,
          content: 'Private text');
    }

    await expectLater(
        send(),
        throwsA(isA<ChatFailure>()
            .having((e) => e.kind, 'kind', ChatFailureKind.transport)
            .having((e) => e.deliveryUncertain, 'uncertain', true)));
    timeout = false;
    await expectLater(
        send(),
        throwsA(isA<ChatFailure>()
            .having((e) => e.kind, 'kind', ChatFailureKind.invalidResponse)
            .having((e) => e.deliveryUncertain, 'uncertain', true)));
    dio.close();
  });

  test('invalid modern response never falls back to legacy timestamp endpoint',
      () async {
    final paths = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      paths.add(options.path);
      handler.resolve(Response(requestOptions: options, data: {'data': []}));
    }));
    await expectLater(
        ChatService(client: dio)
            .getMessagePage(accountId: _account, conversationId: _conversation),
        throwsA(isA<ChatFailure>()
            .having((e) => e.kind, 'kind', ChatFailureKind.invalidResponse)));
    expect(paths, ['/chat/messages/page']);
    dio.close();
  });

  test('malformed read acknowledgement is not treated as server confirmation',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {
        'data': {'updated': 'not-an-integer'},
      }));
    }));
    await expectLater(
        ChatService(client: dio).markReadBound(
            accountId: _account,
            conversationId: _conversation,
            throughCursor: 'last_cursor',
            fromCursor: 'first_cursor'),
        throwsA(isA<ChatFailure>()
            .having((e) => e.kind, 'kind', ChatFailureKind.invalidResponse)));
    dio.close();
  });

  test('empty initial page requires origin cursor instead of a gappy fallback',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {
        'data': {
          'conversation_id': _conversation,
          'messages': <dynamic>[],
          'has_more': false,
          'older_cursor': null,
          'newer_cursor': null,
        },
      }));
    }));
    await expectLater(
        ChatService(client: dio)
            .getMessagePage(accountId: _account, conversationId: _conversation),
        throwsA(isA<ChatFailure>()
            .having((e) => e.kind, 'kind', ChatFailureKind.invalidResponse)));
    // An empty after-page is legitimate: callers retain their existing cursor.
    final empty = await ChatService(client: dio).getMessagePage(
        accountId: _account,
        conversationId: _conversation,
        after: 'origin_cursor');
    expect(empty.messages, isEmpty);
    dio.close();
  });
}
