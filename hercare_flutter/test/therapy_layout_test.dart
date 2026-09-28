import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/presentation/therapy/breathing_exercise_screen.dart';
import 'package:hercare/presentation/therapy/therapy_game_screen.dart';
import 'package:hercare/presentation/therapy/therapy_hub_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() =>
      SharedPreferences.setMockInitialValues(const {'app_language': 'en'}));

  testWidgets('therapy hub remains overflow-free on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(
            create: (_) => TherapyProvider(service: _FakeTherapyService())),
      ],
      child: const MaterialApp(home: TherapyHubScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Suggested for you'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Light mini-games'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathing guide remains overflow-free on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MaterialApp(
          home: BreathingExerciseScreen(patternId: 'breathing_478')),
    ));
    await tester.pump();
    expect(find.text('4-7-8 Breathing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('memory game remains overflow-free on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MaterialApp(home: TherapyGameScreen(gameId: 'memory_match')),
    ));
    await tester.pump();
    expect(find.text('Find the four matching pairs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTherapyService extends TherapyService {
  @override
  Future<void> syncPending() async {}

  @override
  Future<TherapyRecommendation?> recommendation() async =>
      const TherapyRecommendation(
        activityType: 'breathing',
        activityId: 'box_breathing',
        reason: 'A short balanced breathing session is a gentle daily reset.',
        reasonUr: '',
        safetyPriority: false,
      );

  @override
  Future<TherapySummary?> summary() async => const TherapySummary(
      totalSessions: 2, completedSessions: 2, totalSeconds: 360);

  @override
  Future<List<TherapySession>> history({int limit = 30}) async => const [];
}
