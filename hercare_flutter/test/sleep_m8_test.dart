import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hercare/data/models/sleep_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/digital_wellbeing_service.dart';
import 'package:hercare/presentation/wellbeing/digital_wellbeing_screen.dart';
import 'package:hercare/presentation/wellbeing/sleep_cache.dart';
import 'package:hercare/presentation/wellbeing/sleep_insights_panel.dart';

String _day(DateTime value) => value.toIso8601String().substring(0, 10);
Map<String, dynamic> _fixture({bool safety = false}) {
  final now = DateTime.now().toUtc();
  final anchor = DateTime.utc(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  final records = List.generate(28, (i) {
    final wake =
        anchor.subtract(Duration(days: i)).add(const Duration(hours: 7));
    final minutes = i < 7 ? 300 : 480;
    return {
      'sleep_date': _day(wake),
      'bedtime': wake.subtract(Duration(minutes: minutes)).toIso8601String(),
      'wake_time': wake.toIso8601String(),
      'sleep_minutes': '$minutes',
      'awake_minutes': 0,
      'quality': null,
      'awakenings': null,
      'timezone_offset_minutes': 0,
      'journal': 'MUST_NOT_CACHE',
      'package_name': 'MUST_NOT_CACHE'
    };
  });
  return {
    'records': records,
    'summary': {'average_minutes': '300', 'recorded_nights': 7},
    'insights': {
      'version': 'm8-observed-v1',
      'as_of': _day(anchor),
      'stale': false,
      'safety_priority': safety,
      'activity': safety ? 'crisis' : 'body_scan',
      'patterns': [
        'repeated_short_sleep',
        'less_sleep_than_previous_period',
        'variable_sleep_timing'
      ],
      'windows': [
        for (final days in [7, 14, 30])
          {
            'days': days,
            'minimum_nights': days == 7
                ? 5
                : days == 14
                    ? 10
                    : 14,
            'current': {
              'nights': days == 30 ? 28 : days,
              'average_minutes': days == 7 ? 300 : 390,
              'average_quality': null,
              'short_nights': 7
            },
            'previous': {
              'nights': days == 30 ? 0 : days,
              'average_minutes': days == 30 ? null : 480
            },
            'change_minutes': days == 30
                ? null
                : days == 7
                    ? -180
                    : -90,
            'direction':
                days == 30 ? 'insufficient_data' : 'less_recorded_sleep'
          }
      ],
      'correlation': {
        'status': 'available',
        'direction': 'positive',
        'paired_days': 28,
        'minimum_days': 14,
        'coefficient': '1.000',
        'under_six_hours': {'days': 7, 'average_mood': '2.0'},
        'six_hours_or_more': {'days': 21, 'average_mood': '4.0'}
      },
      'digital': {
        'sharing_enabled': true,
        'fresh': true,
        'recorded_days': 7,
        'high_social_days': 3,
        'late_use_days': 5,
        'average_social_minutes': 300,
        'average_late_night_minutes': 40
      }
    }
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'M8 parses numeric strings, preserves nulls and drops private extra fields',
      () {
    final dashboard = SleepDashboard.fromJson(_fixture());
    expect(dashboard.average, 300);
    expect(dashboard.records.first.quality, isNull);
    expect(dashboard.records.first.awakenings, isNull);
    expect(dashboard.insights!.windows.last.change, isNull);
    expect(jsonEncode(dashboard.toJson()), isNot(contains('MUST_NOT_CACHE')));
  });
  test(
      'M8 rejects corrupt intervals, nonfinite values, unsupported activities and missing counts',
      () {
    final fixture = _fixture();
    final record =
        Map<String, dynamic>.from((fixture['records'] as List).first);
    for (final change in [
      {'sleep_minutes': 'NaN'},
      {'quality': 2.5},
      {'sleep_minutes': 999},
      {'sleep_date': '2026-02-30'},
      {'timezone_offset_minutes': null}
    ]) {
      expect(() => SleepRecord.fromJson({...record, ...change}),
          throwsFormatException);
    }
    final insights = Map<String, dynamic>.from(fixture['insights']);
    expect(
        () => SleepInsights.fromJson(
            {...insights, 'activity': 'untrusted_download'}),
        throwsFormatException);
    expect(() => SleepDashboard.fromJson({...fixture, 'summary': {}}),
        throwsFormatException);
    expect(
        () => SleepDashboard.fromJson(
            {...fixture, 'records': List.filled(31, record)}),
        throwsFormatException);
  });
  test(
      'M8 encrypted cache is account/origin bound, expires and excludes raw content',
      () async {
    var now = DateTime.utc(2026, 10, 11);
    const storage = FlutterSecureStorage();
    final cache = SleepCache(
        apiOrigin: 'https://test.example/api/v1',
        now: () => now,
        storage: storage);
    await cache.save('mother-a', SleepDashboard.fromJson(_fixture()));
    expect((await cache.read('mother-a'))!.dashboard.average, 300);
    expect(await cache.read('mother-b'), isNull);
    expect(await storage.read(key: 'm8_sleep_v1_mother-a'),
        isNot(contains('MUST_NOT_CACHE')));
    now = now.add(const Duration(days: 8));
    expect(await cache.read('mother-a'), isNull);
    expect(await storage.read(key: 'm8_sleep_v1_mother-a'), isNull);
    await cache.save('mother-a', SleepDashboard.fromJson(_fixture()));
    expect(
        await SleepCache(apiOrigin: 'https://another.example', now: () => now)
            .read('mother-a'),
        isNull);
    await storage.write(key: 'm8_sleep_v1_mother-a', value: 'not-json');
    expect(await cache.read('mother-a'), isNull);
    expect(() => cache.clear('../mother'), throwsFormatException);
  });
  test('M8 future-dated and oversized cache copies are rejected', () async {
    const storage = FlutterSecureStorage();
    final now = DateTime.utc(2026, 10, 11);
    await SleepCache(
            apiOrigin: 'test', now: () => now.add(const Duration(hours: 1)))
        .save('mother-a', SleepDashboard.fromJson(_fixture()));
    expect(await SleepCache(apiOrigin: 'test', now: () => now).read('mother-a'),
        isNull);
    await storage.write(
        key: 'm8_sleep_v1_mother-a', value: List.filled(64001, 'x').join());
    expect(await SleepCache(apiOrigin: 'test').read('mother-a'), isNull);
  });
  for (final language in ['en', 'ur']) {
    testWidgets(
        'M8 trends, history and optional editor fit 320x480 at 200% text in $language',
        (tester) async {
      final service = _Service();
      await _pump(tester, service: service, language: language);
      await _reveal(tester, find.byKey(const ValueKey('sleep-window-30')));
      await tester.tap(find.byKey(const ValueKey('sleep-window-30')));
      await tester.pumpAndSettle();
      expect(service.reads, 1,
          reason: 'switching a period reuses the same result');
      await _reveal(
          tester,
          find.text(language == 'ur'
              ? 'حساب کیسے ہوتا ہے'
              : 'How this is calculated'));
      await tester.tap(find.text(
          language == 'ur' ? 'حساب کیسے ہوتا ہے' : 'How this is calculated'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Return to the collapsed history and correct a real record.
      final list = find.byType(ListView).first;
      for (var i = 0; i < 60; i++) {
        await tester.drag(list, const Offset(0, 240));
        await tester.pumpAndSettle();
      }
      final history =
          find.text(language == 'ur' ? 'محفوظ راتیں' : 'Saved nights');
      await _reveal(tester, history);
      await tester.tap(history);
      await tester.pumpAndSettle();
      final edit = find
          .text(
              language == 'ur' ? 'اس رات کی درستگی کریں' : 'Correct this night')
          .first;
      await _reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save =
          find.text(language == 'ur' ? 'نیند محفوظ کریں' : 'Save sleep');
      await _reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.quality, isNull);
      expect(service.awakenings, isNull);
      expect(service.offset, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'M8 offline shows only own encrypted saved copy; server denial clears it',
      (tester) async {
    final cache = SleepCache(apiOrigin: 'test');
    await cache.save('mother-a', SleepDashboard.fromJson(_fixture()));
    final service = _Service()..offline = true;
    await _pump(tester, service: service, cache: cache);
    await _reveal(tester, find.textContaining('Offline:'));
    expect(find.textContaining('not live records'), findsOneWidget);
    service
      ..offline = false
      ..denied = true;
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Private sleep access is unavailable'),
        findsOneWidget);
    expect(await cache.read('mother-a'), isNull);
  });
  testWidgets(
      'M8 late previous-account response is neither rendered nor cached',
      (tester) async {
    final auth = _Auth('mother-a');
    final cache = SleepCache(apiOrigin: 'test');
    final pending = Completer<Map<String, dynamic>>();
    final service = _Service()..pending = pending.future;
    await _pump(tester,
        service: service, auth: auth, cache: cache, settle: false);
    auth.change('mother-b');
    await tester.pump();
    pending.complete(_fixture());
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text('Your saved sleep'), findsNothing);
    expect(await cache.read('mother-a'), isNull);
    expect(await cache.read('mother-b'), isNull);
  });
  testWidgets('M8 open editor hides private values when the account changes',
      (tester) async {
    final auth = _Auth('mother-a');
    await _pump(tester, service: _Service(), auth: auth);
    await _reveal(tester, find.text('Log / correct sleep'));
    await tester.tap(find.text('Log / correct sleep'));
    await tester.pumpAndSettle();
    auth.change(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text('Save sleep'), findsNothing);
  });
  for (final safety in [false, true]) {
    testWidgets(
        'M8 activity navigation safety=$safety opens the existing destination',
        (tester) async {
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
                    body: ListView(children: [
                  SleepInsightsPanel(
                      insights:
                          SleepDashboard.fromJson(_fixture(safety: safety))
                              .insights!)
                ]))),
        GoRoute(
            path: '/therapy/meditation',
            builder: (_, state) => Scaffold(
                body: Text('M9:${state.uri.queryParameters['id'] ?? ''}'))),
        GoRoute(
            path: '/crisis',
            builder: (_, __) => const Scaffold(body: Text('M10:help')))
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(const ValueKey('sleep-activity')));
      await tester.tap(find.byKey(const ValueKey('sleep-activity')));
      await tester.pumpAndSettle();
      expect(find.text(safety ? 'M10:help' : 'M9:body_scan'), findsOneWidget);
    });
  }
}

Future<void> _pump(WidgetTester tester,
    {required _Service service,
    _Auth? auth,
    SleepCache? cache,
    String language = 'en',
    bool settle = true}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.binding.setSurfaceSize(const Size(320, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider<AuthProvider>.value(
            value: auth ?? _Auth('mother-a'))
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(
                  textDirection:
                      language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
                  child: child!)),
          home: DigitalWellbeingScreen(
              accountId: 'mother-a',
              service: service,
              cache: cache ?? SleepCache(apiOrigin: 'test')))));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsWidgets);
}

class _Auth extends AuthProvider {
  _Auth(this.id);
  String? id;
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026));
  void change(String? value) {
    id = value;
    notifyListeners();
  }
}

class _Service extends DigitalWellbeingService {
  bool offline = false, denied = false;
  Future<Map<String, dynamic>>? pending;
  int reads = 0, saves = 0;
  int? quality, awakenings, offset;
  @override
  Future<Map<String, dynamic>> usage() async =>
      {'supported': true, 'permission': false};
  @override
  Future<Map<String, dynamic>> sleep() async {
    reads++;
    if (denied) throw SleepAccessException();
    if (offline) throw Exception('offline');
    return pending == null ? _fixture() : await pending!;
  }

  @override
  Future<void> saveSleep(
      {required DateTime bedtime,
      required DateTime wake,
      required int awakeMinutes,
      required int? quality,
      required int? awakenings,
      int? timezoneOffsetMinutes}) async {
    saves++;
    this.quality = quality;
    this.awakenings = awakenings;
    offset = timezoneOffsetMinutes;
  }
}
