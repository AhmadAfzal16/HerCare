import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/chat_models.dart';
import '../data/services/api_service.dart';

class ChatService {
  ChatService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<ChatStatus> getStatus() async {
    try {
      final response = await _api.get('/chat/status');
      return ChatStatus.fromJson(_dataMap(response.data));
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<List<ChatMessage>> getMessages({
    DateTime? before,
    DateTime? after,
    int limit = 30,
  }) async {
    try {
      final response = await _api.get('/chat/messages', queryParameters: {
        if (before != null) 'before': before.toUtc().toIso8601String(),
        if (after != null) 'after': after.toUtc().toIso8601String(),
        'limit': limit,
      });
      final data = response.data is Map<String, dynamic>
          ? response.data['data']
          : null;
      if (data is! List) throw Exception('The server returned invalid chat data.');
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ChatMessage> send(String content) async {
    try {
      final response = await _api.post('/chat/messages', data: {
        'content': content.trim(),
        'client_request_id': _requestId(),
      });
      return ChatMessage.fromJson(_dataMap(response.data));
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> markRead() async {
    try {
      await _api.client.patch('/chat/read');
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Map<String, dynamic> _dataMap(dynamic body) {
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) {
      throw Exception('The server returned invalid chat data.');
    }
    return data;
  }

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Exception _error(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['message'] is String) {
      return Exception(body['message']);
    }
    return Exception('Could not connect to secure chat. Please try again.');
  }
}

