import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/chat_models.dart';
import 'package:hercare/presentation/chat/secure_chat_screen.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/chat_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('secure chat remains overflow-free on a small phone', (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(
            create: (_) => ChatProvider(service: _FakeChatService()),
          ),
        ],
        child: const MaterialApp(home: SecureChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Private and encrypted'), findsOneWidget);
    expect(find.text('A deliberately long message that must wrap safely on compact phone screens without overflowing.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeChatService extends ChatService {
  @override
  Future<ChatStatus> getStatus() async => const ChatStatus(
        available: true,
        unreadCount: 1,
        conversationId: 'conversation-id',
        partnerName: 'Support Partner With A Long Name',
      );

  @override
  Future<List<ChatMessage>> getMessages({DateTime? before, DateTime? after, int limit = 30}) async => [
        ChatMessage(
          id: 'message-id',
          senderId: 'partner-id',
          isMine: false,
          content: 'A deliberately long message that must wrap safely on compact phone screens without overflowing.',
          sentimentLabel: 'neutral',
          sentimentScore: 0,
          distressScore: 0,
          containsDanger: false,
          createdAt: DateTime.utc(2026, 9, 24),
        ),
      ];

  @override
  Future<void> markRead() async {}
}
