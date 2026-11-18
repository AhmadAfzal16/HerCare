import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/care_directory.dart';
import 'package:hercare/presentation/crisis/care_directory_screen.dart';
import 'package:hercare/presentation/crisis/crisis_links.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/care_directory_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CareDirectory bundledDirectory;
  setUpAll(() async {
    // Read once outside testWidgets' FakeAsync zones. A cached asset Future
    // created in a different zone must not be awaited through runAsync later.
    final raw = await rootBundle
        .loadString('assets/care_facilities.json', cache: false)
        .timeout(const Duration(seconds: 10));
    bundledDirectory = _parse(jsonDecode(raw));
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('actual bundled catalog has eight checked institutions in five cities',
      () {
    final directory = bundledDirectory;
    expect(directory.facilities.length, 8);
    expect(directory.facilities.map((entry) => entry.cityEn).toSet().length, 5);
    expect(
        directory.facilities.where((entry) => entry.hasCoordinates).length, 4);
    expect(
        directory.facilities
            .where((entry) => entry.coordinateKind == 'official_geo_point')
            .single
            .id,
        'aku_karachi');
    for (final facility in directory.facilities) {
      expect(CrisisLinks.phoneUri(facility.phone).scheme, 'tel');
      expect(facility.reviewIsDue(DateTime.utc(2026, 10, 12)), false);
      expect(facility.reviewIsDue(DateTime.utc(2027, 1, 11)), true);
      expect(facility.sourceUrls, isNotEmpty);
    }
  });

  test('bounded public catalog rejects clinical, source and phone claims', () {
    final directory = _parse(_catalog());
    expect(directory.facilities.length, 2);
    expect(directory.facilities.first.reviewIsDue(DateTime.utc(2026, 10, 12)),
        false);
    expect(directory.facilities.first.reviewIsDue(DateTime.utc(2027, 1, 12)),
        true);
    for (final changes in [
      {'clinical_approval': true},
      {'availability': 'open'},
      {
        'source_urls': ['https://pims.gov.pk.evil.test/contact']
      },
      {
        'source_urls': ['http://pims.gov.pk/contact']
      },
      {
        'source_urls': ['https://pims.gov.pk/contact?journal=private']
      },
      {
        'source_urls': ['https://name:password@pims.gov.pk/contact']
      },
      {'phone': '*123#'},
      {'phone': '1122;123'},
      {'latitude': 1, 'longitude': 2},
      {'checked_on': '2026-02-31'},
    ]) {
      final json = _catalog();
      (json['facilities'] as List).first.addAll(changes);
      expect(() => _parse(json), throwsFormatException);
    }
    final tooLarge = _catalog()..['facilities'] = List.filled(31, _facility());
    expect(() => _parse(tooLarge), throwsFormatException);
    final duplicate = _catalog()..['facilities'] = [_facility(), _facility()];
    expect(() => _parse(duplicate), throwsFormatException);
    expect(
        sourceUri('https://bipbs.gob.pk/?page_id=1906', careInstitutionHosts)
            .queryParameters,
        {'page_id': '1906'});
    expect(
        () => sourceUri('https://bipbs.gob.pk/?page_id=1906&next=evil',
            careInstitutionHosts),
        throwsFormatException);
  });

  test('only source-checked coordinates rank listed points; no fake distances',
      () {
    final json = _catalog(coordinates: true);
    final directory = _parse(json);
    final position = CarePosition(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 1000,
        recordedAt: DateTime.utc(2026, 10, 12));
    expect(
        directory.facilities.first.distanceKm(position), closeTo(111.19, .01));
    expect(directory.facilities.last.distanceKm(position), isNull);
    expect(directory.listed(position: position).first.id, 'test-hospital');
    expect(directory.listed(city: 'Karachi').single.id, 'other-hospital');
    final map = CareDirectoryLinks.mapUri(directory.facilities.first);
    expect(map.scheme, 'https');
    expect(map.host, 'www.google.com');
    expect(map.queryParameters.keys, ['api', 'query']);
    expect(map.queryParameters['query'], contains('Test Hospital'));
    expect(map.queryParameters['query'], isNot(contains('0.0')));
  });

  test('source reviews use complete UTC dates and flag future checks', () {
    final directory = _parse(_catalog());
    final facility = directory.facilities.first;
    expect(facility.reviewStatus(DateTime.utc(2026, 10, 11, 23, 59)),
        'date_unconfirmed');
    expect(
        directory.reviewStatus(DateTime.utc(2026, 10, 11)), 'date_unconfirmed');
    expect(facility.reviewIsDue(DateTime.utc(2027, 1, 10, 23, 59, 59, 999)),
        false);
    expect(
        directory.reviewStatus(DateTime.utc(2027, 1, 10, 23, 59)), 'current');
    expect(facility.reviewStatus(DateTime.utc(2027, 1, 11)), 'review_due');
    expect(facility.reviewStatus(DateTime.parse('2027-01-11T04:59:59+05:00')),
        'current');
    final sameDay = _catalog()..['review_due_on'] = '2026-10-12';
    for (final entry in sameDay['facilities']) {
      entry['review_due_on'] = '2026-10-12';
    }
    expect(_parse(sameDay).reviewStatus(DateTime.utc(2026, 10, 12, 23)),
        'current');
    expect(
        _parse(sameDay).reviewStatus(DateTime.utc(2026, 10, 13)), 'review_due');
  });

  test('public-only fields, review provenance and 180-day intervals are strict',
      () {
    final maxDue = DateTime.utc(2026, 10, 12)
        .add(const Duration(days: 180))
        .toIso8601String()
        .substring(0, 10);
    final overDue = DateTime.utc(2026, 10, 12)
        .add(const Duration(days: 181))
        .toIso8601String()
        .substring(0, 10);
    expect(_parse(_catalog()..['review_due_on'] = maxDue).facilities.length, 2);
    for (final key in ['journal', 'location', 'mother_id', 'conversation']) {
      expect(() => _parse(_catalog()..[key] = 'must not be cached'),
          throwsFormatException);
      final poisoned = _catalog();
      (poisoned['facilities'] as List).first[key] = 'must not be cached';
      expect(() => _parse(poisoned), throwsFormatException);
    }
    expect(() => _parse(_catalog()..['review_due_on'] = overDue),
        throwsFormatException);
    for (final changes in [
      {'review_due_on': overDue},
      {'checked_on': '2026-10-13'},
      {'review_status': 'verified'},
      {'review_status': 'current', 'stale': true},
      {'stale': 'false'},
    ]) {
      final json = _catalog();
      (json['facilities'] as List).first.addAll(changes);
      expect(() => _parse(json), throwsFormatException);
    }
    final missing = _catalog();
    (missing['facilities'] as List).first.remove('longitude');
    expect(() => _parse(missing), throwsFormatException);
    expect(() => _parse(_catalog()..['approved_domains'] = ['evil.test']),
        throwsFormatException);
    final runtime = _catalog()
      ..['review_status'] = 'date_unconfirmed'
      ..['stale'] = true;
    expect(_parse(runtime).reviewStatus(DateTime.utc(2026, 10, 12)),
        'date_unconfirmed');
  });

  test('native location accepts only finite, recent bounded approximate fixes',
      () {
    final now = DateTime.utc(2026, 10, 12);
    final native = {
      'latitude': 33.6,
      'longitude': 73.1,
      'accuracy': 1200,
      'recorded_at': now.millisecondsSinceEpoch,
    };
    expect(CarePosition.fromNative(native, now: now).accuracyMeters, 1200);
    for (final change in [
      {'latitude': double.nan},
      {'longitude': 181},
      {'accuracy': -1},
      {
        'recorded_at':
            now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch
      },
      {
        'recorded_at':
            now.add(const Duration(minutes: 3)).millisecondsSinceEpoch
      },
    ]) {
      expect(() => CarePosition.fromNative({...native, ...change}, now: now),
          throwsFormatException);
    }
  });

  test('public cache is bounded, expires and never requests auth or GPS',
      () async {
    var now = DateTime.utc(2026, 10, 12);
    final client = Dio(BaseOptions(baseUrl: 'https://hercare.test/api/v1'));
    var requests = 0;
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests++;
      expect(request.path, '/crisis/facilities');
      expect(request.queryParameters, isEmpty);
      expect(request.data, isNull);
      expect(request.headers.containsKey('Authorization'), false);
      handler.resolve(Response(
          requestOptions: request,
          data: utf8.encode(jsonEncode({'data': _catalog()})),
          statusCode: 200));
    }));
    final service = CareDirectoryService(
        client: client,
        loadAsset: () async => jsonEncode(_catalog()),
        now: () => now);
    expect((await service.offline()).downloaded, false);
    expect((await service.refresh()).downloaded, true);
    expect((await service.refresh()).downloaded, true);
    expect(requests, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().length, 1);
    expect(prefs.getString(prefs.getKeys().single),
        isNot(contains('recorded_at')));
    now = now.add(const Duration(days: 8));
    expect((await service.offline()).downloaded, false);
    expect(prefs.getKeys(), isEmpty);
  });

  test('missing native location support safely returns no location', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CareLocationService.channel, (call) async {
      throw PlatformException(code: 'PERMISSION_DENIED');
    });
    expect(await CareLocationService().current(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CareLocationService.channel, null);
  });

  test('poisoned downloads are rejected and old poisoned public caches removed',
      () async {
    var responseCatalog = _catalog();
    final client = Dio(BaseOptions(baseUrl: 'https://hercare.test/api/v1'));
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          data: utf8
              .encode(jsonEncode({'success': true, 'data': responseCatalog})),
          statusCode: 200));
    }));
    final service = CareDirectoryService(
        client: client, loadAsset: () async => jsonEncode(_catalog()));
    responseCatalog = _catalog()..['journal'] = 'private text';
    await expectLater(service.refresh(), throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    responseCatalog = _catalog();
    await service.refresh();
    final key = prefs.getKeys().single;
    final envelope = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    final poisoned = _catalog()..['location'] = {'latitude': 33.5};
    envelope['catalog'] = jsonEncode(poisoned);
    await prefs.setString(key, jsonEncode(envelope));
    expect((await service.offline()).downloaded, false);
    expect(prefs.getString(key), isNull);
    envelope['catalog'] = jsonEncode(_catalog());
    envelope['journal'] = 'private extra envelope field';
    await prefs.setString(key, jsonEncode(envelope));
    expect((await service.offline()).downloaded, false);
    expect(prefs.getString(key), isNull);
  });

  test('streamed catalog is bounded before parsing or cache persistence',
      () async {
    var canceled = false;
    final chunks = StreamController<Uint8List>(onCancel: () => canceled = true);
    final client = Dio(BaseOptions(baseUrl: 'https://hercare.test/api/v1'));
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          data: ResponseBody(chunks.stream, 200),
          statusCode: 200));
      chunks.add(Uint8List(CareDirectoryService.maxBytes));
      chunks.add(Uint8List(300));
    }));
    final service = CareDirectoryService(
        client: client, loadAsset: () async => jsonEncode(_catalog()));
    await expectLater(service.refresh(), throwsFormatException);
    await chunks.close();
    expect(canceled, true);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect((await service.offline()).directory.facilities.length, 2);
  });

  test('downloaded catalog cannot self-approve an unsafe source host',
      () async {
    final unsafe = _catalog()..['approved_domains'] = ['evil.test'];
    (unsafe['facilities'] as List).first['source_urls'] = [
      'https://evil.test/contact'
    ];
    final client = Dio(BaseOptions(baseUrl: 'https://hercare.test/api/v1'));
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          data: utf8.encode(jsonEncode({'data': unsafe})),
          statusCode: 200));
    }));
    final service = CareDirectoryService(
        client: client, loadAsset: () async => jsonEncode(_catalog()));
    await expectLater(service.refresh(), throwsFormatException);
    expect((await service.offline()).downloaded, false);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  for (final language in ['en', 'ur']) {
    testWidgets('actual institutional cards $language at 320px 200% fit',
        (tester) async {
      final directory = bundledDirectory;
      await _mount(tester, _FakeDirectoryService(directory),
          language: language);
      for (final facility in directory.listed()) {
        await _reveal(tester, find.byKey(ValueKey('care-map-${facility.id}')));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    for (final coordinates in [false, true]) {
      testWidgets(
          'directory $language GPS=$coordinates at 320px 200% is responsive',
          (tester) async {
        final service =
            _FakeDirectoryService(_parse(_catalog(coordinates: coordinates)));
        await _mount(tester, service, language: language);
        expect(find.byKey(const ValueKey('care-urgent')), findsOneWidget);
        await _reveal(tester, find.byKey(const ValueKey('care-choose-city')));
        await tester.tap(find.byKey(const ValueKey('care-choose-city')));
        await tester.pumpAndSettle();
        await _reveal(tester, find.byKey(const ValueKey('care-city-Lahore')));
        await tester.tap(find.byKey(const ValueKey('care-city-Lahore')));
        await tester.pumpAndSettle();
        await _reveal(
            tester, find.byKey(const ValueKey('care-map-test-hospital')));
        await _reveal(tester,
            find.text(language == 'ur' ? 'سرکاری ذرائع' : 'Official sources'));
        await tester.tap(
            find.text(language == 'ur' ? 'سرکاری ذرائع' : 'Official sources'));
        await tester.pumpAndSettle();
        await _reveal(
            tester, find.byKey(const ValueKey('care-source-test-hospital-0')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets(
      'external Maps needs confirmation; institution dialer remains usable',
      (tester) async {
    final service = _FakeDirectoryService(_parse(_catalog()));
    final links = _FakeLinks(), calls = _FakeCalls();
    await _mount(tester, service, links: links, calls: calls);
    await _reveal(tester, find.byKey(const ValueKey('care-map-test-hospital')));
    await tester.tap(find.byKey(const ValueKey('care-map-test-hospital')));
    await tester.pumpAndSettle();
    expect(links.mapsOpened, isEmpty);
    expect(find.textContaining('not your HerCare location'), findsOneWidget);
    await _reveal(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(links.mapsOpened, ['test-hospital']);
    await _reveal(
        tester, find.byKey(const ValueKey('care-call-test-hospital')));
    await tester.tap(find.byKey(const ValueKey('care-call-test-hospital')));
    await tester.pumpAndSettle();
    expect(calls.phones, ['+92519261234']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'GPS is opt-in, denial keeps city choice and publishes no distance',
      (tester) async {
    final service = _FakeDirectoryService(_parse(_catalog(coordinates: true)));
    final location = _FakeLocation();
    await _mount(tester, service, location: location);
    expect(location.requests, 0);
    await _reveal(tester, find.byKey(const ValueKey('care-locate')));
    await tester.tap(find.byKey(const ValueKey('care-locate')));
    await tester.pumpAndSettle();
    expect(location.requests, 0);
    await _reveal(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(location.requests, 1);
    expect(find.textContaining('Location unavailable.'), findsOneWidget);
    expect(find.byKey(const ValueKey('care-clear-location')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('urgent dialer does not wait for a usable directory',
      (tester) async {
    final service = _FakeDirectoryService(_parse(_catalog()))
      ..offlineFailed = true;
    final calls = _FakeCalls();
    await _mount(tester, service, calls: calls);
    await tester.tap(find.byKey(const ValueKey('care-urgent')));
    await tester.pumpAndSettle();
    expect(calls.emergencyOpens, 1);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location is cleared on background and a late fix is ignored',
      (tester) async {
    final pending = Completer<CarePosition?>();
    final location = _FakeLocation()..pending = pending.future;
    await _mount(
        tester, _FakeDirectoryService(_parse(_catalog(coordinates: true))),
        location: location);
    await _reveal(tester, find.byKey(const ValueKey('care-locate')));
    await tester.tap(find.byKey(const ValueKey('care-locate')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(location.requests, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pending.complete(_position());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(location.cancels, greaterThanOrEqualTo(1));
    expect(find.byKey(const ValueKey('care-clear-location')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission inactivity does not discard a fix; location expires',
      (tester) async {
    final pending = Completer<CarePosition?>();
    final location = _FakeLocation()..pending = pending.future;
    await _mount(
        tester, _FakeDirectoryService(_parse(_catalog(coordinates: true))),
        location: location);
    await _reveal(tester, find.byKey(const ValueKey('care-locate')));
    await tester.tap(find.byKey(const ValueKey('care-locate')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete(_position());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('care-clear-location')));
    expect(find.byKey(const ValueKey('care-clear-location')), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('care-clear-location')), findsNothing);
    expect(location.cancels, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });
}

CarePosition _position() => CarePosition(
    latitude: 0,
    longitude: 0,
    accuracyMeters: 1500,
    recordedAt: DateTime.now().toUtc());

Map<String, dynamic> _facility({bool coordinates = false}) => {
      'id': 'test-hospital',
      'name': 'Test Hospital Department of Mental Health',
      'name_ur': 'نمونہ ہسپتال شعبہ ذہنی صحت',
      'region': 'punjab',
      'city': 'Lahore',
      'city_ur': 'لاہور',
      'address': 'Main Road, Lahore, Pakistan',
      'address_ur': 'مرکزی سڑک، لاہور، پاکستان',
      'phone': '+92519261234',
      'service':
          'Mental-health outpatient department. Call to confirm care and fees.',
      'service_ur': 'ذہنی صحت کا شعبہ۔ سہولت اور فیس کی تصدیق کے لیے کال کریں۔',
      'source_urls': ['https://pims.gov.pk/contact'],
      'checked_on': '2026-10-12',
      'review_due_on': '2027-01-10',
      'verification_status': 'official_source_checked',
      'clinical_approval': false,
      'availability': 'unknown',
      'latitude': null,
      'longitude': null,
      'coordinates_source_url': null,
      'coordinate_kind': null,
      if (coordinates) ...{
        'latitude': 0,
        'longitude': 1,
        'coordinates_source_url': 'https://pims.gov.pk/map',
        'coordinate_kind': 'official_map_view_center',
      },
    };

Map<String, dynamic> _catalog({bool coordinates = false}) => {
      'version': 'm10-test',
      'checked_on': '2026-10-12',
      'review_due_on': '2027-01-10',
      'notice':
          'This is an incomplete institutional directory, not a doctor ranking. Phone before travelling.',
      'notice_ur':
          'یہ اداروں کی نامکمل فہرست ہے، ڈاکٹر کی درجہ بندی نہیں۔ سفر سے پہلے فون کریں۔',
      'approved_domains': ['pims.gov.pk'],
      'facilities': [
        _facility(coordinates: coordinates),
        {
          ..._facility(),
          'id': 'other-hospital',
          'city': 'Karachi',
          'city_ur': 'کراچی'
        },
      ],
    };

CareDirectory _parse(Map<String, dynamic> value) =>
    CareDirectory.fromJson(value, approvedHosts: careInstitutionHosts);

Future<void> _mount(WidgetTester tester, _FakeDirectoryService service,
    {String language = 'en',
    _FakeLinks? links,
    _FakeCalls? calls,
    _FakeLocation? location}) async {
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final provider = LanguageProvider();
  await provider.setLocale(Locale(language));
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: CareDirectoryScreen(
              service: service,
              links: links ?? _FakeLinks(),
              calls: calls ?? _FakeCalls(),
              location: location ?? _FakeLocation()))));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 220,
        maxScrolls: 70,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

class _FakeDirectoryService extends CareDirectoryService {
  _FakeDirectoryService(this.directory);
  final CareDirectory directory;
  bool offlineFailed = false;
  @override
  Future<CareDirectorySnapshot> offline() async {
    if (offlineFailed) throw Exception('Asset missing');
    return CareDirectorySnapshot(directory);
  }

  @override
  Future<CareDirectorySnapshot> refresh() async => throw Exception('Offline');
}

class _FakeLinks extends CareDirectoryLinks {
  final mapsOpened = <String>[];
  @override
  Future<bool> maps(CareFacility facility) async {
    mapsOpened.add(facility.id);
    return true;
  }

  @override
  Future<bool> source(Uri uri) async => true;
}

class _FakeCalls extends CrisisLinks {
  final phones = <String>[];
  var emergencyOpens = 0;
  @override
  Future<bool> call(String phone) async {
    CrisisLinks.phoneUri(phone);
    phones.add(phone);
    return true;
  }

  @override
  Future<bool> openDialer() async {
    emergencyOpens++;
    return true;
  }
}

class _FakeLocation extends CareLocationService {
  var requests = 0;
  var cancels = 0;
  Future<CarePosition?>? pending;
  @override
  Future<CarePosition?> current() async {
    requests++;
    return pending;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}
