import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hercare/data/models/screening_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/data/models/onboarding_model.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/theme_provider.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/providers/screening_provider.dart';
import 'package:hercare/providers/guardian_provider.dart';
import 'package:hercare/services/guardian_service.dart';
import 'package:hercare/services/screening_service.dart';
import 'package:hercare/services/privacy_service.dart';
import 'package:hercare/presentation/home/widgets/mood_hero_card.dart';
import 'package:hercare/presentation/home/widgets/wellbeing_grid.dart';
import 'package:hercare/presentation/home/widgets/epds_prompt_card.dart';
import 'package:hercare/presentation/home/widgets/home_header.dart';
import 'package:hercare/presentation/profile/profile_screen.dart';
import 'package:hercare/presentation/settings/settings_screen.dart';
import 'package:hercare/presentation/settings/help_support_screen.dart';
import 'package:hercare/presentation/privacy/privacy_screen.dart';
import 'package:hercare/presentation/wellbeing/wellbeing_screen.dart';
import 'package:hercare/presentation/onboarding/onboarding_wizard.dart';
import 'package:hercare/presentation/onboarding/steps/obstetric_info_step.dart';
import 'package:hercare/presentation/onboarding/steps/family_support_step.dart';
import 'package:hercare/presentation/epds/tests_screen.dart';

ScreeningAssessment assessment(
        {String id = 'screen-a',
        String status = 'completed',
        String type = 'epds'}) =>
    ScreeningAssessment(
        id: id,
        instrumentType: type,
        instrumentVersion: 'test',
        scoringVersion: 'test',
        language: 'en',
        status: status,
        totalScore: status == 'completed' ? 12 : null,
        selfHarmPositive: false,
        startedAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
        completedAt: status == 'completed' ? DateTime(2026, 10, 1) : null);

class _Auth extends AuthProvider {
  String? id = 'mother-a';
  @override
  bool get isAuthenticated => id != null;
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime(2026));
  void change(String? value) {
    id = value;
    notifyListeners();
  }
}

class _Mood extends MoodProvider {
  @override
  Future<void> load({bool includeJournals = false}) async {}
}

class _Screening extends ScreeningService {
  final Map<String, Completer<List<ScreeningAssessment>>> historyPending = {};
  String? boundAccount;
  @override
  void bindAccount(String? id) {
    super.bindAccount(id);
    boundAccount = id;
  }

  @override
  Future<List<ScheduledScreening>> getSchedule() async => [];
  Completer<ScreeningAssessment?>? latestPending;
  ScreeningAssessment? latest = assessment();
  bool brokenDraft = false;
  int latestReads = 0, clears = 0, localWrites = 0;
  final List<Map<int, int>> saved = [];
  @override
  Future<ScreeningAssessment?> getLatest({String type = 'epds'}) async {
    latestReads++;
    return latestPending == null ? latest : await latestPending!.future;
  }

  @override
  Future<List<ScreeningAssessment>> getHistory(
          {String type = 'epds', int limit = 20}) async =>
      historyPending.containsKey(type)
          ? await historyPending[type]!.future
          : latest == null
              ? []
              : [latest!];
  @override
  Future<ScreeningReminder> getReminder({String type = 'epds'}) async =>
      ScreeningReminder(
          instrumentType: type,
          due: false,
          dueAt: DateTime.now().add(const Duration(days: 7)));
  @override
  Future<({String id, Map<int, int> answers})?> readLocalDraft() async =>
      brokenDraft ? (id: 'interrupted', answers: {1: 2}) : null;
  @override
  Future<ScreeningAssessment> getAssessment(String id) async =>
      throw Exception('Connection unavailable');
  @override
  Future<void> clearLocalDraft() async {
    clears++;
  }

  @override
  Future<ScreeningAssessment> start(
          {required String instrumentType, required String language}) async =>
      assessment(status: 'draft');
  @override
  Future<ScreeningInstrument> getInstrument(String type,
          {String? version}) async =>
      ScreeningInstrument(
          type: type,
          name: 'Synthetic test',
          version: 'test',
          scoringVersion: 'test',
          timeframeDays: 7,
          maxScore: 6,
          crisisQuestion: 2,
          questions: [
            for (var i = 1; i <= 2; i++)
              ScreeningQuestion(
                  number: i,
                  textEn: 'Synthetic question',
                  textUr: 'سوال',
                  options: const [])
          ]);
  @override
  Future<void> saveLocalDraft(String id, Map<int, int> answers) async {
    localWrites++;
  }

  @override
  Future<void> saveDraft(String assessmentId, Map<int, int> answers) async {
    saved.add(Map.of(answers));
  }
}

class _Guardian extends GuardianService {
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> getDashboard({String lang = 'en'}) =>
      pending.future;
  @override
  Future<Map<String, dynamic>?> getLink() async => null;
}

class _Privacy extends PrivacyService {
  Completer<PrivacySettings>? updatePending;
  int reads = 0, writes = 0;
  @override
  Future<PrivacySettings> read(String accountId) async {
    reads++;
    return PrivacySettings(
        basic: true, guardian: accountId == 'mother-a', telemetry: false);
  }

  @override
  Future<PrivacySettings> update(String id, String field, bool value) async {
    writes++;
    return await updatePending!.future;
  }
}

Widget harness(Widget child,
        {bool ur = false,
        double scale = 2,
        AuthProvider? auth,
        ScreeningProvider? screening}) =>
    MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth ?? _Auth()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<MoodProvider>(create: (_) => _Mood()),
          ChangeNotifierProvider<ScreeningProvider>.value(
              value: screening ?? ScreeningProvider(service: _Screening())),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                    textDirection: ur ? TextDirection.rtl : TextDirection.ltr,
                    child: child!)),
            home: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting());
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('optional guardian sharing is not preselected for a new mother', () {
    expect(OnboardingData().consentTier2, false);
    expect(OnboardingData.fromJson({}).consentTier2, false);
  });

  test(
      'guardian late replies cannot restore a previous account or disconnected link',
      () async {
    for (final switchAccount in [true, false]) {
      final service = _Guardian();
      final provider = GuardianProvider(service: service)
        ..bindAccount('mother-a');
      final pending = provider.loadDashboard();
      if (switchAccount) {
        provider.bindAccount('mother-b');
      } else {
        await provider.loadLink();
      }
      service.pending.complete({'private': 'previous account'});
      await pending;
      expect(provider.dashboard, isNull);
      expect(provider.isLoading, false);
      provider.dispose();
    }
  });

  test('screening cache coalesces loads and drops replies after account switch',
      () async {
    final service = _Screening()..latestPending = Completer();
    final provider = ScreeningProvider(service: service)
      ..bindAccount('mother-a');
    final pending = provider.loadOverview();
    await provider.loadOverview();
    expect(service.latestReads, 1);
    provider.bindAccount('mother-b');
    service.latestPending!.complete(assessment());
    await pending;
    expect(provider.latest, isNull);
    expect(provider.history, isEmpty);
    service.latestPending = null;
    await provider.loadOverview();
    await provider.loadOverview();
    expect(service.latestReads, 2);
    await provider.loadOverview(force: true);
    expect(service.latestReads, 3);
    provider.dispose();
  });

  test('screening retains encrypted answers when draft revalidation is offline',
      () async {
    final service = _Screening()..brokenDraft = true;
    final provider = ScreeningProvider(service: service);
    expect(await provider.initialize(language: 'en'), false);
    expect(service.clears, 0);
    expect(provider.current, isNull);
    provider.dispose();
  });

  test('late EPDS history and overview cannot overwrite selected PHQ-9 history',
      () async {
    final service = _Screening()
      ..historyPending['epds'] = Completer()
      ..historyPending['phq9'] = Completer();
    final provider = ScreeningProvider(service: service)
      ..bindAccount('mother-a');
    final overview = provider.loadOverview();
    final oldHistory = provider.loadHistory();
    final newHistory = provider.loadHistory(type: 'phq9');
    service.historyPending['phq9']!
        .complete([assessment(id: 'phq', type: 'phq9')]);
    await newHistory;
    service.historyPending['epds']!.complete([assessment()]);
    await Future.wait([overview, oldHistory]);
    expect(provider.history.single.id, 'phq');
    expect(provider.latest?.instrumentType, 'epds');
    provider.dispose();
  });

  testWidgets('Tests pins the current account before loading its schedule',
      (tester) async {
    final service = _Screening();
    await tester.pumpWidget(harness(TestsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(service.boundAccount, 'mother-a');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('screening queues immutable answer snapshots with one local write each',
      () async {
    final service = _Screening();
    final provider = ScreeningProvider(service: service);
    await provider.initialize(language: 'en');
    await Future.wait(
        [provider.chooseAnswer(1, 1), provider.chooseAnswer(2, 2)]);
    // Reopening waits for the serialized writes to finish.
    await provider.initialize(language: 'en');
    expect(service.localWrites, 2);
    expect(service.saved, [
      {1: 1},
      {1: 1, 2: 2}
    ]);
    provider.dispose();
  });

  test(
      'screening drafts are isolated by account and never exposed to another account',
      () async {
    final service = ScreeningService()..bindAccount('mother-a');
    await service.saveLocalDraft('private-a', {1: 2});
    service.bindAccount('mother-b');
    expect(await service.readLocalDraft(), isNull);
    await service.saveLocalDraft('private-b', {1: 0});
    service.bindAccount('mother-a');
    expect((await service.readLocalDraft())?.id, 'private-a');
    await service.clearLocalDraft();
    service.bindAccount('mother-b');
    expect((await service.readLocalDraft())?.id, 'private-b');
  });

  for (final ur in [false, true]) {
    for (final name in [
      'wellbeing',
      'home-cards',
      'profile',
      'settings',
      'privacy',
      'help',
      'onboarding',
      'optional-birth',
      'optional-family'
    ]) {
      testWidgets('$name: 320x480 at 200% text in ${ur ? 'Urdu' : 'English'}',
          (tester) async {
        SharedPreferences.setMockInitialValues(
            {'app_language': ur ? 'ur' : 'en'});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final screen = switch (name) {
          'wellbeing' => const WellbeingScreen(),
          'home-cards' => Scaffold(
              appBar: const HomeHeader(),
              body: ListView(children: const [
                MoodHeroCard(),
                WellbeingGrid(),
                EpdsPromptCard()
              ])),
          'profile' => const ProfileScreen(),
          'settings' => const SettingsScreen(),
          'privacy' => PrivacyScreen(service: _Privacy()),
          'help' => const HelpSupportScreen(),
          'optional-birth' => Scaffold(
              body: ObstetricInfoStep(
                  formKey: GlobalKey<FormState>(),
                  data: OnboardingData(),
                  isUrdu: ur)),
          'optional-family' => Scaffold(
              body: FamilySupportStep(
                  formKey: GlobalKey<FormState>(),
                  data: OnboardingData(),
                  isUrdu: ur)),
          _ => const OnboardingWizard(),
        };
        await tester.pumpWidget(harness(screen, ur: ur));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('8 / 30'), findsNothing);
        expect(find.text('Day 47 Postpartum'), findsNothing);
        expect(find.textContaining('clinically validated'), findsNothing);
        expect(find.textContaining('aOR ='), findsNothing);
        expect(find.textContaining('Higher-risk gender'), findsNothing);
        if (name != 'onboarding') {
          for (var i = 0; i < 6; i++) {
            final scroll = find.byType(Scrollable).first;
            await tester.drag(scroll, const Offset(0, -280));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }

  testWidgets(
      'privacy waits for confirmation and re-reads after an uncertain write',
      (tester) async {
    final service = _Privacy()..updatePending = Completer();
    await tester.pumpWidget(harness(PrivacyScreen(service: service), scale: 1));
    await tester.pumpAndSettle();
    final guardian = find.byType(SwitchListTile).first;
    expect(tester.widget<SwitchListTile>(guardian).value, true);
    await tester.tap(guardian);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(guardian).value, true);
    expect(tester.widget<SwitchListTile>(guardian).onChanged, isNull);
    service.updatePending!.completeError(Exception('Lost response'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.writes, 1);
    expect(service.reads, 2);
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        true);
  });

  testWidgets('privacy discards a pending update when the account changes',
      (tester) async {
    final auth = _Auth();
    final service = _Privacy()..updatePending = Completer();
    await tester.pumpWidget(
        harness(PrivacyScreen(service: service), auth: auth, scale: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();
    auth.change('mother-b');
    await tester.pumpAndSettle();
    service.updatePending!.complete(
        const PrivacySettings(basic: true, guardian: true, telemetry: true));
    await tester.pumpAndSettle();
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches.map((s) => s.value), [false, false]);
  });
}
