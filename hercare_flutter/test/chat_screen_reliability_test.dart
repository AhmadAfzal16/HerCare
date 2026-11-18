import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hercare/core/routing/app_router.dart';
import 'package:hercare/data/models/chat_models.dart';
import 'package:hercare/presentation/chat/secure_chat_screen.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mother = '00000000-0000-4000-8000-000000000001';
const _guardian = '00000000-0000-4000-8000-000000000002';
const _otherMother = '00000000-0000-4000-8000-000000000003';
const _conversation = '00000000-0000-4000-8000-000000000004';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uncertain send retains draft and explicit retry reuses UUID',
      (tester) async {
    final service = _Chat(uncertainOnce: true);
    final harness = await _mount(tester, service);
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'I need some support');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();

    expect(service.requestIds, hasLength(1));
    expect(_composer(tester).controller!.text, 'I need some support');
    expect(_composer(tester).enabled, false);
    expect(find.byKey(const Key('chat-pending-notice')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('chat-retry-pending')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-retry-pending')));
    await tester.pumpAndSettle();

    expect(service.requestIds, hasLength(2));
    expect(service.requestIds[1], service.requestIds[0]);
    expect(service.contents, ['I need some support', 'I need some support']);
    expect(harness.provider.messages.where((message) => message.isMine),
        hasLength(1));
    expect(_composer(tester).controller!.text, isEmpty);
    expect(_composer(tester).enabled, true);
    expect(find.byKey(const Key('chat-pending-notice')), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('discard removes only local attempt and its unchanged draft',
      (tester) async {
    final service = _Chat(uncertainOnce: true);
    final harness = await _mount(tester, service);
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'An uncertain message');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('chat-discard-pending')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-discard-pending')));
    await tester.pumpAndSettle();

    expect(service.requestIds, hasLength(1));
    expect(harness.provider.pendingAttempt, isNull);
    expect(_composer(tester).controller!.text, isEmpty);
    expect(_composer(tester).enabled, true);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('history confirms a committed pending send without replay',
      (tester) async {
    final service = _Chat(uncertainOnce: true, committedOnFailure: true);
    final harness = await _mount(tester, service);
    await tester.enterText(find.byKey(const Key('chat-composer')),
        'A committed uncertain message');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(harness.provider.pendingAttempt, isNotNull);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(service.requestIds, hasLength(1));
    expect(harness.provider.pendingAttempt, isNull);
    expect(harness.provider.messages.where((message) => message.isMine),
        hasLength(1));
    expect(_composer(tester).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('late send cannot erase a changed draft or open old safety UI',
      (tester) async {
    final service = _Chat()..pendingSend = Completer<ChatMessage>();
    final harness = await _mount(tester, service);
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'Original draft');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    // Simulate an editor update during an asynchronous completion. A response
    // is not permission to erase text that no longer matches its attempt.
    _composer(tester).controller!.text = 'A different current draft';
    service.pendingSend!.complete(service.accepted(
        accountId: _mother,
        content: 'Original draft',
        requestId: service.requestIds.single,
        danger: false));
    await tester.pumpAndSettle();
    expect(_composer(tester).controller!.text, 'A different current draft');

    service.pendingSend = Completer<ChatMessage>();
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'Previous account text');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pump();
    harness.provider.bindAccount(_otherMother, role: 'mother');
    await tester.pumpAndSettle();
    expect(_composer(tester).controller!.text, isEmpty);
    service.pendingSend!.complete(service.accepted(
        accountId: _mother,
        content: 'Previous account text',
        requestId: service.requestIds.last,
        danger: true));
    await tester.pumpAndSettle();
    expect(find.text('You are not alone'), findsNothing);
    expect(_composer(tester).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('hidden routes and background app stop polling and read markers',
      (tester) async {
    final service = _Chat();
    final navigator = GlobalKey<NavigatorState>();
    final harness = await _mount(tester, service, navigator: navigator);
    final initialReads = service.reads;
    expect(initialReads, greaterThan(0));

    navigator.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Covering route'))));
    await tester.pumpAndSettle();
    final coveredFetches = service.fetches;
    await tester.pump(const Duration(seconds: 12));
    expect(service.fetches, coveredFetches);
    expect(service.reads, initialReads);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(service.fetches, greaterThan(coveredFetches));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedFetches = service.fetches;
    final pausedReads = service.reads;
    await tester.pump(const Duration(seconds: 12));
    expect(service.fetches, pausedFetches);
    expect(service.reads, pausedReads);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('guardian danger text does not open a mother safety sheet',
      (tester) async {
    final service = _Chat(danger: true);
    final harness =
        await _mount(tester, service, account: _guardian, role: 'guardian');
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'A distressing message');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('You are not alone'), findsNothing);
    expect(find.byKey(const Key('chat-open-help')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets(
      'failed polls back off and resume ten-second cadence after success',
      (tester) async {
    final service = _Chat()..pollFailures = 3;
    final harness = await _mount(tester, service);
    final initial = service.fetches;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(service.fetches, initial + 1);
    await tester.pump(const Duration(seconds: 19));
    expect(service.fetches, initial + 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.fetches, initial + 2);
    await tester.pump(const Duration(seconds: 39));
    expect(service.fetches, initial + 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.fetches, initial + 3);
    await tester.pump(const Duration(seconds: 59));
    expect(service.fetches, initial + 3);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final successful = service.fetches;
    expect(successful, greaterThan(initial + 3));
    await tester.pump(const Duration(seconds: 9));
    expect(service.fetches, successful);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(service.fetches, greaterThan(successful));
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  for (final language in ['en', 'ur']) {
    testWidgets(
        'mother safety sheet scrolls in $language with 200% text and disappears after account change',
        (tester) async {
      final service = _Chat(danger: true);
      final harness = await _mount(tester, service,
          language: language, scale: 2, keyboard: 150);
      await tester.enterText(
          find.byKey(const Key('chat-composer')), 'A distressing message');
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-immediate-help')), findsOneWidget);
      expect(tester.takeException(), isNull);
      harness.provider.bindAccount(_guardian, role: 'guardian');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-immediate-help')), findsNothing);
      expect(_composer(tester).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
      await harness.dispose(tester);
    });
  }

  testWidgets('immediate help stays reachable while delivery is uncertain',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
    final service = _Chat(uncertainOnce: true);
    final provider = ChatProvider(service: service)
      ..bindAccount(_mother, role: 'mother');
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const SecureChatScreen()),
      GoRoute(
          path: AppRoutes.crisis,
          builder: (_, __) =>
              const Scaffold(body: Text('Immediate support without sending'))),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider.value(value: provider),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('chat-composer')), 'A pending message');
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-open-help')));
    await tester.pumpAndSettle();
    expect(find.text('Immediate support without sending'), findsOneWidget);
    expect(service.requestIds, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    provider.dispose();
  });

  testWidgets('network status failure is not presented as a missing link',
      (tester) async {
    final service = _Chat(statusUnavailable: true);
    final harness = await _mount(tester, service);
    expect(find.text('Could not connect to chat'), findsOneWidget);
    expect(find.text('Set up link'), findsNothing);
    expect(find.byKey(const Key('chat-open-help')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });

  testWidgets('prepending older messages preserves the visible reading anchor',
      (tester) async {
    final service = _Chat(withHistory: true);
    final harness = await _mount(tester, service);
    await tester.drag(
        find.byKey(const Key('chat-messages')), const Offset(0, 1600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('chat-load-earlier')));
    await tester.pumpAndSettle();
    final anchor = find.text('Current message 0 with enough words to wrap.');
    final before = tester.getTopLeft(anchor).dy;
    await tester.tap(find.byKey(const Key('chat-load-earlier')));
    await tester.pumpAndSettle();
    expect(harness.provider.messages, hasLength(15));
    expect((tester.getTopLeft(anchor).dy - before).abs(), lessThan(3));
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);
  });
}

TextField _composer(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('chat-composer')));

Future<_Harness> _mount(WidgetTester tester, _Chat service,
    {String account = _mother,
    String role = 'mother',
    String language = 'en',
    double scale = 1,
    double keyboard = 0,
    GlobalKey<NavigatorState>? navigator}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.binding.setSurfaceSize(const Size(320, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = ChatProvider(service: service)
    ..bindAccount(account, role: role);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ChangeNotifierProvider.value(value: provider),
    ],
    child: MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: const SecureChatScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return _Harness(provider);
}

class _Harness {
  _Harness(this.provider);
  final ChatProvider provider;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  }
}

class _Chat extends ChatService {
  _Chat({
    this.uncertainOnce = false,
    this.committedOnFailure = false,
    this.danger = false,
    this.statusUnavailable = false,
    this.withHistory = false,
  });

  final bool uncertainOnce;
  final bool committedOnFailure;
  final bool danger;
  final bool statusUnavailable;
  final bool withHistory;
  final List<String> requestIds = [];
  final List<String> contents = [];
  int fetches = 0;
  int reads = 0;
  int pollFailures = 0;
  Completer<ChatMessage>? pendingSend;
  final List<ChatMessage> committed = [];

  @override
  Future<ChatStatus> getStatusBound({required String accountId}) async {
    if (statusUnavailable) {
      throw const ChatFailure(
          ChatFailureKind.transport, 'Could not connect to chat.');
    }
    return const ChatStatus(
        available: true,
        unreadCount: 1,
        conversationId: _conversation,
        partnerName: 'Support Partner');
  }

  @override
  Future<ChatPage> getMessagePage({
    required String accountId,
    required String conversationId,
    String? before,
    String? after,
    int limit = 50,
  }) async {
    fetches++;
    if (after != null) {
      if (pollFailures > 0) {
        pollFailures--;
        throw const ChatFailure(
            ChatFailureKind.rateLimited, 'Please wait before retrying.');
      }
      if (committed.isNotEmpty && after != committed.last.cursor) {
        return ChatPage(
          conversationId: _conversation,
          messages: List.of(committed),
          hasMore: false,
          olderCursor: committed.first.cursor,
          newerCursor: committed.last.cursor,
        );
      }
      return const ChatPage(
          conversationId: _conversation, messages: [], hasMore: false);
    }
    final messages = before != null
        ? List.generate(
            5, (index) => _incoming(index - 5, 'Older message $index.'))
        : withHistory
            ? List.generate(
                10,
                (index) => _incoming(
                    index, 'Current message $index with enough words to wrap.'))
            : [
                _incoming(0, 'A supportive incoming message.'),
                ...committed,
              ];
    return ChatPage(
      conversationId: _conversation,
      messages: messages,
      hasMore: withHistory && before == null,
      olderCursor: messages.first.cursor,
      newerCursor: messages.last.cursor,
    );
  }

  ChatMessage _incoming(int index, String content) => ChatMessage(
        id: 'incoming_$index',
        senderId: _guardian,
        conversationId: _conversation,
        cursor: index < 0 ? 'older_${-index}' : 'cursor_$index',
        isMine: false,
        content: content,
        sentimentLabel: 'neutral',
        sentimentScore: 0,
        distressScore: 0,
        containsDanger: false,
        createdAt: DateTime.utc(2026, 10, 12).add(Duration(seconds: index)),
      );

  ChatMessage accepted({
    required String accountId,
    required String content,
    required String requestId,
    required bool danger,
  }) =>
      ChatMessage(
        id: 'accepted_$requestId',
        senderId: accountId,
        conversationId: _conversation,
        clientRequestId: requestId,
        cursor: 'accepted_cursor',
        isMine: true,
        content: content,
        sentimentLabel: 'neutral',
        sentimentScore: 0,
        distressScore: 0,
        containsDanger: danger,
        createdAt: DateTime.utc(2026, 10, 12, 0, 1),
      );

  @override
  Future<ChatMessage> sendBound({
    required String accountId,
    required String conversationId,
    required String clientRequestId,
    required String content,
  }) async {
    requestIds.add(clientRequestId);
    contents.add(content);
    if (uncertainOnce && requestIds.length == 1) {
      if (committedOnFailure) {
        committed.add(accepted(
            accountId: accountId,
            content: content,
            requestId: clientRequestId,
            danger: danger));
      }
      throw const ChatFailure(
          ChatFailureKind.transport, 'Delivery is uncertain.');
    }
    if (pendingSend != null) return pendingSend!.future;
    final message = accepted(
        accountId: accountId,
        content: content,
        requestId: clientRequestId,
        danger: danger);
    committed.add(message);
    return message;
  }

  @override
  Future<void> markReadBound({
    required String accountId,
    required String conversationId,
    required String throughCursor,
    String? fromCursor,
  }) async {
    reads++;
  }
}
