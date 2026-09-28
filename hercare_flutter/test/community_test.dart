import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/community_models.dart';
import 'package:hercare/presentation/community/community_screen.dart';
import 'package:hercare/presentation/community/community_composer.dart';
import 'package:hercare/presentation/community/community_widgets.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/community_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> postData = {
  'id': 'thread',
  'author': {'id': 'member', 'alias': 'Kind Willow 0123456789'},
  'title': 'Sharing a small step forward on a difficult day',
  'body': 'A supportive message and a recovery experience. امید اور حوصلہ',
  'topic': 'medication',
  'status': 'published',
  'created_at': '2026-09-26T12:00:00Z',
  'version': 1,
  'reactions': {'solidarity': 120},
  'comment_count': 12,
};

class FakeCommunity extends CommunityService {
  FakeCommunity({this.joined = true});
  bool joined;
  @override
  Future<Map<String, dynamic>> status() async => {
        'joined': joined,
        'alias': 'Kind Lotus 1234567890',
        'is_moderator': true,
        'rules_version': 'v1'
      };
  @override
  Future<void> join(String version) async {
    joined = true;
  }

  @override
  Future<CommunityPage> feed(
          {String? topic,
          String? cursor,
          bool mine = false,
          String? sessionId}) async =>
      CommunityPage({
        'items': [postData],
        'next_cursor': null
      });
  @override
  Future<CommunityPost> detail(String id) async => CommunityPost(postData);
  @override
  Future<CommunityPage> comments(String id, {String? cursor}) => feed();
  @override
  Future<CommunityPage> queue({String? cursor}) => feed();
  @override
  Future<Map<String, dynamic>> submit(Map<String, dynamic> data) async =>
      {'safety_support': false};
}

void main() {
  testWidgets('successful submission returns to the previous screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CommunityComposer(
                              service: FakeCommunity(), urdu: false))),
                  child: const Text('Open composer'),
                )))));
    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'A hopeful day');
    await tester.enterText(
        find.byType(TextField).last, 'Today I felt supported by my family.');
    await tester.scrollUntilVisible(find.text('Send for review'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Send for review'));
    await tester.pumpAndSettle();
    expect(find.text('Sent for review'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open composer'), findsOneWidget);
    expect(find.byType(CommunityComposer), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final language in ['en', 'ur']) {
    for (final mode in ['join', 'feed', 'thread', 'moderation', 'composer']) {
      testWidgets(
          'community $mode $language fits 320px with large text and keyboard',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = FakeCommunity(joined: mode != 'join');
        await tester.pumpWidget(ChangeNotifierProvider(
            create: (_) => LanguageProvider(),
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.5),
                      viewInsets: const EdgeInsets.only(bottom: 100)),
                  child: Directionality(
                      textDirection: language == 'ur'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: child!)),
              home: mode == 'composer'
                  ? CommunityComposer(service: service, urdu: language == 'ur')
                  : CommunityScreen(
                      service: service,
                      parentId: mode == 'thread' ? 'thread' : null,
                      moderation: mode == 'moderation'),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 12; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -180));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('post reaction chips wrap at 280px and double text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: ListView(children: [
          CommunityPostCard(
              post: CommunityPost(postData),
              urdu: true,
              onReaction: (_) {},
              onAction: (_) {},
              onOpen: () {})
        ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
