import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/chat_models.dart';
import '../data/services/api_service.dart';

enum ChatFailureKind {
  accessDenied,
  conversationChanged,
  validation,
  rateLimited,
  transport,
  server,
  invalidResponse,
}

/// Transport failures can follow a committed send. Retry its original UUID;
/// never create a new request or automatically replay private messages.
class ChatFailure implements Exception {
  const ChatFailure(this.kind, this.message, {this.statusCode});

  final ChatFailureKind kind;
  final String message;
  final int? statusCode;

  bool get deliveryUncertain =>
      kind == ChatFailureKind.transport ||
      kind == ChatFailureKind.server ||
      kind == ChatFailureKind.invalidResponse;

  @override
  String toString() => message;
}

class ChatService {
  ChatService({ApiService? api, Dio? client})
      : _client = client ?? (api ?? ApiService()).client;

  final Dio _client;

  // Legacy methods remain for older callers. The account-bound provider never
  // falls back to timestamp-only pagination.
  Future<ChatStatus> getStatus() => _status();
  Future<ChatStatus> getStatusBound({required String accountId}) =>
      _status(accountId: accountId);

  Future<ChatStatus> _status({String? accountId}) async {
    try {
      final response =
          await _client.get('/chat/status', options: _options(accountId));
      return ChatStatus.fromJson(_dataMap(response.data));
    } on DioException catch (error) {
      throw _error(error);
    } on FormatException {
      throw _invalid;
    }
  }

  Future<List<ChatMessage>> getMessages({
    DateTime? before,
    DateTime? after,
    int limit = 30,
  }) async {
    try {
      final response = await _client.get('/chat/messages', queryParameters: {
        if (before != null) 'before': before.toUtc().toIso8601String(),
        if (after != null) 'after': after.toUtc().toIso8601String(),
        'limit': limit,
      });
      final data =
          response.data is Map<String, dynamic> ? response.data['data'] : null;
      if (data is! List) throw _invalid;
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ChatPage> getMessagePage({
    required String accountId,
    required String conversationId,
    String? before,
    String? after,
    int limit = 50,
  }) async {
    if (before != null && after != null || limit < 1 || limit > 50) {
      throw const ChatFailure(
          ChatFailureKind.validation, 'Invalid chat page request.');
    }
    try {
      final response = await _client.get('/chat/messages/page',
          queryParameters: {
            'conversation_id': conversationId,
            if (before != null) 'before': before,
            if (after != null) 'after': after,
            'limit': limit,
          },
          options: _options(accountId));
      final page = ChatPage.fromJson(_dataMap(response.data));
      if (page.conversationId != conversationId) {
        throw const ChatFailure(ChatFailureKind.conversationChanged,
            'The conversation has changed. Reload chat.');
      }
      if (before == null &&
          after == null &&
          page.messages.isEmpty &&
          page.newerCursor == null) {
        // Modern empty conversations must publish a starting cursor. A
        // timestamp/latest-window fallback would miss a first large burst.
        throw _invalid;
      }
      return page;
    } on DioException catch (error) {
      throw _error(error);
    } on FormatException {
      throw _invalid;
    }
  }

  Future<ChatMessage> send(String content) =>
      _send(content: content, clientRequestId: createRequestId());

  Future<ChatMessage> sendBound({
    required String accountId,
    required String conversationId,
    required String clientRequestId,
    required String content,
  }) =>
      _send(
        accountId: accountId,
        conversationId: conversationId,
        clientRequestId: clientRequestId,
        content: content,
      );

  Future<ChatMessage> _send({
    String? accountId,
    String? conversationId,
    required String clientRequestId,
    required String content,
  }) async {
    try {
      final response = await _client.post('/chat/messages',
          data: {
            'content': content.trim(),
            'client_request_id': clientRequestId,
            if (conversationId != null) 'conversation_id': conversationId,
          },
          options: _options(accountId));
      final raw = _dataMap(response.data);
      final message = ChatMessage.fromJson(raw);
      if (message.id.isEmpty ||
          !message.isMine ||
          message.content != content.trim() ||
          DateTime.tryParse(raw['created_at']?.toString() ?? '') == null ||
          (conversationId != null &&
              (message.conversationId != conversationId ||
                  message.clientRequestId != clientRequestId ||
                  message.cursor == null ||
                  message.cursor!.length > 1024))) {
        throw _invalid;
      }
      return message;
    } on DioException catch (error) {
      throw _error(error);
    } on FormatException {
      throw _invalid;
    }
  }

  Future<void> markRead() => _read();

  Future<void> markReadBound({
    required String accountId,
    required String conversationId,
    required String throughCursor,
    String? fromCursor,
  }) =>
      _read(
          accountId: accountId,
          conversationId: conversationId,
          throughCursor: throughCursor,
          fromCursor: fromCursor);

  Future<void> _read({
    String? accountId,
    String? conversationId,
    String? throughCursor,
    String? fromCursor,
  }) async {
    try {
      final response = await _client.patch('/chat/read',
          data: conversationId == null
              ? null
              : {
                  'conversation_id': conversationId,
                  'through_cursor': throughCursor,
                  if (fromCursor != null) 'from_cursor': fromCursor,
                },
          options: _options(accountId));
      if (conversationId != null) {
        final updated = _dataMap(response.data)['updated'];
        if (updated is! int || updated < 0) throw _invalid;
      }
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Options _options(String? accountId) => Options(
        headers: {
          'Cache-Control': 'no-store',
          if (accountId != null) 'X-Chat-Account-Id': accountId,
        },
        sendTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        followRedirects: false,
      );

  Map<String, dynamic> _dataMap(dynamic body) {
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) throw _invalid;
    return data;
  }

  static String createRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static const _invalid = ChatFailure(ChatFailureKind.invalidResponse,
      'The server returned invalid chat data. Try again safely.');

  ChatFailure _error(DioException error) {
    final status = error.response?.statusCode;
    // Do not echo arbitrary server bodies: they may contain private text or
    // debug details. User-facing failure classes are bounded and predictable.
    if (status == 401 || status == 403) {
      return ChatFailure(ChatFailureKind.accessDenied,
          'Secure chat access is no longer available.',
          statusCode: status);
    }
    if (status == 409) {
      return ChatFailure(ChatFailureKind.conversationChanged,
          'The conversation has changed. Reload chat.',
          statusCode: status);
    }
    if (status == 429) {
      return ChatFailure(ChatFailureKind.rateLimited,
          'Too many requests. Please wait before trying again.',
          statusCode: status);
    }
    if (status != null && status >= 500) {
      return ChatFailure(ChatFailureKind.server,
          'Chat could not confirm this request. Try again safely.',
          statusCode: status);
    }
    if (status != null) {
      return ChatFailure(
          ChatFailureKind.validation, 'Chat could not accept this request.',
          statusCode: status);
    }
    return const ChatFailure(ChatFailureKind.transport,
        'Could not connect to secure chat. Please try again.');
  }
}
