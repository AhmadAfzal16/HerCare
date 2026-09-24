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
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        conversationId: json['conversation_id']?.toString(),
        partnerName: json['partner_name']?.toString(),
        lastMessageAt: DateTime.tryParse(json['last_message_at']?.toString() ?? ''),
        privacy: json['privacy']?.toString(),
      );
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
      );

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

