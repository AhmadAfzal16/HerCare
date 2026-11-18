import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chat_models.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/services/chat_service.dart';

const _account = '11111111-1111-4111-8111-111111111111';
const _otherAccount = '22222222-2222-4222-8222-222222222222';
const _conversation = '33333333-3333-4333-8333-333333333333';
const _requestId = '44444444-4444-4444-8444-444444444444';
const _origin = 'origin_cursor';
final _time = DateTime.utc(2026, 10, 12, 12);

ChatMessage _message(int number,
        {String conversation = _conversation,
        String? requestId,
        bool mine = false,
        String? content,
        DateTime? time,
        DateTime? readAt}) =>
    ChatMessage(
      id: number.toString().padLeft(6, '0'),
      senderId: mine ? _account : _otherAccount,
      isMine: mine,
      content: content ?? 'Message $number',
      sentimentLabel: 'neutral',
      sentimentScore: 0,
      distressScore: 0,
      containsDanger: false,
      createdAt: time ?? _time,
      readAt: readAt,
      conversationId: conversation,
      clientRequestId: requestId,
      cursor: 'cursor_${number.toString().padLeft(6, '0')}',
    );

ChatPage _page(List<ChatMessage> rows,
        {bool more = false, bool initial = false}) =>
    ChatPage(
      conversationId: _conversation,
      messages: rows,
      hasMore: more,
      olderCursor: rows.isEmpty ? null : rows.first.cursor,
      newerCursor: rows.isEmpty ? (initial ? _origin : null) : rows.last.cursor,
    );

ChatProvider _provider(_Chat service, {DateTime Function()? clock}) =>
    ChatProvider(
        service: service, requestIdFactory: () => _requestId, clock: clock)
      ..bindAccount(_account, role: 'mother')
      ..setVisible(true);

void main() {
  test('slow refreshes coalesce, empty polls do not fetch receipt window/read',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.pendingPage = Completer<ChatPage>();
    final refresh = provider.refreshNew();
    await provider.refreshNew();
    expect(service.pages.length, 2);
    expect(service.pages.last.after, 'cursor_000001');
    service.pendingPage!.complete(_page([]));
    await refresh;
    expect(service.pages.length, 2);
    expect(service.reads, isEmpty);
    provider.dispose();
  });

  test('same-timestamp rows and bursts over thirty drain without skips',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.forwardRows = [
      for (var number = 2; number <= 127; number++) _message(number)
    ];
    await provider.refreshNew();
    expect(provider.messages.length, 127);
    expect(provider.messages.first.id, '000001');
    expect(provider.messages.last.id, '000127');
    expect(service.pages.skip(1).map((page) => page.after),
        ['cursor_000001', 'cursor_000051', 'cursor_000101']);
    expect(provider.hasForwardBacklog, false);
    provider.dispose();
  });

  test('bounded forward cycle retains highwater for remaining backlog',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.forwardRows = [
      for (var number = 2; number <= 302; number++) _message(number)
    ];
    await provider.refreshNew();
    expect(provider.messages.last.id, '000251');
    expect(provider.hasForwardBacklog, true);
    expect(service.pages.length, 6);
    await provider.refreshNew();
    expect(service.pages[6].after, 'cursor_000251');
    expect(provider.messages.last.id, '000302');
    expect(provider.hasForwardBacklog, false);
    provider.dispose();
  });

  test('empty conversation origin drains first burst from oldest row',
      () async {
    final service = _Chat();
    final provider = _provider(service);
    await provider.initialize();
    service.forwardRows = [
      for (var number = 1; number <= 101; number++) _message(number)
    ];
    await provider.refreshNew();
    expect(service.pages[1].after, _origin);
    expect(provider.messages.length, 101);
    expect(provider.messages.first.id, '000001');
    provider.dispose();
  });

  test('non-progressing forward pages are rejected without moving highwater',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.pageOverride = (_, after) =>
        after != null ? Future.value(_page([_message(1)], more: true)) : null;
    await provider.refreshNew();
    expect(provider.messages.length, 1);
    expect(provider.failure?.kind, ChatFailureKind.invalidResponse);
    service.pageOverride = null;
    service.forwardRows = [_message(2)];
    await provider.refreshNew();
    expect(service.pages.last.after, 'cursor_000001');
    expect(provider.messages.length, 2);
    provider.dispose();
  });

  test('receipt refresh is throttled and does not import unseen rows',
      () async {
    var now = _time;
    final mine = _message(1, mine: true);
    final service = _Chat()..initial = [mine];
    final provider = _provider(service, clock: () => now);
    await provider.initialize();
    await provider.refreshNew();
    expect(service.pages.length, 2);
    now = now.add(const Duration(seconds: 31));
    service.initial = [_message(1, mine: true, readAt: now), _message(2)];
    await provider.refreshNew();
    expect(service.pages.length, 4);
    expect(provider.messages.length, 1);
    expect(provider.messages.single.isRead, true);
    service.forwardRows = [_message(2)];
    await provider.refreshNew();
    expect(service.pages.last.after, 'cursor_000001');
    expect(provider.messages.length, 2);
    provider.dispose();
  });

  test('timeout keeps immutable UUID/content and explicit retry reuses both',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendFailure =
        const ChatFailure(ChatFailureKind.transport, 'Offline');
    expect(await provider.send('  Original message  '), false);
    final original = provider.pendingAttempt!;
    expect(original.content, 'Original message');
    expect(original.requestId, _requestId);
    expect(provider.canSend, false);
    expect(await provider.send('Changed composer text'), false);
    expect(service.sends.length, 1);
    service.sendFailure = null;
    expect(await provider.retryPending(), true);
    expect(service.sends.length, 2);
    expect(service.sends[0], service.sends[1]);
    expect(provider.pendingAttempt, isNull);
    expect(provider.lastSentMessage?.content, 'Original message');
    provider.dispose();
  });

  test('uncertain attempt survives safe same-conversation reload', () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendFailure = const ChatFailure(ChatFailureKind.server, 'Busy');
    await provider.send('Original');
    await provider.initialize();
    expect(provider.pendingAttempt?.content, 'Original');
    expect(provider.failure?.deliveryUncertain, true);
    service.sendFailure = null;
    expect(await provider.retryPending(), true);
    provider.dispose();
  });

  test('definitive validation/rate limit do not retain send attempts',
      () async {
    for (final kind in [
      ChatFailureKind.validation,
      ChatFailureKind.rateLimited
    ]) {
      final service = _Chat()..initial = [_message(1)];
      final provider = _provider(service);
      await provider.initialize();
      service.sendFailure = ChatFailure(kind, 'Rejected');
      expect(await provider.send('No commit'), false);
      expect(provider.pendingAttempt, isNull);
      expect(await provider.retryPending(), false);
      expect(provider.failure?.kind, kind);
      provider.dispose();
    }
  });

  test('committed history reconciles pending request without another send',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendFailure =
        const ChatFailure(ChatFailureKind.transport, 'Offline');
    await provider.send('Maybe committed');
    service.forwardRows = [
      _message(2, mine: true, requestId: _requestId, content: 'Maybe committed')
    ];
    await provider.refreshNew();
    expect(provider.pendingAttempt, isNull);
    expect(provider.lastSentMessage?.id, '000002');
    expect(provider.error, isNull);
    expect(service.sends.length, 1);
    provider.dispose();
  });

  test('accepted own send cannot skip unseen partner rows or advance read',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendNumber = 100;
    expect(await provider.send('Later own message'), true);
    await provider.markVisibleRead();
    expect(service.reads.single.throughCursor, 'cursor_000001');
    service.forwardRows = [
      for (var number = 2; number <= 99; number++) _message(number),
      _message(100,
          mine: true, requestId: _requestId, content: 'Later own message')
    ];
    await provider.refreshNew();
    expect(service.pages[1].after, 'cursor_000001');
    expect(provider.messages.length, 100);
    expect(provider.messages[98].id, '000099');
    provider.dispose();
  });

  test('read receipt failures neither erase successful send nor fabricate read',
      () async {
    var now = _time;
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service, clock: () => now);
    await provider.initialize();
    expect(await provider.send('Accepted'), true);
    service.readFailure =
        const ChatFailure(ChatFailureKind.transport, 'Offline');
    await provider.markVisibleRead();
    expect(provider.lastSentMessage?.content, 'Accepted');
    expect(provider.error, isNull);
    expect(provider.readReceiptError, isNotNull);
    expect(provider.messages.first.isRead, false);
    expect(provider.pendingAttempt, isNull);
    service.readFailure = null;
    await provider.markVisibleRead();
    expect(service.reads.length, 1);
    now = now.add(const Duration(seconds: 31));
    await provider.markVisibleRead();
    expect(service.reads.length, 2);
    await provider.markVisibleRead();
    expect(service.reads.length, 2);
    provider.dispose();
  });

  test('read acknowledges loaded range, not earlier unseen fifty-plus history',
      () async {
    final service = _Chat()
      ..allRows = [
        for (var number = 1; number <= 100; number++) _message(number)
      ]
      ..initial = [
        for (var number = 51; number <= 100; number++) _message(number)
      ]
      ..initialMore = true;
    final provider = _provider(service);
    await provider.initialize();
    await provider.markVisibleRead();
    expect(service.reads.single.fromCursor, 'cursor_000051');
    expect(service.reads.single.throughCursor, 'cursor_000100');
    await provider.loadOlder();
    await provider.markVisibleRead();
    expect(service.reads.last.fromCursor, 'cursor_000001');
    expect(service.reads.last.throughCursor, 'cursor_000100');
    expect(service.reads.length, 2);
    provider.dispose();
  });

  test('hidden routes never poll or mark read; late read denied clears state',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    provider.setVisible(false);
    await provider.refreshNew();
    await provider.markVisibleRead();
    expect(service.pages.length, 1);
    expect(service.reads, isEmpty);
    provider.setVisible(true);
    service.readFailure =
        const ChatFailure(ChatFailureKind.accessDenied, 'Access withdrawn');
    await provider.markVisibleRead();
    expect(provider.messages, isEmpty);
    expect(provider.status, isNull);
    expect(provider.pendingAttempt, isNull);
    provider.dispose();
  });

  test('account switch discards messages and ignores late fetch completion',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.pendingPage = Completer<ChatPage>();
    final refresh = provider.refreshNew();
    provider.bindAccount(_otherAccount, role: 'guardian');
    expect(provider.messages, isEmpty);
    expect(provider.status, isNull);
    service.pendingPage!.complete(_page([_message(2)]));
    await refresh;
    expect(provider.messages, isEmpty);
    expect(provider.accountId, _otherAccount);
    expect(provider.role, 'guardian');
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('account switch ignores late send and does not expose its pending draft',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.pendingSend = Completer<ChatMessage>();
    final sending = provider.send('Private mother draft');
    provider.bindAccount(_otherAccount, role: 'guardian');
    service.pendingSend!.complete(_message(2,
        mine: true, requestId: _requestId, content: 'Private mother draft'));
    expect(await sending, false);
    expect(provider.messages, isEmpty);
    expect(provider.pendingAttempt, isNull);
    expect(provider.lastSentMessage, isNull);
    provider.dispose();
  });

  test('account switch ignores late status and disposal ignores completion',
      () async {
    final service = _Chat()..pendingStatus = Completer<ChatStatus>();
    final provider = _provider(service);
    final initializing = provider.initialize();
    provider.bindAccount(_otherAccount, role: 'guardian');
    service.pendingStatus!.complete(const ChatStatus(
        available: true, unreadCount: 0, conversationId: _conversation));
    await initializing;
    expect(service.pages, isEmpty);
    service.pendingStatus = null;
    await provider.initialize();
    provider.setVisible(true);
    service.pendingPage = Completer<ChatPage>();
    final refreshing = provider.refreshNew();
    provider.dispose();
    service.pendingPage!.complete(_page([_message(1)]));
    await refreshing;
    expect(provider.messages, isEmpty);
  });

  test('access denial and conversation conflict clear all private state',
      () async {
    for (final kind in [
      ChatFailureKind.accessDenied,
      ChatFailureKind.conversationChanged
    ]) {
      final service = _Chat()..initial = [_message(1)];
      final provider = _provider(service);
      await provider.initialize();
      service.sendFailure =
          const ChatFailure(ChatFailureKind.transport, 'Offline');
      await provider.send('Pinned draft');
      service.pageFailure = ChatFailure(kind, 'Not available');
      await provider.refreshNew();
      expect(provider.messages, isEmpty);
      expect(provider.status, isNull);
      expect(provider.pendingAttempt, isNull);
      expect(provider.failure?.kind, kind);
      expect(await provider.retryPending(), false);
      provider.dispose();
    }
  });

  test('changed conversation on reload never retargets pending attempt',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendFailure =
        const ChatFailure(ChatFailureKind.transport, 'Offline');
    await provider.send('Original recipient only');
    service.conversation = 'other-conversation';
    await provider.initialize();
    expect(provider.pendingAttempt, isNull);
    expect(provider.messages, isEmpty);
    expect(provider.failure?.kind, ChatFailureKind.conversationChanged);
    expect(service.sends.length, 1);
    provider.dispose();
  });

  test('status withdrawal and relink invalidate generation without pending',
      () async {
    for (final withdrawal in [true, false]) {
      final service = _Chat()..initial = [_message(1)];
      final provider = _provider(service);
      await provider.initialize();
      final generation = provider.generation;
      if (withdrawal) {
        service.available = false;
      } else {
        service.conversation = 'new-conversation';
      }
      await provider.initialize();
      expect(provider.generation, greaterThan(generation));
      expect(provider.messages, isEmpty);
      expect(provider.status, isNull);
      expect(
          provider.failure?.kind,
          withdrawal
              ? ChatFailureKind.accessDenied
              : ChatFailureKind.conversationChanged);
      expect(service.pages.length, 1);
      provider.dispose();
    }
  });

  test('bounded older window still pages earlier and can return to latest',
      () async {
    final service = _Chat()
      ..allRows = [
        for (var number = 1; number <= 1100; number++) _message(number)
      ]
      ..initial = [
        for (var number = 1051; number <= 1100; number++) _message(number)
      ]
      ..initialMore = true;
    final provider = _provider(service);
    await provider.initialize();
    for (var index = 0; index < 11; index++) {
      await provider.loadOlder();
    }
    expect(provider.messages.length, ChatProvider.maxMessages);
    expect(provider.messages.first.id, '000501');
    expect(provider.messages.last.id, '001000');
    expect(provider.historyLimited, true);
    expect(provider.isAtLatest, false);
    expect(provider.hasMore, true);
    final priorFetches = service.pages.length;
    await provider.refreshNew();
    expect(service.pages.length, priorFetches);
    await provider.loadOlder();
    expect(provider.messages.first.id, '000451');
    expect(provider.messages.last.id, '000950');
    await provider.returnToLatest();
    expect(provider.messages.first.id, '001051');
    expect(provider.messages.last.id, '001100');
    expect(provider.isAtLatest, true);
    provider.dispose();
  });

  test('read after account switch is pinned to original account and ignored',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.pendingRead = Completer<void>();
    final reading = provider.markVisibleRead();
    expect(service.reads.single.accountId, _account);
    provider.bindAccount(_otherAccount, role: 'guardian');
    service.pendingRead!.complete();
    await reading;
    expect(provider.messages, isEmpty);
    expect(provider.readReceiptError, isNull);
    provider.dispose();
  });

  test(
      'discard is explicit, memory only, and role change removes private state',
      () async {
    final service = _Chat()..initial = [_message(1)];
    final provider = _provider(service);
    await provider.initialize();
    service.sendFailure =
        const ChatFailure(ChatFailureKind.transport, 'Offline');
    await provider.send('Draft');
    provider.discardPending();
    expect(provider.pendingAttempt, isNull);
    expect(provider.error, isNull);
    await provider.send('Draft again');
    provider.bindAccount(_account, role: 'guardian');
    expect(provider.messages, isEmpty);
    expect(provider.pendingAttempt, isNull);
    expect(provider.role, 'guardian');
    provider.bindAccount(null);
    expect(provider.accountId, isNull);
    expect(provider.role, isNull);
    provider.dispose();
  });
}

class _PageRequest {
  const _PageRequest(
      this.accountId, this.conversationId, this.before, this.after);
  final String accountId;
  final String conversationId;
  final String? before;
  final String? after;
}

class _ReadRequest {
  const _ReadRequest(
      this.accountId, this.conversationId, this.throughCursor, this.fromCursor);
  final String accountId;
  final String conversationId;
  final String throughCursor;
  final String? fromCursor;
}

class _Chat extends ChatService {
  String conversation = _conversation;
  bool available = true;
  List<ChatMessage> initial = [];
  bool initialMore = false;
  List<ChatMessage> forwardRows = [];
  List<ChatMessage> allRows = [];
  final List<_PageRequest> pages = [];
  final List<_ReadRequest> reads = [];
  final List<Map<String, String>> sends = [];
  Completer<ChatStatus>? pendingStatus;
  Completer<ChatPage>? pendingPage;
  Completer<ChatMessage>? pendingSend;
  Completer<void>? pendingRead;
  ChatFailure? sendFailure;
  ChatFailure? pageFailure;
  ChatFailure? readFailure;
  int sendNumber = 2;
  Future<ChatPage>? Function(String? before, String? after)? pageOverride;

  @override
  Future<ChatStatus> getStatusBound({required String accountId}) =>
      pendingStatus?.future ??
      Future.value(ChatStatus(
          available: available, unreadCount: 0, conversationId: conversation));

  @override
  Future<ChatPage> getMessagePage({
    required String accountId,
    required String conversationId,
    String? before,
    String? after,
    int limit = 50,
  }) {
    pages.add(_PageRequest(accountId, conversationId, before, after));
    if (pageFailure != null) return Future.error(pageFailure!);
    if (pendingPage != null) return pendingPage!.future;
    final overridden = pageOverride?.call(before, after);
    if (overridden != null) return overridden;
    if (before != null) {
      final cursorNumber = int.parse(before.substring('cursor_'.length));
      final available =
          allRows.where((row) => int.parse(row.id) < cursorNumber).toList();
      final start = available.length > limit ? available.length - limit : 0;
      return Future.value(_page(available.sublist(start), more: start > 0));
    }
    if (after != null) {
      final cursorNumber =
          after == _origin ? 0 : int.parse(after.substring('cursor_'.length));
      final available =
          forwardRows.where((row) => int.parse(row.id) > cursorNumber).toList();
      return Future.value(_page(available.take(limit).toList(),
          more: available.length > limit));
    }
    return Future.value(_page(initial, more: initialMore, initial: true));
  }

  @override
  Future<ChatMessage> sendBound({
    required String accountId,
    required String conversationId,
    required String clientRequestId,
    required String content,
  }) {
    sends.add({
      'account': accountId,
      'conversation': conversationId,
      'request': clientRequestId,
      'content': content,
    });
    if (sendFailure != null) return Future.error(sendFailure!);
    return pendingSend?.future ??
        Future.value(_message(sendNumber,
            mine: true, requestId: clientRequestId, content: content));
  }

  @override
  Future<void> markReadBound({
    required String accountId,
    required String conversationId,
    required String throughCursor,
    String? fromCursor,
  }) {
    reads.add(
        _ReadRequest(accountId, conversationId, throughCursor, fromCursor));
    if (readFailure != null) return Future.error(readFailure!);
    return pendingRead?.future ?? Future.value();
  }
}
