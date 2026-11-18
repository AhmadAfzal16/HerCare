import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chatbot_models.dart';
import 'package:hercare/presentation/hum_raaz/hum_raaz_screen.dart';
import 'package:hercare/presentation/hum_raaz/offline_support.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/chatbot_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('strict message parsing, private metadata and opaque cursors', () {
    final history = ChatbotHistory.fromJson({
      'messages': [
        {
          'id': 'assistant-id',
          'role': 'assistant',
          'content': 'Support, not diagnosis.',
          'language': 'roman_ur',
          'created_at': '2026-10-08T12:00:00Z',
          'reply_metadata': {
            'clinical_validation': false,
            'mode': 'grounded_support'
          },
        }
      ],
      'has_more': true,
      'next_cursor': 'opaque:cursor'
    });
    expect(history.nextCursor, 'opaque:cursor');
    expect(history.messages.single.isUser, false);
    expect(history.messages.single.metadata['clinical_validation'], false);
    expect(() => ChatbotMessage.fromJson({'id': 'x', 'role': 'system'}),
        throwsFormatException);
    expect(ChatbotConsent.fromJson({}).enabled, false);
    expect(
        ChatbotService.requestId(),
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test(
      'fixed offline safety support works in three scripts without pretending to notify',
      () {
    for (final text in [
      'I want to kill myself',
      'mujhe khudkushi karni hai',
      'میں خودکشی کرنا چاہتی ہوں',
      'I might harm my baby'
    ]) {
      expect(OfflineSupport.needsImmediateHelp(text), true);
    }
    expect(OfflineSupport.needsImmediateHelp('I am tired today'), false);
    expect(OfflineSupport.reply('en', urgent: true),
        contains('cannot notify your guardian'));
    expect(OfflineSupport.reply('roman_ur'), contains('live AI chat nahi'));
  });

  for (final language in ['en', 'ur']) {
    testWidgets(
        'chatbot wraps at 280 pixels with keyboard and large $language text',
        (tester) async {
      final service = _FakeChatbotService();
      await _mount(tester, service, language: language, keyboard: true);
      final composer = find.byKey(const ValueKey('chatbot-composer'));
      await _reveal(tester, composer);
      await tester.enterText(
          composer,
          language == 'ur'
              ? 'مجھے مدد چاہیے'
              : 'Please help me understand my check-ins.');
      await _reveal(tester, find.byIcon(Icons.send));
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(service.languages.single, language);
      expect(
          find.text(
              'A supportive response grounded in HerCare guidance, not a diagnosis or a clinical forecast.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Roman Urdu is an explicit reply option and preserves app default',
      (tester) async {
    final service = _FakeChatbotService();
    await _mount(tester, service);
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roman Urdu'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('chatbot-composer')));
    await tester.enterText(
        find.byKey(const ValueKey('chatbot-composer')), 'Aaj udaas hoon');
    await _reveal(tester, find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(service.languages.single, 'roman_ur');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed send never retries automatically and manual retry preserves UUID',
      (tester) async {
    final service = _FakeChatbotService()..failFirstSend = true;
    await _mount(tester, service);
    await _reveal(tester, find.byKey(const ValueKey('chatbot-composer')));
    await tester.enterText(
        find.byKey(const ValueKey('chatbot-composer')), 'Private test message');
    await _reveal(tester, find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(service.requestIds.length, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(service.requestIds.length, 1);
    await _reveal(tester, find.text('Retry same message'));
    await tester.tap(find.text('Retry same message'));
    await tester.pumpAndSettle();
    expect(service.requestIds.length, 2);
    expect(service.requestIds.first, service.requestIds.last);
    await _reveal(tester, find.text('Private test message'));
    expect(find.text('Private test message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'server failure offers explicit offline support and uploads no offline text',
      (tester) async {
    final service = _FakeChatbotService()..unavailable = true;
    await _mount(tester, service);
    await _reveal(tester, find.text('Limited offline support'));
    await tester.tap(find.text('Limited offline support'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('chatbot-composer')));
    await tester.enterText(find.byKey(const ValueKey('chatbot-composer')),
        'I want to hurt myself');
    await _reveal(tester, find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(service.requestIds, isEmpty);
    await _reveal(tester, find.textContaining('Please seek human help now.'));
    expect(find.textContaining('Please seek human help now.'), findsOneWidget);
    expect(find.text('Fixed offline guide'), findsOneWidget);
    expect(find.text('Grounding card'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account key change disposes private in-memory messages',
      (tester) async {
    final service = _FakeChatbotService();
    await _mount(tester, service, accountKey: 'first');
    await _reveal(tester, find.byKey(const ValueKey('chatbot-composer')));
    await tester.enterText(find.byKey(const ValueKey('chatbot-composer')),
        'First account private message');
    await _reveal(tester, find.byIcon(Icons.send));
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('First account private message'));
    expect(find.text('First account private message'), findsOneWidget);
    await _mount(tester, service, accountKey: 'second');
    expect(find.text('First account private message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'aggregate personalisation needs confirmation and can be withdrawn',
      (tester) async {
    final service = _FakeChatbotService();
    await _mount(tester, service);
    await tester.tap(find.text('Conversation & privacy'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byType(Switch));
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(service.consentChanges, isEmpty);
    expect(find.textContaining('This does not enable guardian alerts.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('I agree'));
    await tester.tap(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(service.consentChanges, [true]);
    await _reveal(tester, find.byType(Switch));
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(service.consentChanges, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'private history opens its own session and deletion removes that thread',
      (tester) async {
    final service = _FakeChatbotService()..hasHistory = true;
    await _mount(tester, service);
    await tester.tap(find.text('Conversation & privacy'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('History'));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-10-08'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Previously saved private support.'));
    expect(service.historyRequests, ['past-private-session']);
    await _reveal(tester, find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this conversation?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(service.deleted, ['past-private-session']);
    expect(find.text('Previously saved private support.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester.widget<ListView>(find.byType(ListView).first).controller!.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(finder, 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _mount(WidgetTester tester, ChatbotService service,
    {String language = 'en',
    bool keyboard = false,
    String accountKey = 'account'}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.binding.setSurfaceSize(const Size(280, 520));
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 200 : 0);
  addTearDown(() {
    tester.view.resetViewInsets();
    tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: Directionality(
                  textDirection:
                      language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
                  child: child!)),
          home: HumRaazScreen(key: ValueKey(accountKey), service: service))));
  await tester.pumpAndSettle();
}

class _FakeChatbotService extends ChatbotService {
  bool failFirstSend = false, unavailable = false, hasHistory = false;
  final requestIds = <String>[];
  final languages = <String>[];
  final consentChanges = <bool>[];
  final historyRequests = <String>[];
  final deleted = <String>[];
  @override
  Future<ChatbotStatus> status() async {
    if (unavailable) throw Exception('offline');
    return const ChatbotStatus(available: true, historyEncrypted: true);
  }

  @override
  Future<ChatbotSessions> sessions({String? before}) async =>
      ChatbotSessions(sessions: [
        if (hasHistory)
          ChatbotSession(
              id: 'past-private-session',
              language: 'en',
              createdAt: DateTime.utc(2026, 10, 8)),
      ]);
  @override
  Future<ChatbotConsent> consent(bool enabled) async {
    consentChanges.add(enabled);
    return ChatbotConsent(enabled: enabled);
  }

  @override
  Future<ChatbotHistory> messages(String sessionId, {String? before}) async {
    historyRequests.add(sessionId);
    return ChatbotHistory(messages: [
      ChatbotMessage(
          id: 'old-assistant',
          role: 'assistant',
          content: 'Previously saved private support.',
          language: 'en',
          createdAt: DateTime.utc(2026, 10, 8),
          metadata: const {'mode': 'grounded_support'})
    ]);
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    deleted.add(sessionId);
  }

  @override
  Future<ChatbotSession> createSession(String language) async => ChatbotSession(
      id: 'private-session',
      language: language,
      createdAt: DateTime.utc(2026, 10, 8));
  @override
  Future<ChatbotSendResult> send(String sessionId,
      {required String message,
      required String language,
      required String requestId}) async {
    requestIds.add(requestId);
    languages.add(language);
    if (failFirstSend && requestIds.length == 1) throw Exception('timeout');
    return ChatbotSendResult(status: 'complete', messages: [
      ChatbotMessage(
          id: 'user-$requestId',
          role: 'user',
          content: message,
          language: language,
          createdAt: DateTime.now()),
      ChatbotMessage(
          id: 'assistant-$requestId',
          role: 'assistant',
          content:
              'A supportive response grounded in HerCare guidance, not a diagnosis or a clinical forecast.',
          language: language,
          createdAt: DateTime.now(),
          metadata: const {
            'mode': 'grounded_support',
            'clinical_validation': false
          }),
    ]);
  }
}
