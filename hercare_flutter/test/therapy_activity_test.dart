import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/presentation/therapy/activity_clock.dart';
import 'package:hercare/presentation/therapy/breathing_exercise_screen.dart';
import 'package:hercare/presentation/therapy/breathing_band_panel.dart';
import 'package:hercare/presentation/therapy/meditation_audio.dart';
import 'package:hercare/presentation/therapy/cbt_exercise_screen.dart';
import 'package:hercare/presentation/therapy/therapy_game_screen.dart';
import 'package:hercare/presentation/therapy/therapy_completion_sheet.dart';
import 'package:hercare/presentation/therapy/therapy_hub_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'optional band picker displays a live reading and clears it on exit',
      (tester) async {
    const control = MethodChannel('com.hercare/breathing_band');
    const events = MethodChannel('com.hercare/breathing_band/events');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(control, (call) async {
      calls.add(call);
    });
    messenger.setMockMethodCallHandler(events, (_) async {});
    addTearDown(() {
      messenger.setMockMethodCallHandler(control, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    Future<void> show(bool enabled) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BreathingBandPanel(isUrdu: false, enabled: enabled))));
    Future<void> event(Map<String, Object> data) async {
      await messenger.handlePlatformMessage(events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(data), (_) {});
      await tester.pump();
    }

    await show(true);
    await tester.tap(find.text('Connect band'));
    await tester.pump();
    expect(calls.last.method, 'scan');
    await event({
      'device': {'id': '0', 'name': 'Xiaomi Smart Band 10'}
    });
    await tester.tap(find.text('Xiaomi Smart Band 10'));
    await tester.pump();
    expect(calls.last.arguments, {'id': '0'});
    await event({'status': 'live', 'bpm': 72});
    expect(find.text('Live heart rate: 72 bpm'), findsOneWidget);
    await event({'status': 'no_reading'});
    expect(find.text('Live heart rate: 72 bpm'), findsNothing);
    await show(false);
    await tester.pump();
    expect(calls.last.method, 'stop');
    expect(find.text('Connect band'), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  test('active clock excludes background and saves rounded active time only',
      () {
    var monotonic = Duration.zero;
    final clock = ActiveTherapyClock(elapsedSource: () => monotonic);
    clock.resume();
    monotonic = const Duration(milliseconds: 1400);
    expect(clock.seconds, 1);
    expect(clock.recordedSeconds, 2);
    clock.pause();
    monotonic = const Duration(hours: 5);
    expect(clock.seconds, 1);
    clock.resume();
    monotonic += const Duration(milliseconds: 600);
    clock.pause();
    expect(clock.seconds, 2);
    clock.resume();
    monotonic += const Duration(hours: 10);
    expect(clock.recordedSeconds, 7200);
  });

  for (final language in ['en', 'ur']) {
    for (final activity in TherapyCatalog.activities
        .where((activity) => activity.type != 'meditation')) {
      testWidgets('$language ${activity.id} fits 320x480 at 200% text',
          (tester) async {
        await _smallPhone(tester);
        final screen = switch (activity.type) {
          'breathing' => BreathingExerciseScreen(patternId: activity.id),
          'cbt' => CbtExerciseScreen(activityId: activity.id),
          _ => TherapyGameScreen(gameId: activity.id),
        };
        await _pump(tester, screen, language: language, scale: 2);
        for (var scroll = 0; scroll < 5; scroll += 1) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -250));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('grounding completes only after all five explicit steps',
      (tester) async {
    await _pump(tester, const CbtExerciseScreen(activityId: 'grounding_54321'));
    ElevatedButton button() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Complete exercise'));
    expect(button().onPressed, isNull);
    for (var i = 0; i < 4; i += 1) {
      await tester.ensureVisible(find.text('Next sense'));
      await tester.tap(find.text('Next sense'));
      await tester.pump();
      expect(button().onPressed, isNull);
    }
    await tester.ensureVisible(find.text('I noticed it'));
    await tester.tap(find.text('I noticed it'));
    await tester.pump();
    expect(find.text('All five senses explored.'), findsOneWidget);
    expect(button().onPressed, isNotNull);
  });

  for (final language in ['en', 'ur']) {
    testWidgets(
        '$language optional CBT answer fits with keyboard and 200% text',
        (tester) async {
      await _smallPhone(tester);
      await _pump(
          tester, const CbtExerciseScreen(activityId: 'thought_challenge'),
          language: language, scale: 2, keyboardHeight: 160);
      final answer = find.byKey(const ValueKey('cbt-answer-0'));
      await tester.scrollUntilVisible(answer, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(answer, 'Private reflection');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.text(language == 'ur' ? 'مشق مکمل کریں' : 'Complete exercise'),
          150,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('breathing bubbles do not complete from rapid repeated taps',
      (tester) async {
    await _pump(tester, const TherapyGameScreen(gameId: 'breathing_bubbles'));
    final bubble = find.byKey(const Key('breathing-bubble'));
    for (var i = 0; i < 10; i += 1) {
      await tester.tap(bubble);
      await tester.pump();
    }
    expect(find.text('1 / 10'), findsOneWidget);
    expect(find.text('You completed the game.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unfinished game stores partial rather than completed',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, const TherapyGameScreen(gameId: 'domestic_puzzle'),
        service: service);
    await tester.ensureVisible(find.text('Stop early'));
    await tester.tap(find.text('Stop early'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save partial'));
    await tester.tap(find.text('Save partial'));
    await tester.pumpAndSettle();
    expect(service.saved, hasLength(1));
    expect(service.saved.single.completed, isFalse);
    expect(service.saved.single.moodChange, isNull);
  });

  testWidgets('domestic puzzle requires correct matches and save can retry',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, const TherapyGameScreen(gameId: 'domestic_puzzle'),
        service: service);
    await tester.tap(find.byKey(const ValueKey('household-1')));
    await tester.pump();
    expect(find.text('No problem—try another place.'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    for (var i = 0; i < 3; i += 1) {
      await tester.tap(find.byKey(ValueKey('household-$i')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(service.saved, isEmpty);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Save completed game'), findsOneWidget);
    await tester.tap(find.text('Save completed game'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save completion'));
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    expect(service.saved, hasLength(1));
    expect(service.saved.single.completed, isTrue);
    expect(find.text('Session saved'), findsOneWidget);
  });

  testWidgets('color game is playable by names not color vision',
      (tester) async {
    final service = _FakeService();
    await _pump(tester, const TherapyGameScreen(gameId: 'color_calm'),
        service: service);
    const names = ['Purple', 'Pink', 'Blue', 'Green'];
    for (var i = 0; i < 8; i += 1) {
      final name =
          tester.widget<Text>(find.byKey(const Key('color-target'))).data!;
      final target = find.byKey(ValueKey('color-${names.indexOf(name)}'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save completion'));
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    expect(service.saved.single.completed, isTrue);
  });

  testWidgets('breathing pauses when backgrounded and when route is covered',
      (tester) async {
    final audio = _BreathingAudio();
    addTearDown(audio.dispose);
    await _pump(tester,
        BreathingExerciseScreen(patternId: 'breathing_478', audio: audio));
    final button = find.byKey(const Key('breathing-toggle'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    expect(audio.cues, ['assets/audio/breathing/en_inhale.wav']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Pause'), findsNothing);
    expect(audio.pauses, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered route'))));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'breathing check-in saves an optional self-report separately from completion',
      (tester) async {
    final service = _FakeService();
    await _pump(
        tester,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showTherapyCompletionSheet(context,
                        type: 'breathing',
                        activityId: 'box_breathing',
                        durationSeconds: 15,
                        completed: false,
                        isUrdu: false),
                    child: const Text('Open save sheet'),
                  ),
                )),
        service: service);
    await tester.tap(find.text('Open save sheet'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Some cues'));
    await tester.tap(find.text('Some cues'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save partial'));
    await tester.tap(find.text('Save partial'));
    await tester.pumpAndSettle();
    expect(service.saved.single.breathingParticipation, 'some_cues');
    expect(service.saved.single.completed, false);
  });

  testWidgets(
      'monitoring: before/after comparison is shown, distress is saved and support is offered',
      (tester) async {
    final service = _FakeService();
    await _pump(
        tester,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showTherapyCompletionSheet(context,
                        type: 'breathing',
                        activityId: 'cyclic_sighing',
                        durationSeconds: 300,
                        isUrdu: false,
                        measures: const TherapyMeasures(
                            tensionBefore: 7,
                            hrBefore: 88,
                            hrvBefore: 24,
                            hrAfter: 76,
                            hrvAfter: 39,
                            physioSource: 'camera')),
                    child: const Text('Open save sheet'),
                  ),
                )),
        service: service);
    await tester.tap(find.text('Open save sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Heart rate: 88 → 76 bpm'), findsOneWidget);
    expect(find.text('Variability: 24 → 39 ms'), findsOneWidget);
    expect(find.text('Camera readings are approximate.'), findsOneWidget);
    // She did a before-check, so the "after" questions are already open.
    await tester.ensureVisible(find.byKey(const Key('distress-true')));
    await tester.tap(find.byKey(const Key('distress-true')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save completion'));
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    final saved = service.saved.single.measures!;
    expect(saved.distressReported, true);
    expect(saved.tensionBefore, 7);
    expect(saved.tensionAfter, isNull,
        reason: 'untouched slider is not an answer');
    expect([saved.hrBefore, saved.hrAfter, saved.physioSource],
        [88, 76, 'camera']);
    expect(find.text('Thank you for telling us'), findsOneWidget);
    expect(find.text('5-4-3-2-1 grounding (eyes open)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text("I'm okay for now"));
    await tester.tap(find.text("I'm okay for now"));
    await tester.pumpAndSettle();
    expect(find.text('Thank you for telling us'), findsNothing);
  });

  testWidgets(
      'no before-check: the after questions stay collapsed and nothing extra is saved',
      (tester) async {
    final service = _FakeService();
    await _pump(
        tester,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showTherapyCompletionSheet(context,
                        type: 'meditation',
                        activityId: 'body_scan',
                        durationSeconds: 300,
                        isUrdu: false),
                    child: const Text('Open save sheet'),
                  ),
                )),
        service: service);
    await tester.tap(find.text('Open save sheet'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('distress-true')), findsNothing);
    await tester.ensureVisible(find.text('Save completion'));
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();
    expect(service.saved.single.measures, isNull);
    expect(find.text('Thank you for telling us'), findsNothing);
  });

  test('measures: heart readings need a source; ranges match the server', () {
    const noSource = TherapyMeasures(hrBefore: 80, tensionBefore: 4);
    expect(noSource.toJson(), {'tension_before': 4},
        reason: 'heart readings are dropped without their source');
    const camera =
        TherapyMeasures(hrBefore: 80, hrvBefore: 30, physioSource: 'camera');
    expect(TherapyMeasures.validJson(camera.toJson()), isTrue);
    for (final bad in [
      {'tension_before': 11},
      {'hr_before': 80},
      {'physio_source': 'band'},
      {'hr_before': 80, 'physio_source': 'guess'},
      {'distress_reported': 'yes'},
      {'raw_frames': []},
    ]) {
      expect(TherapyMeasures.validJson(bad), isFalse, reason: '$bad');
    }
    final session = TherapySession.fromJson({
      'id': '1',
      'activity_type': 'breathing',
      'activity_id': 'cyclic_sighing',
      'duration_seconds': 300,
      'completed': true,
      'completed_at': '2026-11-17T10:00:00Z',
      'measures': {
        'tension_before': 7,
        'tension_after': 3,
        'distress_reported': false
      },
    });
    expect(session.measures!.tensionChange, -4);
    expect(needsSupport(session), isFalse);
    expect(
        needsSupport(TherapySession.fromJson({
          'completed': true,
          'measures': {'tension_before': 2, 'tension_after': 6},
        })),
        isTrue,
        reason: 'tension rose by 3 or more');
  });

  testWidgets(
      'calming sigh shows its top-up breath and a collapsed before-check',
      (tester) async {
    await _pump(
        tester,
        BreathingExerciseScreen(
            patternId: 'cyclic_sighing', audio: _BreathingAudio()));
    await tester.pumpAndSettle();
    expect(find.text('Calming Sigh'), findsOneWidget);
    expect(find.text('Top-up breath 1s'), findsOneWidget);
    expect(find.text('Exhale 6s'), findsOneWidget);
    expect(find.text('Before you start (optional)'), findsOneWidget);
    expect(find.byKey(const Key('heart-before')), findsNothing,
        reason: 'collapsed until she opens it');
    await tester.tap(find.text('Before you start (optional)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heart-before')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hub presents partial history and nonclinical mood summary',
      (tester) async {
    await _smallPhone(tester);
    final service = _FakeService();
    service.saved.add(TherapySession(
      id: 'partial',
      activityType: 'game',
      activityId: 'domestic_puzzle',
      durationSeconds: 12,
      completed: false,
      completedAt: DateTime(2026, 10, 12),
      moodBefore: 1,
      moodAfter: 5,
      isSynced: false,
    ));
    await _pump(tester, const TherapyHubScreen(), service: service, scale: 2);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Recent activities'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.textContaining('Stopped early'), findsOneWidget);
    expect(find.textContaining('Your reported mood difference'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _BreathingAudio extends MeditationAudio {
  final cues = <String>[];
  int pauses = 0;
  @override
  bool get unavailable => false;
  @override
  void cue(String asset) => cues.add(asset);
  @override
  void pause() => pauses++;
  @override
  void resume() {}
  @override
  void stop() {}
}

Future<void> _smallPhone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pump(WidgetTester tester, Widget screen,
    {String language = 'en',
    double scale = 1,
    double keyboardHeight = 0,
    _FakeService? service}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ChangeNotifierProvider(
          create: (_) => TherapyProvider(service: service ?? _FakeService())),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
          viewInsets: EdgeInsets.only(bottom: keyboardHeight),
        ),
        child: Directionality(
          textDirection:
              language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: screen,
    ),
  ));
  await tester.pump();
}

class _FakeService extends TherapyService {
  final List<TherapySession> saved = [];

  @override
  Future<void> syncPending() async {}

  @override
  Future<TherapyRecommendation?> recommendation() async => null;

  @override
  Future<TherapySummary?> summary() async => TherapySummary(
      totalSessions: saved.length,
      completedSessions: 0,
      totalSeconds: 0,
      periodDays: 30);

  @override
  Future<List<TherapySession>> history({int limit = 30}) async => saved;

  @override
  Future<TherapySession> record({
    required String type,
    required String activityId,
    required int durationSeconds,
    int? moodBefore,
    int? moodAfter,
    String? breathingParticipation,
    bool completed = true,
    String? clientRequestId,
    DateTime? clientCompletedAt,
    TherapyMeasures? measures,
  }) async {
    final session = TherapySession(
      id: 'test-${saved.length}',
      activityType: type,
      activityId: activityId,
      durationSeconds: durationSeconds,
      moodBefore: moodBefore,
      moodAfter: moodAfter,
      breathingParticipation: breathingParticipation,
      measures: measures,
      completed: completed,
      completedAt: DateTime.now(),
    );
    saved.add(session);
    return session;
  }
}
