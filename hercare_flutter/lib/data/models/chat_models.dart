class ChatStatus {
  const ChatStatus({
    required this.available,
    required this.unreadCount,
    this.conversationId,
    this.partnerName,
    this.lastMessageAt,
    this.privacy,
  });

  final bool available;
  final int unreadCount;
  final String? conversationId;
  final String? partnerName;
  final DateTime? lastMessageAt;
  final String? privacy;

  factory ChatStatus.fromJson(Map<String, dynamic> json) => ChatStatus(
        available: json['available'] == true,
        unreadCount: _count(json['unread_count']),
        conversationId: json['conversation_id']?.toString(),
        partnerName: json['partner_name']?.toString(),
        lastMessageAt:
            DateTime.tryParse(json['last_message_at']?.toString() ?? ''),
        privacy: json['privacy']?.toString(),
      );

  static int _count(dynamic value) {
    if (value is num && !value.isFinite) {
      return 0;
    }
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.isMine,
    required this.content,
    required this.sentimentLabel,
    required this.sentimentScore,
    required this.distressScore,
    required this.containsDanger,
    required this.createdAt,
    this.readAt,
    this.language = 'en',
    this.conversationId,
    this.clientRequestId,
    this.cursor,
  });

  final String id;
  final String senderId;
  final bool isMine;
  final String content;
  final String language;
  final String sentimentLabel;
  final double sentimentScore;
  final double distressScore;
  final bool containsDanger;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? conversationId;
  final String? clientRequestId;
  final String? cursor;

  bool get isRead => readAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        isMine: json['is_mine'] == true,
        content: json['content']?.toString() ?? '',
        language: json['language']?.toString() ?? 'en',
        sentimentLabel: json['sentiment_label']?.toString() ?? 'neutral',
        sentimentScore: _number(json['sentiment_score']),
        distressScore: _number(json['distress_score']),
        containsDanger: json['contains_danger'] == true,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
        conversationId: json['conversation_id']?.toString(),
        clientRequestId: json['client_request_id']?.toString(),
        cursor: json['cursor']?.toString(),
      );

  static double _number(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : 0;
  }

  /// Database timestamp precision and the UUID together define a total order.
  static int compare(ChatMessage first, ChatMessage second) {
    final timestamp = first.createdAt.compareTo(second.createdAt);
    return timestamp == 0 ? first.id.compareTo(second.id) : timestamp;
  }
}

class ChatPage {
  const ChatPage({
    required this.conversationId,
    required this.messages,
    required this.hasMore,
    this.olderCursor,
    this.newerCursor,
  });

  final String conversationId;
  final List<ChatMessage> messages;
  final bool hasMore;
  final String? olderCursor;
  final String? newerCursor;

  factory ChatPage.fromJson(Map<String, dynamic> json) {
    final conversation = json['conversation_id'];
    final rawMessages = json['messages'];
    if (conversation is! String ||
        conversation.isEmpty ||
        rawMessages is! List ||
        rawMessages.length > 50 ||
        json['has_more'] is! bool ||
        !_validCursor(json['older_cursor']) ||
        !_validCursor(json['newer_cursor'])) {
      throw const FormatException('Invalid chat page.');
    }
    final parsed = <ChatMessage>[];
    final identifiers = <String>{};
    for (final raw in rawMessages) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid chat message.');
      }
      final message = ChatMessage.fromJson(raw);
      if (message.id.isEmpty ||
          message.conversationId != conversation ||
          message.senderId.isEmpty ||
          message.content.length > 2000 ||
          !_validCursor(message.cursor) ||
          message.cursor == null ||
          DateTime.tryParse(raw['created_at']?.toString() ?? '') == null ||
          !identifiers.add(message.id) ||
          (parsed.isNotEmpty &&
              ChatMessage.compare(parsed.last, message) >= 0)) {
        throw const FormatException('Invalid or unordered chat message.');
      }
      parsed.add(message);
    }
    final older = json['older_cursor'] as String?;
    final newer = json['newer_cursor'] as String?;
    // An empty initial conversation supplies an origin newer cursor so its
    // first burst can be drained oldest-first without a timestamp-only gap.
    if ((parsed.isEmpty && older != null) ||
        (parsed.isNotEmpty &&
            (older != parsed.first.cursor || newer != parsed.last.cursor)) ||
        (json['has_more'] == true && parsed.isEmpty)) {
      throw const FormatException('Invalid chat page boundary.');
    }
    return ChatPage(
      conversationId: conversation,
      messages: List.unmodifiable(parsed),
      hasMore: json['has_more'] as bool,
      olderCursor: older,
      newerCursor: newer,
    );
  }

  static bool _validCursor(dynamic value) =>
      value == null ||
      (value is String &&
          value.isNotEmpty &&
          value.length <= 1024 &&
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value));
}
