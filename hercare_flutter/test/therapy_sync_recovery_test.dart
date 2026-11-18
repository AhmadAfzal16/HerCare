import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/presentation/therapy/therapy_hub_screen.dart';
import 'package:hercare/presentation/therapy/therapy_sync_recovery.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['en', 'ur']) {
    testWidgets(
        '$language recovery fits small phone large text and requires discard confirmation',
        (tester) async {
      await _smallPhone(tester);
      final service = _RecoveryService()..offline = true;
      final provider = TherapyProvider(service: service)
        ..bindAccount('mother-a');
      addTearDown(provider.dispose);
      await provider.load();
      await _pump(tester, provider, language: language, scale: 2);
      await tester.tap(find.byKey(const Key('open-recovery')));
      await tester.pumpAndSettle();
      final discard =
          _text(language, 'Discard phone record', 'مقامی ریکارڈ ہٹائیں');
      final keep = _text(language, 'Keep', 'رہنے دیں');
      final confirm = _text(language, 'Discard', 'ہٹائیں');
      await _reveal(tester, find.text(discard));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(discard));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.discards, isEmpty);
      expect(service.issues['mother-a'], hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(keep));
      await tester.tap(find.text(keep));
      await tester.pumpAndSettle();
      expect(service.discards, isEmpty);
      await _reveal(tester, find.text(discard));
      await tester.tap(find.text(discard));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(confirm));
      await tester.tap(find.text(confirm));
      await tester.pumpAndSettle();
      expect(service.discards, [('mother-a', 'pending-a')]);
      expect(service.issues['mother-a'], isEmpty);
      expect(service.serverHistory['mother-a']!.single.id, 'server-a');
      expect(tester.takeException(), isNull);
      await _reveal(tester, find.text(_text(language, 'Close', 'بند کریں')));
      await tester.tap(find.text(_text(language, 'Close', 'بند کریں')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  }

  testWidgets(
      'retry uses the captured owner and updates only their pending record',
      (tester) async {
    final service = _RecoveryService()..offline = true;
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    addTearDown(provider.dispose);
    await provider.load();
    await _pump(tester, provider);
    await tester.tap(find.byKey(const Key('open-recovery')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.retries, [('mother-a', 'pending-a')]);
    expect(service.issues['mother-a'], isEmpty);
    expect(service.issues['mother-b'], hasLength(1));
    expect(provider.history.map((session) => session.id),
        containsAll(['server-a', 'synced-pending-a']));
    expect(service.discards, isEmpty);
    await _reveal(tester, find.text('No rejected records remain.'));
    expect(find.text('No rejected records remain.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account change during confirmation prevents deletion and hides both owners records',
      (tester) async {
    final service = _RecoveryService()..offline = true;
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    addTearDown(provider.dispose);
    await provider.load();
    await _pump(tester, provider);
    await tester.tap(find.byKey(const Key('open-recovery')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Discard phone record'));
    await tester.tap(find.text('Discard phone record'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    provider.bindAccount('mother-b');
    await provider.load();
    await tester.pump();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(service.discards, isEmpty);
    expect(service.retries, isEmpty);
    expect(service.issues['mother-a'], hasLength(1));
    expect(service.issues['mother-b'], hasLength(1));
    expect(find.text('Your account changed. Close this page.'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Memory Match')),
        findsNothing);
    expect(find.descendant(of: sheet, matching: find.text('Color Calm')),
        findsNothing);
    expect(
        find.descendant(of: sheet, matching: find.text('Retry')), findsNothing);
    await _reveal(tester, find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'discarding rejected local save retains previously read server history',
      (tester) async {
    final service = _RecoveryService();
    final provider = TherapyProvider(service: service)..bindAccount('mother-a');
    addTearDown(provider.dispose);
    await provider.load();
    expect(provider.history.map((entry) => entry.id), contains('server-a'));
    service.offline = true;
    await provider.load();
    expect(provider.history.map((entry) => entry.id),
        containsAll(['server-a', 'pending-a']));
    await _pump(tester, provider);
    await tester.tap(find.byKey(const Key('open-recovery')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Discard phone record'));
    await tester.tap(find.text('Discard phone record'));
    await tester.pumpAndSettle();
    expect(service.discards, isEmpty);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(provider.history.map((entry) => entry.id), contains('server-a'));
    expect(provider.history.map((entry) => entry.id),
        isNot(contains('pending-a')));
    expect(service.serverHistory['mother-a']!.single.id, 'server-a');
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ur']) {
    testWidgets(
        '$language offline hub preserves history and opens rejected-record review',
        (tester) async {
      await _smallPhone(tester);
      final service = _RecoveryService();
      final provider = TherapyProvider(service: service)
        ..bindAccount('mother-a');
      addTearDown(provider.dispose);
      await provider.load();
      service.offline = true;
      await _pump(tester, provider, language: language, scale: 2, hub: true);
      await tester.pumpAndSettle();
      final banner = _text(
          language,
          'Offline: suggestions and summaries may be older. This is not an urgent safety check.',
          'آف لائن: تجویز اور خلاصہ پرانے ہو سکتے ہیں۔ یہ فوری خطرے کی جانچ نہیں۔');
      await tester.scrollUntilVisible(find.text(banner), 150,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(banner), findsOneWidget);
      expect(provider.history.map((entry) => entry.id), contains('server-a'));
      final review =
          _text(language, 'Review pending records', 'محفوظ ریکارڈ کا جائزہ');
      await tester.scrollUntilVisible(find.text(review), 150,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(review));
      await tester.pumpAndSettle();
      await _reveal(
          tester,
          find.text(
              _text(language, 'Discard phone record', 'مقامی ریکارڈ ہٹائیں')));
      expect(tester.takeException(), isNull);
      await _reveal(tester, find.text(_text(language, 'Close', 'بند کریں')));
      await tester.tap(find.text(_text(language, 'Close', 'بند کریں')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(service.discards, isEmpty);
      expect(provider.history.map((entry) => entry.id), contains('server-a'));
      expect(tester.takeException(), isNull);
    });
  }
}

String _text(String language, String en, String ur) =>
    language == 'ur' ? ur : en;

Future<void> _smallPhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scrolling = find
      .descendant(
          of: find.byType(BottomSheet), matching: find.byType(Scrollable))
      .last;
  await tester.scrollUntilVisible(target, 120, scrollable: scrolling);
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, TherapyProvider provider,
    {String language = 'en', double scale = 1, bool hub = false}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ChangeNotifierProvider<TherapyProvider>.value(value: provider),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: Directionality(
          textDirection:
              language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: hub ? const TherapyHubScreen() : const _Launcher(),
    ),
  ));
  await tester.pumpAndSettle();
}

class _Launcher extends StatelessWidget {
  const _Launcher();
  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: ElevatedButton(
              key: const Key('open-recovery'),
              onPressed: () => showTherapySyncRecovery(context),
              child: const Text('Review'))));
}

class _RecoveryService extends TherapyService {
  bool offline = false;
  String? owner;
  final List<(String, String)> retries = [], discards = [];
  final issues = <String, List<TherapyPendingIssue>>{
    'mother-a': [
      TherapyPendingIssue(
          requestId: 'pending-a',
          activityId: 'memory_match',
          completedAt: DateTime.utc(2026, 10, 10),
          statusCode: 409)
    ],
    'mother-b': [
      TherapyPendingIssue(
          requestId: 'pending-b',
          activityId: 'color_calm',
          completedAt: DateTime.utc(2026, 10, 11),
          statusCode: 422)
    ],
  };
  late final serverHistory = <String, List<TherapySession>>{
    'mother-a': [_session('server-a', 'box_breathing', synced: true)],
    'mother-b': [_session('server-b', 'color_calm', synced: true)],
  };

  @override
  void bindAccount(String? id) {
    owner = id;
    super.bindAccount(id);
  }

  @override
  String? get syncWarning => pendingIssues.isEmpty ? null : 'Review needed';

  @override
  List<TherapyPendingIssue> get pendingIssues =>
      List.unmodifiable(issues[owner] ?? const <TherapyPendingIssue>[]);

  @override
  Future<void> syncPending() async {}

  @override
  Future<TherapyRecommendation?> recommendation() async => offline
      ? null
      : const TherapyRecommendation(
          activityType: 'breathing',
          activityId: 'box_breathing',
          reason: 'Gentle self-care',
          reasonUr: 'نرم خود مدد',
          safetyPriority: false);

  @override
  Future<TherapySummary?> summary() async => offline
      ? null
      : const TherapySummary(
          totalSessions: 1,
          completedSessions: 1,
          totalSeconds: 60,
          periodDays: 30);

  @override
  Future<List<TherapySession>> history({int limit = 30}) async => offline
      ? pendingIssues
          .map((issue) =>
              _session(issue.requestId, issue.activityId, synced: false))
          .toList()
      : List.of(serverHistory[owner] ?? const []);

  @override
  Future<void> retryPending(String id,
      {required String expectedAccountId}) async {
    if (expectedAccountId != owner) throw TherapyAccountException();
    retries.add((expectedAccountId, id));
    final pending = issues[owner]!;
    final issue = pending.singleWhere((issue) => issue.requestId == id);
    pending.remove(issue);
    serverHistory[owner]!
        .add(_session('synced-$id', issue.activityId, synced: true));
    offline = false;
  }

  @override
  Future<void> discardPending(String id,
      {required String expectedAccountId}) async {
    if (expectedAccountId != owner) throw TherapyAccountException();
    discards.add((expectedAccountId, id));
    issues[owner]!.removeWhere((issue) => issue.requestId == id);
  }

  TherapySession _session(String id, String activity, {required bool synced}) =>
      TherapySession(
          id: id,
          activityType: TherapyCatalog.byId(activity).type,
          activityId: activity,
          durationSeconds: 60,
          completed: true,
          completedAt: DateTime.utc(2026, 10, 10),
          isSynced: synced);
}
