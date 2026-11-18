import 'dart:math';
import 'package:dio/dio.dart';
import '../data/models/chatbot_models.dart';
import '../data/services/api_service.dart';

/// Stateless authenticated transport: private histories are never globally cached.
class ChatbotService {
  ChatbotService({ApiService? api}) : _api = api ?? ApiService();
  final ApiService _api;

  Future<T> _request<T>(Future<Response<dynamic>> Function() call,
      T Function(Map<String, dynamic>) parse) async {
    try {
      final response = await call();
      final body = response.data;
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid chatbot response');
      }
      return parse(data);
    } on DioException catch (error) {
      // Never include private request/response text in a user-visible exception.
      if (error.response?.statusCode == 401) {
        throw Exception('Please sign in again.');
      }
      if (error.response?.statusCode == 403) {
        throw Exception('Chatbot access is not available for this account.');
      }
      throw Exception(
          'Hum-Raaz could not reach the server. Retry or use limited offline support.');
    }
  }

  Future<ChatbotStatus> status() =>
      _request(() => _api.get('/chatbot/status'), ChatbotStatus.fromJson);
  Future<ChatbotConsent> consent(bool enabled) => _request(
      () => _api.client.put('/chatbot/consent', data: {
            'enabled': enabled,
            'policy_version': 'chatbot-aggregate-v1',
          }),
      ChatbotConsent.fromJson);
  Future<ChatbotSessions> sessions({String? before}) => _request(
      () => _api.get('/chatbot/sessions', queryParameters: {
            'limit': 30,
            if (before != null) 'before': before,
          }),
      ChatbotSessions.fromJson);
  Future<ChatbotSession> createSession(String language) => _request(
      () => _api.post('/chatbot/sessions', data: {'language': language}),
      ChatbotSession.fromJson);
  Future<ChatbotHistory> messages(String sessionId, {String? before}) =>
      _request(
          () => _api.get('/chatbot/sessions/$sessionId/messages',
                  queryParameters: {
                    'limit': 30,
                    if (before != null) 'before': before,
                  }),
          ChatbotHistory.fromJson);
  Future<ChatbotSendResult> send(String sessionId,
          {required String message,
          required String language,
          required String requestId}) =>
      _request(
          () => _api.client.post('/chatbot/sessions/$sessionId/messages',
                  options: Options(receiveTimeout: const Duration(seconds: 60)),
                  data: {
                    'message': message,
                    'language': language,
                    'client_request_id': requestId,
                  }),
          ChatbotSendResult.fromJson);
  Future<void> deleteSession(String sessionId) =>
      _request(() => _api.delete('/chatbot/sessions/$sessionId'), (_) {});

  static String requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
