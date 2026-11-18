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

  test('numeric status strings and non-finite sentiment are safe', () {
    expect(ChatStatus.fromJson({'unread_count': '7'}).unreadCount, 7);
    expect(ChatStatus.fromJson({'unread_count': '-1'}).unreadCount, 0);
    expect(ChatStatus.fromJson({'unread_count': double.infinity}).unreadCount, 0);
    expect(ChatMessage.fromJson({'sentiment_score': 'NaN'}).sentimentScore, 0);
  });

  test('message comparison preserves microseconds and UUID tie ordering', () {
    final first = ChatMessage.fromJson({
      'id': 'b',
      'created_at': '2026-10-12T09:20:30.123456Z',
    });
    final tied = ChatMessage.fromJson({
      'id': 'a',
      'created_at': '2026-10-12T09:20:30.123456Z',
    });
    final later = ChatMessage.fromJson({
      'id': '0',
      'created_at': '2026-10-12T09:20:30.123457Z',
    });
    expect(first.createdAt.microsecond, 456);
    expect(ChatMessage.compare(tied, first), lessThan(0));
    expect(ChatMessage.compare(first, later), lessThan(0));
  });

  test('page validates pinned conversation, chronological order and cursors',
      () {
    Map<String, dynamic> row(String id, String cursor) => {
          'id': id,
          'sender_id': 'sender',
          'conversation_id': 'conversation',
          'content': 'hello',
          'created_at': '2026-10-12T09:20:30.123456Z',
          'cursor': cursor,
        };
    final body = {
      'conversation_id': 'conversation',
      'messages': [row('a', 'cursor_a'), row('b', 'cursor_b')],
      'has_more': true,
      'older_cursor': 'cursor_a',
      'newer_cursor': 'cursor_b',
    };
    expect(ChatPage.fromJson(body).messages.length, 2);
    expect(() => ChatPage.fromJson({...body, 'conversation_id': 'other'}),
        throwsFormatException);
    expect(
        () => ChatPage.fromJson({
              ...body,
              'messages': [row('b', 'cursor_b'), row('a', 'cursor_a')],
            }),
        throwsFormatException);
    expect(() => ChatPage.fromJson({...body, 'newer_cursor': 'wrong'}),
        throwsFormatException);
    expect(
        () => ChatPage.fromJson({
              ...body,
              'messages': [null]
            }),
        throwsFormatException);
  });

  test('empty initial page allows origin cursor but not a phantom older page',
      () {
    final body = {
      'conversation_id': 'conversation',
      'messages': <dynamic>[],
      'has_more': false,
      'older_cursor': null,
      'newer_cursor': 'origin_cursor',
    };
    expect(ChatPage.fromJson(body).newerCursor, 'origin_cursor');
    expect(() => ChatPage.fromJson({...body, 'older_cursor': 'phantom'}),
        throwsFormatException);
    expect(() => ChatPage.fromJson({...body, 'has_more': true}),
        throwsFormatException);
  });
}
