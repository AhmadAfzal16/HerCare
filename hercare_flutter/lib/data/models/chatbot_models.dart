/// Private chatbot contracts. Unknown model status is never clinical validation.
class ChatbotConsent {
  const ChatbotConsent(
      {this.enabled = false, this.policyVersion = 'chatbot-aggregate-v1'});
  final bool enabled;
  final String policyVersion;
  factory ChatbotConsent.fromJson(Map<String, dynamic> json) => ChatbotConsent(
        enabled: json['enabled'] == true,
        policyVersion:
            json['policy_version'] as String? ?? 'chatbot-aggregate-v1',
      );
}

class ChatbotStatus {
  const ChatbotStatus(
      {required this.available,
      this.consent = const ChatbotConsent(),
      this.historyEncrypted = false});
  final bool available;
  final ChatbotConsent consent;
  final bool historyEncrypted;
  factory ChatbotStatus.fromJson(Map<String, dynamic> json) => ChatbotStatus(
        available: json['available'] == true,
        consent: ChatbotConsent.fromJson(_map(json['personalization'])),
        historyEncrypted: json['history_encrypted'] == true,
      );
}

class ChatbotSession {
  const ChatbotSession(
      {required this.id, required this.language, required this.createdAt});
  final String id;
  final String language;
  final DateTime createdAt;
  factory ChatbotSession.fromJson(Map<String, dynamic> json) => ChatbotSession(
        id: _requiredString(json, 'id'),
        language: _language(json['language']),
        createdAt: DateTime.parse(_requiredString(json, 'created_at')),
      );
}

class ChatbotMessage {
  const ChatbotMessage(
      {required this.id,
      required this.role,
      required this.content,
      required this.language,
      required this.createdAt,
      this.metadata = const {}});
  final String id;
  final String role;
  final String content;
  final String language;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;
  bool get isUser => role == 'user';
  factory ChatbotMessage.fromJson(Map<String, dynamic> json) {
    final role = _requiredString(json, 'role');
    if (role != 'user' && role != 'assistant') {
      throw const FormatException('Invalid chat role');
    }
    return ChatbotMessage(
        id: _requiredString(json, 'id'),
        role: role,
        content: _requiredString(json, 'content'),
        language: _language(json['language']),
        createdAt: DateTime.parse(_requiredString(json, 'created_at')),
        metadata: _map(json['reply_metadata']));
  }
}

class ChatbotHistory {
  const ChatbotHistory(
      {required this.messages, this.hasMore = false, this.nextCursor});
  final List<ChatbotMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  factory ChatbotHistory.fromJson(Map<String, dynamic> json) => ChatbotHistory(
        messages: _list(json['messages']).map(ChatbotMessage.fromJson).toList(),
        hasMore: json['has_more'] == true,
        nextCursor: json['next_cursor'] as String?,
      );
}

class ChatbotSessions {
  const ChatbotSessions(
      {required this.sessions, this.hasMore = false, this.nextCursor});
  final List<ChatbotSession> sessions;
  final bool hasMore;
  final String? nextCursor;
  factory ChatbotSessions.fromJson(Map<String, dynamic> json) =>
      ChatbotSessions(
        sessions: _list(json['sessions']).map(ChatbotSession.fromJson).toList(),
        hasMore: json['has_more'] == true,
        nextCursor: json['next_cursor'] as String?,
      );
}

class ChatbotSendResult {
  const ChatbotSendResult(
      {required this.status, required this.messages, this.reply = const {}});
  final String status;
  final List<ChatbotMessage> messages;
  final Map<String, dynamic> reply;
  factory ChatbotSendResult.fromJson(Map<String, dynamic> json) =>
      ChatbotSendResult(
        status: _requiredString(json, 'status'),
        messages: _list(json['messages']).map(ChatbotMessage.fromJson).toList(),
        reply: _map(json['reply']),
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : {};
List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw const FormatException('Invalid chatbot list');
  }
  return value.cast<Map<String, dynamic>>();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid chatbot $key');
  }
  return value;
}

String _language(dynamic value) =>
    const ['en', 'ur', 'roman_ur'].contains(value) ? value as String : 'en';
