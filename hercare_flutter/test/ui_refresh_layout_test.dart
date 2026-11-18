import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/core/theme/app_theme.dart';
import 'package:hercare/data/models/screening_models.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/community/community_screen.dart';
import 'package:hercare/presentation/epds/tests_screen.dart';
import 'package:hercare/presentation/home/widgets/epds_prompt_card.dart';
import 'package:hercare/presentation/home/widgets/guardian_card.dart';
import 'package:hercare/presentation/home/widgets/home_header.dart';
import 'package:hercare/presentation/home/widgets/mood_hero_card.dart';
import 'package:hercare/presentation/home/widgets/quick_actions_row.dart';
import 'package:hercare/presentation/home/widgets/wellbeing_grid.dart';
import 'package:hercare/presentation/profile/profile_screen.dart';
import 'package:hercare/presentation/shared/app_language_bar.dart';
import 'package:hercare/presentation/therapy/therapy_hub_screen.dart';
import 'package:hercare/presentation/wellbeing/wellbeing_screen.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/guardian_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/providers/screening_provider.dart';
import 'package:hercare/providers/theme_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/screening_service.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the refreshed screens with the real app theme on a very small phone
/// with very large text, and on a normal phone, in English and Urdu, light and
/// dark. Any RenderFlex overflow ("yellow-black stripes") fails the test.
void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('filled icon buttons keep a white icon on the violet theme',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
            body: Center(
                child: IconButton.filled(
                    onPressed: () {}, icon: const Icon(Icons.send))))));
    final icon = tester.element(find.byIcon(Icons.send));
    expect(IconTheme.of(icon).color, Colors.white);
  });

  const sizes = {
    'small phone, 200% text': (Size(320, 568), 2.0),
    'normal phone': (Size(412, 915), 1.0),
  };

  for (final screen in ['home', 'profile', 'wellbeing', 'tests', 'calm']) {
    for (final urdu in [false, true]) {
      for (final dark in [false, true]) {
        for (final size in sizes.entries) {
          for (final linked in screen == 'home' ? [false, true] : [false]) {
            final name = '$screen${linked ? ' (guardian linked)' : ''}: '
                '${urdu ? 'Urdu' : 'English'}, ${dark ? 'dark' : 'light'}, '
                '${size.key}';
            testWidgets(name, (tester) async {
              SharedPreferences.setMockInitialValues(
                  {'app_language': urdu ? 'ur' : 'en'});
              await tester.binding.setSurfaceSize(size.value.$1);
              addTearDown(() => tester.binding.setSurfaceSize(null));
              // Print the full diagnostics (widget + source line) of any
              // layout error, then let the test framework record it as usual.
              final record = FlutterError.onError;
              FlutterError.onError = (details) {
                FlutterError.dumpErrorToConsole(details, forceReport: true);
                record?.call(details);
              };
              await tester.pumpWidget(_harness(
                  switch (screen) {
                    'home' => Scaffold(
                        appBar: const HomeHeader(),
                        body: ListView(children: const [
                          MoodHeroCard(),
                          SizedBox(height: 28),
                          QuickActionsRow(),
                          SizedBox(height: 28),
                          WellbeingGrid(),
                          SizedBox(height: 28),
                          EpdsPromptCard(),
                          SizedBox(height: 28),
                          GuardianCard(),
                          SizedBox(height: 16),
                          CommunityEntryCard(),
                        ])),
                    'profile' => const ProfileScreen(),
                    'tests' =>
                      TestsScreen(embedded: true, service: _ScheduleService()),
                    'calm' => const TherapyHubScreen(),
                    _ => const WellbeingScreen(),
                  },
                  urdu: urdu,
                  dark: dark,
                  scale: size.value.$2,
                  linked: linked));
              await tester.pumpAndSettle();
              _expectNoLayoutError(tester);
              for (var i = 0; i < 12; i++) {
                final scrollables = find.byType(Scrollable);
                if (scrollables.evaluate().isEmpty) break;
                await tester.drag(scrollables.first, const Offset(0, -300));
                await tester.pumpAndSettle();
                _expectNoLayoutError(tester);
              }
              FlutterError.onError = record;
            });
          }
        }
      }
    }
  }
}

/// Fails with the full Flutter diagnostics (which widget, which file/line).
void _expectNoLayoutError(WidgetTester tester) {
  final error = tester.takeException();
  if (error is FlutterError) debugPrint(error.toStringDeep());
  expect(error, isNull);
}

Widget _harness(Widget child,
        {required bool urdu,
        required bool dark,
        required double scale,
        required bool linked}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<MoodProvider>(create: (_) => _Mood()),
        ChangeNotifierProvider<ScreeningProvider>(create: (_) => _Screening()),
        ChangeNotifierProvider<GuardianProvider>(
            create: (_) => _Guardian(linked)),
        ChangeNotifierProvider(
            create: (_) => TherapyProvider(service: _TherapyService())),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
            child: AppLanguageBar(child: child!),
          ),
        ),
        home: child,
      ),
    );

class _Auth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  UserModel get user => UserModel(
      id: 'mother-a',
      phone: '+923001234567',
      role: 'mother',
      language: 'en',
      onboardingComplete: true,
      createdAt: DateTime(2026));
}

class _Mood extends MoodProvider {
  @override
  Future<void> load({bool includeJournals = false}) async {}
}

class _Screening extends ScreeningProvider {
  @override
  bool get overviewLoaded => true;
  @override
  Future<void> loadOverview({bool force = false}) async {}
}

class _Guardian extends GuardianProvider {
  _Guardian(this.linked);
  final bool linked;
  @override
  Map<String, dynamic>? get link => linked
      ? {
          'id': 'link-1',
          'guardian_name': 'A very long guardian name for layout testing',
          'relationship': 'husband',
        }
      : null;
  @override
  bool get hasActiveLink => linked;
  @override
  Future<void> loadLink() async {}
}

class _ScheduleService extends ScreeningService {
  @override
  Future<List<ScheduledScreening>> getSchedule() async => [
        ScheduledScreening(
            instrumentType: 'epds',
            intervalDays: 7,
            due: true,
            dueAt: DateTime.now().subtract(const Duration(days: 1))),
        ScheduledScreening(
            instrumentType: 'phq9',
            intervalDays: 14,
            due: false,
            dueAt: DateTime.now().add(const Duration(days: 14))),
      ];
}

class _TherapyService extends TherapyService {
  @override
  Future<void> syncPending() async {}
  @override
  Future<TherapyRecommendation?> recommendation() async =>
      const TherapyRecommendation(
        activityType: 'breathing',
        activityId: 'box_breathing',
        reason: 'A short balanced breathing session is a gentle daily reset.',
        reasonUr: 'مختصر متوازن سانس روزانہ کا نرم آغاز ہے۔',
        safetyPriority: false,
      );
  @override
  Future<TherapySummary?> summary() async => const TherapySummary(
      totalSessions: 2, completedSessions: 2, totalSeconds: 360);
  @override
  Future<List<TherapySession>> history({int limit = 30}) async => const [];
}