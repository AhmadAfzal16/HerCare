import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chat_models.dart';

void main() {
  test('chat message safely parses PostgreSQL numeric fields', () {
    final message = ChatMessage.fromJson({
      'id': 'message-id',
      'sender_id': 'sender-id',
      'is_mine': true,
      'content': 'I feel supported',
      'language': 'en',
      'sentiment_label': 'positive',
      'sentiment_score': '0.750',
      'distress_score': '0.125',
      'contains_danger': false,
      'created_at': '2026-09-24T00:00:00.000Z',
      'read_at': null,
    });

    expect(message.sentimentScore, .75);
    expect(message.distressScore, .125);
    expect(message.isRead, false);
  });

  test('unavailable chat status has safe defaults', () {
    final status = ChatStatus.fromJson({'available': false});
    expect(status.available, false);
    expect(status.unreadCount, 0);
    expect(status.partnerName, isNull);
  });
}

