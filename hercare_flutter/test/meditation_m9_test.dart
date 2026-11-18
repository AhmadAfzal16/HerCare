import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';
import 'package:hercare/presentation/therapy/meditation_audio.dart';
import 'package:hercare/presentation/therapy/meditation_guides.dart';
import 'package:hercare/presentation/therapy/meditation_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:hercare/services/therapy_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Audio extends MeditationAudio {
  final cues = <String>[];
  int pauses = 0, resumes = 0, stops = 0;
  bool failed = false, disposed = false;
  @override
  bool get unavailable => failed;
  @override
  void cue(String asset) => cues.add(asset);
  @override
  void pause() => pauses++;
  @override
  void resume() => resumes++;
  @override
  void stop() => stops++;
  void fail() {
    failed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Language extends LanguageProvider {
  Locale selected = const Locale('en');
  @override
  Locale get locale => selected;
  @override
  bool get isUrdu => selected.languageCode == 'ur';
  @override
  Future<void> setLocale(Locale locale) async {
    selected = locale;
    notifyListeners();
  }
}

class _Clock extends Stopwatch {
  Duration value = Duration.zero;
  bool running = false;
  @override
  Duration get elapsed => value;
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => value = Duration.zero;
}

class _Service extends TherapyService {
  final saves = <Map<String, Object?>>[];
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
    saves.add({
      'completed': completed,
      'seconds': durationSeconds,
      'before': moodBefore,
      'after': moodAfter,
      'id': clientRequestId,
    });
    return TherapySession(
        id: clientRequestId ?? 'test',
        activityType: type,
        activityId: activityId,
        durationSeconds: durationSeconds,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        completed: completed,
        completedAt: clientCompletedAt ?? DateTime.now());
  }
}

Future<void> _mount(WidgetTester tester,
    {required _Audio audio,
    required _Clock clock,
    required _Service service,
    required LanguageProvider language,
    String id = 'body_scan',
    double scale = 1}) async {
  final provider = TherapyProvider(service: service)..bindAccount('mother-a');
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: language),
      ChangeNotifierProvider.value(value: provider),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: Directionality(
            textDirection:
                language.isUrdu ? TextDirection.rtl : TextDirection.ltr,
            child: child!),
      ),
      home: MeditationScreen(activityId: id, audio: audio, activeClock: clock),
    ),
  ));
  await tester.pumpAndSettle();
  addTearDown(provider.dispose);
}

Future<void> _pose(WidgetTester tester, bool urdu) async {
  for (var index = 0; index < 3; index++) {
    final label = index == 2
        ? (urdu ? 'ہاں، شروع کریں' : 'Yes, begin')
        : (urdu ? 'ہاں، اگلا مرحلہ' : 'Yes, next step');
    await tester.ensureVisible(find.text(label));
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, label))
            .onPressed,
        isNotNull,
        reason: 'Posture step $index must be enabled after catalog load');
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await MeditationGuides.load();
  });

  test('all three public guides have four paired captions and local audio',
      () async {
    final guides = await MeditationGuides.load();
    expect(guides.keys,
        containsAll(['body_scan', 'muscle_relaxation', 'mindfulness']));
    for (final entry in guides.entries) {
      expect(entry.value.length, 4);
      for (var index = 0; index < 4; index++) {
        final cue = entry.value[index];
        expect(cue.en, isNotEmpty);
        expect(cue.ur, contains(RegExp(r'[\u0600-\u06ff]')));
        expect(cue.audio(true),
            'assets/audio/meditation/ur_${entry.key}_$index.m4a');
      }
    }
  });

  test('all narration clips are packaged and external audio paths are rejected',
      () async {
    final guides = await MeditationGuides.load();
    for (final steps in guides.values) {
      for (final cue in steps) {
        for (final urdu in [false, true]) {
          final bytes = await rootBundle.load(cue.audio(urdu));
          expect(bytes.lengthInBytes, greaterThan(1000));
        }
      }
    }
    final audio = BundledTherapyAudio();
    expect(() => audio.cue('https://example.com/user-journal.mp3'),
        throwsArgumentError);
    expect(() => audio.cue('assets/audio/meditation/../../private.m4a'),
        throwsArgumentError);
    audio.dispose();
  });

  for (final urdu in [false, true]) {
    for (final id in ['body_scan', 'muscle_relaxation', 'mindfulness']) {
      testWidgets('$id ${urdu ? 'Urdu' : 'English'} 320px 200% setup/practice',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final audio = _Audio(), clock = _Clock(), service = _Service();
        final language = _Language();
        await language.setLocale(Locale(urdu ? 'ur' : 'en'));
        await _mount(tester,
            audio: audio,
            clock: clock,
            service: service,
            language: language,
            id: id,
            scale: 2);
        await _pose(tester, urdu);
        await _tap(tester, urdu ? 'شروع / جاری' : 'Start / Resume');
        expect(audio.cues,
            ['assets/audio/meditation/${urdu ? 'ur' : 'en'}_${id}_0.m4a']);
        clock.value = const Duration(seconds: 80);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(audio.cues.last, endsWith('${id}_1.m4a'));
        await _tap(tester, urdu ? 'وقفہ' : 'Pause');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(audio.disposed, isTrue);
      });
    }
  }

  testWidgets(
      'pause/resume retains step; background and focus interruptions never auto-resume',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: _Language());
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    clock.value = const Duration(seconds: 10);
    await tester.pump(const Duration(milliseconds: 250));
    await _tap(tester, 'Pause');
    expect(clock.running, isFalse);
    await _tap(tester, 'Start / Resume');
    expect(audio.cues.length, 1);
    expect(audio.resumes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(clock.running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(clock.running, isFalse);
    await _tap(tester, 'Start / Resume');
    audio.onInterruption?.call();
    await tester.pump();
    expect(clock.running, isFalse);
    expect(service.saves, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'language change replaces spoken cue with the current-language caption',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    final language = _Language();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: language);
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    unawaited(language.setLocale(const Locale('ur')));
    await tester.pumpAndSettle();
    expect(audio.cues.last, 'assets/audio/meditation/ur_body_scan_0.m4a');
    final guides = MeditationGuides.loaded!;
    expect(find.text(guides['body_scan']!.first.ur), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('audio can be disabled and errors keep honest text guidance',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: _Language());
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    audio.fail();
    await tester.pump();
    expect(find.textContaining('Audio could not play'), findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    clock.value = const Duration(seconds: 160);
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.cues.length, 1);
    expect(clock.running, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ending early saves partial with optional ratings omitted',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: _Language());
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    clock.value = const Duration(seconds: 70);
    await tester.pump(const Duration(milliseconds: 250));
    await _tap(tester, 'End early');
    expect(find.text('Save partial practice'), findsOneWidget);
    await _tap(tester, 'Save partial');
    expect(service.saves.single['completed'], isFalse);
    expect(service.saves.single['seconds'], 70);
    expect(service.saves.single['before'], isNull);
    expect(service.saves.single['after'], isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'timer is not proof; confirmed practice is required to save completion',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: _Language());
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    clock.value = const Duration(seconds: 300);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Did you practise?'), findsOneWidget);
    await _tap(tester, 'Not yet');
    expect(service.saves, isEmpty);
    await _tap(tester, 'Confirm practice and save');
    await _tap(tester, 'Yes, I practised');
    await _tap(tester, 'Save completion');
    expect(service.saves.single['completed'], isTrue);
    expect(service.saves.single['seconds'], 300);
    expect(clock.running, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a covered route pauses narration and active time',
      (tester) async {
    final audio = _Audio(), clock = _Clock(), service = _Service();
    await _mount(tester,
        audio: audio, clock: clock, service: service, language: _Language());
    await _pose(tester, false);
    await _tap(tester, 'Start / Resume');
    final context = tester.element(find.byType(MeditationScreen));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    expect(clock.running, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
