import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/content_models.dart';
import 'package:hercare/presentation/content/content_actions.dart';
import 'package:hercare/presentation/content/content_cache.dart';
import 'package:hercare/presentation/content/content_for_you_card.dart';
import 'package:hercare/presentation/content/content_screen.dart';
import 'package:hercare/presentation/content/content_widgets.dart';
import 'package:hercare/presentation/shared/app_language_bar.dart';
import 'package:hercare/providers/content_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/content_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _at = DateTime.utc(2026, 10, 15, 12);
const _origin = 'https://api.hercare.example/api/v1';
Map<String, dynamic> contentData({Map<String, dynamic> overrides = const {}}) =>
    {
      'id': '00000000-0000-4000-8000-000000000001',
      'version': 1,
      'title_en': 'A gentle moment',
      'title_ur': 'سکون کا ایک لمحہ',
      'summary_en': 'Small, practical support for a busy day.',
      'summary_ur': 'مصروف دن میں ایک چھوٹی مدد۔',
      'body_en': 'Pause for a moment. Ask a trusted person for practical help.',
      'body_ur':
          'ایک لمحے کے لیے رکیں۔ کسی قابل اعتماد فرد سے عملی مدد مانگیں۔',
      'category': 'psychoeducation',
      'format': 'article',
      'audience': 'both',
      'source_name': 'Reviewed educational source',
      'license_name': 'Original text',
      'saved': true,
      'reason_en': 'A short format based on your recent mood.',
      'reason_ur': 'حالیہ موڈ کے مطابق مختصر رہنمائی۔',
      'review_after': _at.add(const Duration(days: 3)).toIso8601String(),
      ...overrides,
    };
ContentItem _item([Map<String, dynamic> overrides = const {}]) =>
    ContentItem.fromJson(contentData(overrides: overrides));
ContentFeed _feed(
        {List<ContentItem>? items,
        bool safety = false,
        ContentPreferences preferences = const ContentPreferences(),
        String revision = 'one'}) =>
    ContentFeed(
        items: items ?? [_item()],
        preferences: preferences,
        catalogRevision: revision,
        generatedAt: _at,
        refreshAfterSeconds: 30,
        safetyPriority: safety,
        allowedMediaHosts: const ['media.example']);

class FakeContent extends ContentService {
  FakeContent() : super(client: Dio(BaseOptions(baseUrl: _origin)));
  ContentFeed current = _feed();
  CachedContent? cached;
  Completer<ContentFeed>? pending;
  Object? feedError, detailError;
  int feedCalls = 0, detailCalls = 0, clears = 0;
  bool uncertain = false;
  bool stickyCache = false;
  bool deniedPreferences = false;
  final requests = <String>[];
  final feedbackValues = <String>[];
  ContentPreferences? nextPreferences;
  @override
  Future<ContentFeed> feed(
      {required String language, bool savedOnly = false}) async {
    feedCalls++;
    if (feedError != null) throw feedError!;
    if (pending != null) return pending!.future;
    return current;
  }

  final detailReasons = <String?>[];
  final engagements = <String>[];
  @override
  Future<ContentItem> detail(String id, {String? reason}) async {
    detailCalls++;
    detailReasons.add(reason);
    if (detailError != null) throw detailError!;
    return current.items.first;
  }

  @override
  Future<void> engagement(String id, String event,
      {int seconds = 0, String? reason}) async {
    engagements.add('$event:$seconds');
  }

  LiveFeed liveResult = const LiveFeed();
  final hiddenLive = <String>[];
  @override
  Future<LiveFeed> live({required String language}) async => liveResult;
  @override
  Future<void> hideLive(String videoId) async => hiddenLive.add(videoId);

  @override
  Future<CachedContent?> readCache() async => cached;
  @override
  Future<void> clearCache() async {
    if (stickyCache) throw StateError('Secure storage unavailable');
    cached = null;
    clears++;
  }

  @override
  Future<void> writeCache(List<ContentItem> items,
      ContentPreferences preferences, String revision) async {
    cached = CachedContent(
        items
            .where((item) =>
                item.saved && item.canSaveOffline && preferences.allows(item))
            .toList(),
        preferences,
        revision,
        _at);
  }

  @override
  Future<ContentPreferences> preferences(ContentPreferences value) async {
    if (deniedPreferences) {
      throw const ContentException('Access removed', statusCode: 403);
    }
    nextPreferences = value;
    current = _feed(
        preferences: ContentPreferences(
            religiousEnabled: value.religiousEnabled,
            musicEnabled: value.musicEnabled,
            disabledCategories: value.disabledCategories,
            version: value.version + 1));
    return current.preferences;
  }

  @override
  Future<void> feedback(String id, String value, String requestId) async {
    requests.add(requestId);
    feedbackValues.add(value);
    if (uncertain) {
      uncertain = false;
      throw const ContentException('Timeout', offline: true);
    }
  }

  @override
  Future<void> save(String id, bool saved, String requestId) async {
    requests.add(requestId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
  });

  test('catalogue models parse numeric strings and retain availability', () {
    final item = _item({'duration_seconds': '120', 'version': '3'});
    expect(item.durationSeconds, 120);
    expect(item.version, 3);
    expect(ContentItem.fromJson(item.toJson()).reviewAfter, item.reviewAfter);
    expect(_item({'duration_seconds': 'huge'}).durationSeconds, isNull);
    expect(
        _item({'category': 'quran', 'is_religious': false}).isReligious, true);
    expect(() => _item({'review_after': 'not-a-date'}), throwsFormatException);
    expect(() => _item({'format': 'untrusted_native_intent'}),
        throwsFormatException);
    expect(() => _item({'id': '../private'}), throwsFormatException);
    final offline =
        _item({'media_url': 'https://media.example/watch'}).toOfflineJson();
    expect(offline.containsKey('reason_en'), false);
    expect(offline.containsKey('media_url'), false);
    expect(offline.containsKey('feedback'), false);
    expect(offline['review_after'], isNotNull);
  });

  test('only exact reviewed HTTPS hosts and allow-listed M9 actions open', () {
    expect(
        ContentActions.mediaLink(
            'https://media.example/watch?v=a', ['media.example']),
        isNotNull);
    for (final url in [
      'http://media.example/a',
      'https://user:secret@media.example/a',
      'https://media.example.evil.test/a',
      'https://media.example:8080/a',
      'https://127.0.0.1/a',
      'https://localhost/a',
      'javascript:alert(1)',
      'intent://a'
    ]) {
      expect(ContentActions.mediaLink(url, ['media.example']), isNull);
    }
    final game = _item({
      'format': 'activity',
      'category': 'game',
      'activity_id': 'memory_match',
      'activity_type': 'game'
    });
    expect(ContentActions.activityRoute(game, role: 'mother'),
        '/therapy/game?id=memory_match');
    expect(ContentActions.activityRoute(game, role: 'guardian'), isNull);
    expect(
        ContentActions.activityRoute(
            _item({
              'format': 'activity',
              'activity_id': 'memory_match',
              'activity_type': 'cbt'
            }),
            role: 'mother'),
        isNull);
    expect(
        ContentActions.activityRoute(
            _item({
              'format': 'activity',
              'activity_id': '/settings',
              'activity_type': 'game'
            }),
            role: 'mother'),
        isNull);
  });

  test(
      'encrypted cache stores only saved text, bounded and owner/origin-specific',
      () async {
    final cache = ContentCache(now: () => _at);
    final values = List.generate(24, (i) => _item({'id': 'item-$i'}));
    await cache.save(
        'mother-a',
        _origin,
        [
          ...values,
          _item({'id': 'unsaved', 'saved': false}),
          _item({
            'id': 'video',
            'format': 'video',
            'media_url': 'https://media.example/a'
          })
        ],
        const ContentPreferences(),
        'one');
    final cached = await cache.read('mother-a', _origin);
    expect(cached!.items.length, 20);
    expect(
        cached.items.every((item) =>
            item.canSaveOffline &&
            item.mediaUrl == null &&
            item.reasonEn.isEmpty),
        true);
    expect(await cache.read('mother-b', _origin), isNull);
    expect(
        await cache.read('mother-a', 'https://other.example/api/v1'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((key) => key.startsWith('m11')), isEmpty);
    final secure = await const FlutterSecureStorage().readAll();
    expect(secure.length, 1);
    expect(secure.values.single, isNot(contains('recent mood')));
  });

  test('offline copies expire at 24h, review expiry and publication window',
      () async {
    var clock = _at;
    final cache = ContentCache(now: () => clock);
    await cache.save(
        'mother-a',
        _origin,
        [
          _item({
            'id': 'review',
            'review_after':
                _at.add(const Duration(minutes: 10)).toIso8601String()
          }),
          _item({
            'id': 'ends',
            'available_until':
                _at.add(const Duration(minutes: 5)).toIso8601String()
          }),
          _item({
            'id': 'future',
            'available_from':
                _at.add(const Duration(hours: 1)).toIso8601String()
          }),
          _item({'id': 'active'}),
        ],
        const ContentPreferences(),
        'one');
    expect(
        (await cache.read('mother-a', _origin))!.items.map((item) => item.id),
        ['review', 'ends', 'active']);
    clock = _at.add(const Duration(minutes: 10));
    expect(
        (await cache.read('mother-a', _origin))!.items.map((item) => item.id),
        ['active']);
    clock = _at.add(const Duration(hours: 24, seconds: 1));
    expect(await cache.read('mother-a', _origin), isNull);
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });

  test('preferences default opt-out and disabled categories filter cached text',
      () async {
    final cache = ContentCache(now: () => _at);
    await cache.save(
        'mother-a',
        _origin,
        [
          _item(),
          _item({'id': 'quran', 'category': 'quran'}),
          _item({'id': 'music', 'is_music': true})
        ],
        const ContentPreferences(),
        'one');
    expect((await cache.read('mother-a', _origin))!.items.length, 1);
    await cache.save(
        'mother-a',
        _origin,
        [_item()],
        const ContentPreferences(disabledCategories: ['psychoeducation']),
        'one');
    expect((await cache.read('mother-a', _origin))!.items, isEmpty);
  });

  test(
      'service binds header and rejects old-account replies, redirects and invalid responses',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _origin));
    final barrier = Completer<void>();
    final started = Completer<void>();
    RequestOptions? captured;
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) async {
      captured = request;
      started.complete();
      await barrier.future;
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'success': true,
        'data': {
          'items': [],
          'preferences': {},
          'catalog_revision': 'one',
          'generated_at': _at.toIso8601String()
        }
      }));
    }));
    final service = ContentService(client: dio)..bindAccount('mother-a');
    final read = service.feed(language: 'ur', savedOnly: true);
    await started.future;
    expect(captured!.headers['X-Content-Account-Id'], 'mother-a');
    expect(captured!.headers.containsKey('Cache-Control'), false);
    expect(captured!.followRedirects, false);
    expect(captured!.queryParameters['limit'], 100);
    service.bindAccount('mother-b');
    barrier.complete();
    await expectLater(read, throwsA(isA<ContentAccountException>()));
  });

  test('late feed cannot cross account or logout; identical loads coalesce',
      () async {
    final fake = FakeContent()..pending = Completer<ContentFeed>();
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    final old = provider.load();
    final coalesced = provider.load();
    await Future<void>.delayed(Duration.zero);
    expect(fake.feedCalls, 1);
    provider.bindAccount('mother-b', role: 'mother');
    final oldBarrier = fake.pending!;
    fake.pending = null;
    fake.current = _feed(items: [
      _item({'id': 'mother-b-only'})
    ]);
    await provider.load();
    oldBarrier.complete(_feed(items: [
      _item({'id': 'mother-a-private'})
    ]));
    await Future.wait([old, coalesced]);
    expect(provider.items().single.id, 'mother-b-only');
    provider.bindAccount(null);
    expect(provider.items(), isEmpty);
    expect(provider.preferences.religiousEnabled, false);
    provider.dispose();
  });

  test(
      'catalogue/pref revision and access denial purge copies; crisis blocks detail',
      () async {
    final fake = FakeContent()
      ..cached =
          CachedContent([_item()], const ContentPreferences(), 'old', _at);
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(fake.clears, 1);
    await provider.load(savedOnly: true, force: true);
    expect(fake.cached, isNotNull);
    fake.feedError = const ContentException('Removed', statusCode: 403);
    await provider.load(force: true);
    expect(provider.items(), isEmpty);
    expect(fake.cached, isNull);
    fake.feedError = null;
    fake.current = _feed(items: [], safety: true);
    await provider.load(force: true);
    expect(provider.safetyPriority, true);
    expect(await provider.detail('id'), isNull);
    expect(fake.detailCalls, 0);
    provider.dispose();
  });

  test(
      'network outage shows only cached text and detail labels offline, never a fresh ranking',
      () async {
    final fake = FakeContent()
      ..cached =
          CachedContent([_item()], const ContentPreferences(), 'one', _at)
      ..feedError = const ContentException('Offline', offline: true)
      ..detailError = const ContentException('Offline', offline: true);
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(provider.isOffline, true);
    expect(provider.items().single.id, _item().id);
    expect(provider.dailyVerse, isNull);
    final detail = await provider.detail(_item().id);
    expect(detail!.offline, true);
    expect(detail.savedAt, _at);
    expect(provider.refreshInterval, const Duration(seconds: 60));
    provider.dispose();
  });

  test('feedback retries use one UUID but a different intent uses a new one',
      () async {
    final fake = FakeContent()..uncertain = true;
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(await provider.giveFeedback(_item(), 'helpful'), false);
    expect(await provider.giveFeedback(_item(), 'helpful'), true);
    expect(fake.requests[0], fake.requests[1]);
    expect(await provider.giveFeedback(_item(), 'not_helpful'), true);
    expect(fake.requests.last, isNot(fake.requests.first));
    expect(await provider.setSaved(_item(), false), true);
    provider.dispose();
  });

  test('preferences save is versioned and clears copies before new suggestions',
      () async {
    final fake = FakeContent();
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load(savedOnly: true);
    expect(
        await provider.updatePreferences(const ContentPreferences(
            religiousEnabled: true, musicEnabled: false, version: 0)),
        true);
    expect(fake.nextPreferences!.version, 0);
    expect(provider.preferences.religiousEnabled, true);
    expect(fake.clears, greaterThan(0));
    provider.dispose();
  });

  test('fresh preferences and host policy survive a changed cached catalogue',
      () async {
    final fake = FakeContent()
      ..cached =
          CachedContent([_item()], const ContentPreferences(), 'old', _at)
      ..current = _feed(
          items: [
            _item({'category': 'quran', 'is_religious': true})
          ],
          preferences:
              const ContentPreferences(religiousEnabled: true, version: 2),
          revision: 'new');
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(provider.preferences.religiousEnabled, true);
    expect(provider.items().single.category, 'quran');
    expect(provider.allowedMediaHosts, ['media.example']);
    provider.dispose();
  });

  test(
      'a stale saved-list preference never overrides a newer server preference',
      () async {
    final fake = FakeContent()
      ..current = _feed(
          items: [
            _item({'id': 'religious', 'category': 'quran'})
          ],
          preferences:
              const ContentPreferences(religiousEnabled: true, version: 1));
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load(savedOnly: true);
    expect(provider.items(savedOnly: true), hasLength(1));
    fake.current =
        _feed(items: [], preferences: const ContentPreferences(version: 2));
    await provider.load(force: true);
    expect(provider.items(savedOnly: true), isEmpty);
    provider.dispose();
  });

  test(
      'failed secure-cache deletion cannot resurrect an old copy after revocation',
      () async {
    final fake = FakeContent()
      ..cached =
          CachedContent([_item()], const ContentPreferences(), 'old', _at)
      ..stickyCache = true;
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    fake.detailError = const ContentException('Offline', offline: true);
    await expectLater(
        provider.detail(_item().id), throwsA(isA<ContentException>()));
    fake.deniedPreferences = true;
    expect(await provider.updatePreferences(const ContentPreferences()), false);
    expect(provider.items(), isEmpty);
    expect(provider.allowedMediaHosts, isEmpty);
    provider.dispose();
  });

  test('new care marker queues a fresh server read even during an old request',
      () async {
    final fake = FakeContent()..pending = Completer<ContentFeed>();
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    final loading = provider.load();
    await Future<void>.delayed(Duration.zero);
    final first = fake.pending!;
    fake.pending = null;
    final before = provider.signalRevision;
    provider.observeCareRevision('new-aggregate-record');
    provider.observeCareRevision('new-aggregate-record');
    expect(provider.signalRevision, before + 1);
    fake.current = _feed(items: [
      _item({'id': 'fresh-after-care-change'})
    ]);
    first.complete(_feed(items: [
      _item({'id': 'old'})
    ]));
    await loading;
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(fake.feedCalls, 2);
    expect(provider.items().single.id, 'fresh-after-care-change');
    provider.dispose();
  });

  test('changing the API origin discards old memory and binds the next read',
      () async {
    final dio = Dio(BaseOptions(baseUrl: _origin));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: {
        'success': true,
        'data': {
          'items': [
            contentData(overrides: {
              'id': request.baseUrl == _origin ? 'old-origin' : 'new-origin'
            })
          ],
          'preferences': {},
          'catalog_revision': 'one',
          'generated_at': _at.toIso8601String()
        }
      }));
    }));
    final provider =
        ContentProvider(service: ContentService(client: dio), now: () => _at)
          ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(provider.items().single.id, 'old-origin');
    dio.options.baseUrl = 'https://new-api.example/api/v1';
    expect(provider.items(), isEmpty);
    await provider.load();
    expect(provider.items().single.id, 'new-origin');
    provider.dispose();
  });

  test(
      'in-memory offline items expire during a continuing outage without restart',
      () async {
    var clock = _at;
    final fake = FakeContent()
      ..cached = CachedContent([
        _item({
          'id': 'review',
          'review_after': _at.add(const Duration(minutes: 5)).toIso8601String()
        }),
        _item({
          'id': 'publication',
          'available_until':
              _at.add(const Duration(minutes: 10)).toIso8601String()
        }),
        _item({'id': 'regular'}),
      ], const ContentPreferences(), 'one', _at)
      ..feedError = const ContentException('Offline', offline: true);
    final provider = ContentProvider(service: fake, now: () => clock)
      ..bindAccount('mother-a', role: 'mother');
    await provider.load();
    expect(provider.items(), hasLength(3));
    clock = _at.add(const Duration(minutes: 6));
    await provider.load(force: true);
    expect(provider.items().map((item) => item.id), ['publication', 'regular']);
    clock = _at.add(const Duration(hours: 24, seconds: 1));
    await provider.load(force: true);
    expect(provider.items(), isEmpty);
    provider.dispose();
  });

  testWidgets(
      'small-phone English/Urdu feed, filters, reader and preference sheet do not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final language = LanguageProvider();
    final fake = FakeContent();
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(value: language),
          ChangeNotifierProvider<ContentProvider>.value(value: provider),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: Directionality(
                    textDirection:
                        language.isUrdu ? TextDirection.rtl : TextDirection.ltr,
                    child: child!)),
            home: const ContentScreen())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('View content →').hitTestable(), 150);
    await tester.tap(find.text('View content →').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('A gentle moment'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Not helpful').hitTestable(), 150,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await language.setLocale(const Locale('ur'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('مواد کی پسند'));
    await tester.pumpAndSettle();
    expect(find.text('اسلامی اور قرآنی مواد'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('پسند محفوظ کریں'), 180,
        scrollable: find.byType(Scrollable).last);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    language.dispose();
  });

  testWidgets('home card does not poll while inactive and starts when visible',
      (tester) async {
    final fake = FakeContent();
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    Widget host(bool active) => MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => LanguageProvider()),
              ChangeNotifierProvider<ContentProvider>.value(value: provider),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: ContentForYouCard(
                            active: active, onOpen: () {})))));
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(fake.feedCalls, 0);
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(fake.feedCalls, 1);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    // The fake wall clock need not advance; provider also enforces freshness.
    expect(fake.feedCalls, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('account scope disposes old private view immediately',
      (tester) async {
    final provider = ContentProvider(service: FakeContent(), now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider<ContentProvider>.value(value: provider),
        ],
        child: const MaterialApp(
            home: ContentAccountScope(child: Text('Old private view')))));
    expect(find.text('Old private view'), findsOneWidget);
    provider.bindAccount('mother-b', role: 'mother');
    await tester.pumpAndSettle();
    expect(find.text('Old private view'), findsNothing);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets(
      'Urdu Quran reader stays responsive at 2x text with the global language bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_language': 'ur'});
    final language = LanguageProvider();
    final fake = FakeContent()
      ..current = _feed(items: [
        _item({
          'category': 'quran',
          'arabic_text': 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
          'verse_reference': '94:5',
          'transliteration': 'Fa inna ma al usri yusra',
        })
      ], preferences: const ContentPreferences(religiousEnabled: true));
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(value: language),
          ChangeNotifierProvider<ContentProvider>.value(value: provider),
        ],
        child: MaterialApp(
            builder: (context, child) => Consumer<LanguageProvider>(
                builder: (context, value, _) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: AppLanguageBar(child: child!)))),
            home: ContentScreen(initialItemId: _item().id))));
    await tester.pumpAndSettle();
    expect(find.text('مواد'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('مفید نہیں').hitTestable(), 160,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    language.dispose();
  });

  test(
      'YouTube previews come only from exact video links; reason codes stay out of offline copies',
      () {
    final video = _item({
      'format': 'video',
      'media_url': 'https://www.youtube.com/watch?v=KBlVBOP7TGc',
      'reason_codes': ['low_mood', 'stage', 'BAD CODE'],
    });
    expect(video.youtubeId, 'KBlVBOP7TGc');
    expect(
        video.thumbnailUrl, 'https://i.ytimg.com/vi/KBlVBOP7TGc/hqdefault.jpg');
    expect(video.primaryReason, 'low_mood');
    expect(video.reasonCodes, ['low_mood', 'stage']);
    expect(video.toOfflineJson().containsKey('reason_codes'), false);
    expect(_item({'media_url': 'https://youtu.be/KBlVBOP7TGc'}).youtubeId,
        'KBlVBOP7TGc');
    for (final bad in [
      'http://www.youtube.com/watch?v=KBlVBOP7TGc',
      'https://www.youtube.com.evil.example/watch?v=KBlVBOP7TGc',
      'https://www.youtube.com/watch?v=short',
      'https://media.example/watch?v=KBlVBOP7TGc',
    ]) {
      expect(_item({'media_url': bad}).thumbnailUrl, isNull, reason: bad);
    }
  });

  Map<String, dynamic> liveJson(String id,
          {Map<String, dynamic> extra = const {}}) =>
      {
        'video_id': id,
        'title': 'Gentle breathing for new mothers',
        'channel_title': 'Headspace',
        'topic': 'calm',
        'category': 'soothing',
        'duration_seconds': 300,
        'reviewed': false,
        'reason_en': 'Live from a trusted channel, for a calm moment.',
        ...extra,
      };

  test('live results reject reviewed claims, bad IDs and oversized lists', () {
    final video = LiveVideo.fromJson(liveJson('abcdefghijk'));
    expect(video.mediaUrl, 'https://www.youtube.com/watch?v=abcdefghijk');
    expect(
        video.thumbnailUrl, 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg');
    for (final bad in [
      liveJson('short'),
      liveJson('abcdefghijk', extra: {'reviewed': true}),
      liveJson('abcdefghijk', extra: {'category': 'native_intent'}),
      liveJson('abcdefghijk', extra: {'title': ''}),
    ]) {
      expect(() => LiveVideo.fromJson(bad), throwsFormatException);
    }
    expect(
        () => LiveFeed.fromJson(
            {'items': List.generate(9, (i) => liveJson('abcdefghij$i'))}),
        throwsFormatException);
  });

  testWidgets(
      'live section is labelled unreviewed, respects music opt-out, hides on request and disappears in a crisis',
      (tester) async {
    final language = LanguageProvider();
    final fake = FakeContent()
      ..liveResult = LiveFeed.fromJson({
        'enabled': true,
        'notice_en': 'Not individually reviewed by HerCare.',
        'items': [
          liveJson('abcdefghijk'),
          liveJson('musicmusic1',
              extra: {'title': 'Calm piano', 'is_music': true}),
        ],
      });
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<LanguageProvider>.value(value: language),
      ChangeNotifierProvider<ContentProvider>.value(value: provider),
    ], child: const MaterialApp(home: ContentScreen())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Live from YouTube'), 200);
    expect(find.text('Not individually reviewed by HerCare.'), findsOneWidget);
    expect(find.text('Gentle breathing for new mothers'), findsOneWidget);
    expect(find.text('Calm piano'), findsNothing,
        reason: 'music needs her opt-in, even if the server sent it');
    await tester.scrollUntilVisible(
        find.text("Don't show this").hitTestable(), 200);
    await tester.tap(find.text("Don't show this").hitTestable());
    await tester.pumpAndSettle();
    expect(fake.hiddenLive, ['abcdefghijk']);
    expect(find.text('Gentle breathing for new mothers'), findsNothing);
    fake.liveResult = LiveFeed.fromJson({
      'enabled': true,
      'items': [liveJson('zyxwvutsrqp')]
    });
    fake.current = _feed(safety: true);
    await provider.load(force: true);
    await tester.pumpAndSettle();
    expect(find.text('Live from YouTube'), findsNothing);
    expect(provider.liveVideos, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    language.dispose();
  });

  test('interests and formats round-trip and unknown values are dropped', () {
    final value = ContentPreferences.fromJson({
      'religious_enabled': true,
      'interests': ['sleep', 'faith', 'not_a_topic'],
      'preferred_formats': ['video', 'hologram'],
      'version': 2,
    });
    expect(value.interests, ['sleep', 'faith']);
    expect(value.preferredFormats, ['video']);
    expect(value.toJson()['interests'], ['sleep', 'faith']);
    expect(const ContentPreferences().toJson()['preferred_formats'], isEmpty);
  });

  testWidgets(
      'opening a card reports its reason once and the sheet saves chosen topics',
      (tester) async {
    final language = LanguageProvider();
    final fake = FakeContent()
      ..current = _feed(items: [
        _item({
          'reason_codes': ['interest']
        })
      ]);
    final provider = ContentProvider(service: fake, now: () => _at)
      ..bindAccount('mother-a', role: 'mother');
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<LanguageProvider>.value(value: language),
      ChangeNotifierProvider<ContentProvider>.value(value: provider),
    ], child: const MaterialApp(home: ContentScreen())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('View content →').hitTestable(), 150);
    await tester.tap(find.text('View content →').hitTestable());
    await tester.pumpAndSettle();
    expect(fake.detailReasons.first, 'interest');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(fake.detailReasons.last, isNull, reason: 'reason is sent once');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Content preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Quran and dua'), findsNothing,
        reason: 'faith topic needs the religious opt-in');
    await tester.tap(find.text('Sleep'));
    await tester.ensureVisible(find.text('Videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Save preferences'), 180,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(fake.nextPreferences?.interests, ['sleep']);
    expect(fake.nextPreferences?.preferredFormats, ['video']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    language.dispose();
  });
}
