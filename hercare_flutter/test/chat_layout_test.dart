import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chat_models.dart';
import 'package:hercare/presentation/chat/secure_chat_screen.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _account = '00000000-0000-4000-8000-000000000001';
const _conversation = '00000000-0000-4000-8000-000000000002';
const _longMessage =
    'A deliberately long message that must wrap safely on compact phone screens without overflowing.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['en', 'ur']) {
    for (final largeText in [false, true]) {
      testWidgets(
          'M7 $language chat wraps at 320x480 with keyboard and ${largeText ? '200%' : 'normal'} text',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final provider = ChatProvider(service: _FakeChatService())
          ..bindAccount(_account, role: 'guardian');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => LanguageProvider()),
              ChangeNotifierProvider.value(value: provider),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(largeText ? 2 : 1),
                  viewInsets: const EdgeInsets.only(bottom: 150),
                ),
                child: child!,
              ),
              home: const SecureChatScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SecureChatScreen), findsOneWidget);
        expect(find.textContaining('coming soon'), findsNothing);
        expect(find.text('Private and encrypted'), findsNothing);
        expect(find.text(_longMessage), findsOneWidget);
        expect(find.byKey(const Key('chat-open-help')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        provider.dispose();
      });
    }
  }
}

class _FakeChatService extends ChatService {
  @override
  Future<ChatStatus> getStatusBound({required String accountId}) async =>
      const ChatStatus(
        available: true,
        unreadCount: 1,
        conversationId: _conversation,
        partnerName: 'Support Partner With A Long Name',
      );

  @override
  Future<ChatPage> getMessagePage({
    required String accountId,
    required String conversationId,
    String? before,
    String? after,
    int limit = 50,
  }) async {
    if (after != null) {
      return const ChatPage(
          conversationId: _conversation, messages: [], hasMore: false);
    }
    return ChatPage(
      conversationId: _conversation,
      hasMore: false,
      olderCursor: 'old_cursor',
      newerCursor: 'old_cursor',
      messages: [
        ChatMessage(
          id: '00000000-0000-4000-8000-000000000003',
          senderId: '00000000-0000-4000-8000-000000000004',
          conversationId: _conversation,
          cursor: 'old_cursor',
          isMine: false,
          content: _longMessage,
          sentimentLabel: 'neutral',
          sentimentScore: 0,
          distressScore: 0,
          containsDanger: false,
          createdAt: DateTime.utc(2026, 9, 24),
        ),
      ],
    );
  }

  @override
  Future<void> markReadBound({
    required String accountId,
    required String conversationId,
    required String throughCursor,
    String? fromCursor,
  }) async {}
}
