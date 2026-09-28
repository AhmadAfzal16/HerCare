import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chat_models.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/services/chat_service.dart';

void main() {
  test('slow chat refreshes cannot overlap and empty polls do not mark read',
      () async {
    final service = _Chat();
    final provider = ChatProvider(service: service);
    await provider.initialize();
    service.pending = Completer<List<ChatMessage>>();
    final refresh = provider.refreshNew();
    await provider.refreshNew();
    expect(service.fetches, 2);
    service.pending!.complete([]);
    await refresh;
    expect(service.reads, 1);
    provider.dispose();
  });
}

class _Chat extends ChatService {
  int fetches = 0;
  int reads = 0;
  Completer<List<ChatMessage>>? pending;
  @override
  Future<ChatStatus> getStatus() async =>
      const ChatStatus(available: true, unreadCount: 0);
  @override
  Future<List<ChatMessage>> getMessages(
      {DateTime? before, DateTime? after, int limit = 30}) {
    fetches++;
    return pending?.future ?? Future.value([]);
  }

  @override
  Future<void> markRead() async {
    reads++;
  }
}
