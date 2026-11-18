import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/content/content_admin_screen.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/content_admin_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _itemId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, dynamic> _row({String status = 'draft', bool quran = false}) => {
      'id': _itemId,
      'version': 1,
      'status': status,
      'title_en': 'Optional reflection',
      'title_ur': 'اختیاری غور و فکر',
      'summary_en': 'Reviewed text is not a treatment guarantee.',
      'summary_ur': 'یہ مواد علاج کی ضمانت نہیں ہے۔',
      'body_en': 'English translation available for review.',
      'body_ur': 'اردو ترجمہ جائزے کے لیے دستیاب ہے۔',
      'category': quran ? 'quran' : 'psychoeducation',
      'format': quran ? 'audio' : 'article',
      'audience': 'both',
      'is_religious': quran,
      'is_music': false,
      'media_url': quran
          ? 'https://cdn.islamic.network/quran/audio/128/ar.alafasy/6095.mp3'
          : null,
      'source_url': 'https://alquran.cloud/terms-and-conditions',
      'source_name': 'Verified source name',
      'license_name': 'Educational use; rights retained',
      'attribution': 'Named author and translator. No endorsement claimed.',
      'arabic_text': quran ? 'فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا' : null,
      'transliteration': quran ? "Fa inna ma'al usri yusra" : null,
      'verse_reference': quran ? '94:5' : null,
      'activity_type': null,
      'activity_id': null,
      'tags': ['reflection'],
      'priority': 0,
      'duration_seconds': null,
      'review_after': null,
      'available_from': null,
      'available_until': null,
    };

class _Auth extends AuthProvider {
  String? id = _admin;
  String role = 'admin';
  @override
  bool get isAuthenticated => id != null;
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: role,
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026));
  void change(String? value, {String role = 'admin'}) {
    id = value;
    this.role = role;
    notifyListeners();
  }
}

class _AdminService extends ContentAdminService {
  _AdminService({List<Map<String, dynamic>>? initial})
      : rows = initial ?? [_row()],
        super(accountId: _admin, client: Dio());
  final List<Map<String, dynamic>> rows;
  final creates = <Map<String, dynamic>>[];
  final updates = <Map<String, dynamic>>[];
  final reviews = <Map<String, dynamic>>[];
  final publications = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pendingList, pendingCreate;
  bool denied = false, uncertainFirst = false;
  int listCalls = 0;
  @override
  Future<Map<String, dynamic>> list({String? status, int offset = 0}) async {
    listCalls++;
    if (denied) {
      throw const ContentAdminException('Administrator access is unavailable.',
          statusCode: 403);
    }
    if (pendingList != null) return pendingList!.future;
    return {
      'items': rows
          .where((row) => status == null || row['status'] == status)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      'next_offset': null
    };
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> item) async {
    creates.add(jsonDecode(jsonEncode(item)) as Map<String, dynamic>);
    if (pendingCreate != null) return pendingCreate!.future;
    if (uncertainFirst && creates.length == 1) {
      throw const ContentAdminException('The save was not confirmed.');
    }
    return {'id': _itemId, 'version': 1, 'status': 'draft'};
  }

  @override
  Future<Map<String, dynamic>> update(
      String id, Map<String, dynamic> item) async {
    updates.add(Map<String, dynamic>.from(item));
    return {...item, 'id': id, 'version': 2, 'status': 'draft'};
  }

  @override
  Future<Map<String, dynamic>> review(
      String id, Map<String, dynamic> decision) async {
    reviews.add(Map<String, dynamic>.from(decision));
    final row = rows.firstWhere((row) => row['id'] == id);
    row['version'] = (row['version'] as int) + 1;
    row['status'] = decision['decision'] == 'approved' ? 'reviewed' : 'draft';
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>> publication(
      String id, int version, bool published) async {
    publications.add({'id': id, 'version': version, 'published': published});
    final row = rows.firstWhere((row) => row['id'] == id);
    row['version'] = version + 1;
    row['status'] = published ? 'published' : 'draft';
    return Map<String, dynamic>.from(row);
  }
}

Widget _app(_AdminService service, _Auth auth,
        {double scale = 1, bool keyboard = false, bool pinned = false}) =>
    MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: keyboard
                        ? const EdgeInsets.only(bottom: 100)
                        : EdgeInsets.zero),
                child: Directionality(
                    textDirection: context.watch<LanguageProvider>().isUrdu
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: child!)),
            home: pinned
                ? ContentAdminGuard(
                    accountId: _admin,
                    child: ContentAdminScreen(service: service))
                : ContentAdminScreen(service: service)));

Future<void> _show(WidgetTester tester, Finder finder,
    {bool interactive = true}) async {
  Finder activeScroll() {
    final dialog = find.byType(Dialog);
    final parent =
        dialog.evaluate().isNotEmpty ? dialog.last : find.byType(ListView).last;
    return find.descendant(of: parent, matching: find.byType(Scrollable)).first;
  }

  if (finder.evaluate().isEmpty) {
    final state = tester.state<ScrollableState>(activeScroll());
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 120; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      if (!interactive || finder.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(activeScroll(), const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey('content-admin-$key'));
  await _show(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> _fillArticle(WidgetTester tester) async {
  for (final entry in {
    'title_en': 'Simple educational draft',
    'title_ur': 'سادہ تعلیمی مسودہ',
    'summary_en': 'An optional educational introduction.',
    'summary_ur': 'ایک اختیاری تعلیمی تعارف۔',
    'body_en': 'This is educational material, not a diagnosis.',
    'body_ur': 'یہ تعلیمی مواد ہے، تشخیص نہیں۔',
  }.entries) {
    await _fill(tester, entry.key, entry.value);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final ur in [false, true]) {
    testWidgets(
        'admin review is usable at 320x480, 200% text and keyboard (${ur ? 'Urdu' : 'English'})',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'app_language': ur ? 'ur' : 'en'});
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _AdminService(), auth = _Auth();
      await tester.pumpWidget(_app(service, auth, scale: 2, keyboard: true));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(ur ? 'جائزہ' : 'Review'));
      expect(tester.takeException(), isNull);
      await _show(
          tester, find.byKey(const ValueKey('content-review-qualification')));
      await tester.enterText(
          find.byKey(const ValueKey('content-review-qualification')),
          'Editorial reviewer');
      await _show(tester, find.byKey(const ValueKey('content-review-note')));
      await tester.enterText(find.byKey(const ValueKey('content-review-note')),
          'Checked rights, source and both languages; not a clinical validation claim.');
      await _tap(tester, find.byType(SwitchListTile));
      await _tap(tester, find.byKey(const ValueKey('content-review-save')));
      expect(service.reviews.single['decision'], 'approved');
      expect(service.reviews.single['version'], 1);
      expect(service.reviews.single['reviewer_qualification'],
          'Editorial reviewer');
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text(ur ? 'نیا مسودہ' : 'New draft'));
      await _show(tester, find.byKey(const ValueKey('content-draft-save')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'new drafts use stable exact retries and never fabricate approval',
      (tester) async {
    final service = _AdminService(initial: [])..uncertainFirst = true;
    final auth = _Auth();
    await tester.pumpWidget(_app(service, auth));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('New draft'));
    await _fillArticle(tester);
    await _tap(tester, find.byKey(const ValueKey('content-draft-save')));
    expect(service.creates, hasLength(1));
    expect(service.creates.single['status'], isNull);
    expect(service.creates.single['reviewed_by'], isNull);
    final lockedFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(lockedFields, isNotEmpty);
    expect(lockedFields.every((field) => field.enabled == false), true);
    await _tap(tester, find.byKey(const ValueKey('content-draft-save')));
    expect(service.creates, hasLength(2));
    expect(service.creates.first, service.creates.last);
    expect(find.text('Content draft'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a Quran audio reviewer can inspect the exact English and Urdu translations before approval',
      (tester) async {
    final service = _AdminService(initial: [_row(quran: true)]);
    await tester.pumpWidget(_app(service, _Auth()));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Read / edit draft'));
    await _show(tester, find.byKey(const ValueKey('content-admin-body_en')));
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('content-admin-body_en')))
            .controller!
            .text,
        'English translation available for review.');
    await _show(tester, find.byKey(const ValueKey('content-admin-body_ur')));
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('content-admin-body_ur')))
            .controller!
            .text,
        'اردو ترجمہ جائزے کے لیے دستیاب ہے۔');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'publication is a separate reviewed-version action and published items cannot be reviewed again',
      (tester) async {
    final service = _AdminService(initial: [_row(status: 'reviewed')]);
    await tester.pumpWidget(_app(service, _Auth()));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Reviewed'));
    await _tap(tester, find.text('Publish'));
    expect(service.publications.single,
        {'id': _itemId, 'version': 1, 'published': true});
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Published'));
    await _show(tester, find.text('Withdraw'));
    expect(find.text('Review'), findsNothing);
    expect(find.text('Read / edit draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'account/role changes remove an open review dialog and ignore an old list response',
      (tester) async {
    final auth = _Auth(), service = _AdminService();
    await tester.pumpWidget(_app(service, auth, pinned: true));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Review'));
    await tester.enterText(find.byKey(const ValueKey('content-review-note')),
        'Private operator draft note');
    auth.change(_other, role: 'mother');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-review-note')), findsNothing);
    expect(find.text('Save review'), findsNothing);
    expect(service.reviews, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    final secondAuth = _Auth(),
        second = _AdminService()
          ..pendingList = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_app(second, secondAuth, pinned: true));
    await tester.pump();
    secondAuth.change(_other);
    await tester.pump();
    second.pendingList!.complete({
      'items': [_row()],
      'next_offset': null
    });
    await tester.pumpAndSettle();
    expect(find.text('Optional reflection'), findsNothing);
    expect(
        find.textContaining('account or permissions changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'access revocation does not retain catalog rows or active create controls',
      (tester) async {
    final service = _AdminService()..denied = true;
    await tester.pumpWidget(_app(service, _Auth()));
    await tester.pumpAndSettle();
    expect(find.text('Optional reflection'), findsNothing);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'New draft'));
    expect(button.onPressed, isNull);
    expect(find.text('Administrator access is unavailable.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('archived content is restored only as an unpublished draft',
      (tester) async {
    final service = _AdminService(initial: [_row(status: 'archived')]);
    await tester.pumpWidget(_app(service, _Auth()));
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Archived'));
    await _tap(tester, find.text('Restore as draft'));
    expect(service.publications.single,
        {'id': _itemId, 'version': 1, 'published': false});
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Drafts'));
    await _show(tester, find.text('Review'));
    expect(find.text('Publish'), findsNothing);
    expect(service.rows.single['status'], 'draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'format changes clear incompatible links and in-app activities select the mother audience',
      (tester) async {
    final service = _AdminService(initial: [
      {
        ..._row(),
        'format': 'video',
        'category': 'soothing',
        'media_url': 'https://upload.wikimedia.org/example.webm'
      }
    ]);
    await tester.pumpWidget(_app(service, _Auth()));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Read / edit draft'));
    await _tap(tester, find.byKey(const ValueKey('content-admin-format')));
    await tester.tap(find.text('article').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('content-draft-save')));
    expect(service.updates.single['format'], 'article');
    expect(service.updates.single['media_url'], isNull);
    expect(service.updates.single['activity_id'], isNull);
    await _tap(tester, find.text('New draft'));
    await _tap(tester, find.byKey(const ValueKey('content-admin-format')));
    await tester.tap(find.text('activity').last);
    await tester.pumpAndSettle();
    final audience = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('content-admin-audience-activity')));
    expect(audience.initialValue, 'mother');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
      'admin service uses realistic list/receipt shapes, account headers, versioned actions and no redirects',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://hercare.example/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      final status = options.path.endsWith('/review')
          ? 'reviewed'
          : options.path.endsWith('/publication')
              ? 'published'
              : options.method == 'DELETE'
                  ? 'archived'
                  : 'draft';
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'success': true,
        'data': options.method == 'GET'
            ? {
                'items': [_row()],
                'next_offset': null
              }
            : {'id': _itemId, 'version': 2, 'status': status}
      }));
    }));
    final service = ContentAdminService(accountId: _admin, client: dio);
    expect((await service.list(status: 'draft'))['items'], hasLength(1));
    expect((await service.create({'client_request_id': _other}))['status'],
        'draft');
    await service.update(_itemId, {'version': 1});
    await service.review(_itemId, {'version': 1, 'decision': 'approved'});
    await service.publication(_itemId, 1, true);
    await service.archive(_itemId, 1);
    expect(
        requests.every((r) =>
            r.headers['X-Content-Account-Id'] == _admin && !r.followRedirects),
        true);
    expect(requests.first.queryParameters,
        {'status': 'draft', 'limit': 30, 'offset': 0});
    expect(requests.last.queryParameters, {'version': 1});
    await expectLater(
        service.update('../policy', {}), throwsA(isA<ContentAdminException>()));
    dio.close();
  });

  test(
      'malformed or mismatched mutation receipts are not falsely treated as a saved draft',
      () async {
    for (final data in [
      {},
      {'id': _itemId, 'version': 1, 'status': 'published'},
      {'id': _other, 'version': 2, 'status': 'draft'}
    ]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://hercare.example/api/v1'));
      dio.interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(
              requestOptions: o,
              data: {'success': true, 'data': data},
              statusCode: 200))));
      await expectLater(
          ContentAdminService(accountId: _admin, client: dio)
              .update(_itemId, {'version': 1}),
          throwsA(isA<ContentAdminException>()));
      dio.close();
    }
  });

  test(
      'unexpected response and server-error values remain private and origin changes reject stale responses',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://hercare.example/api/v1'));
    final ready = Completer<void>();
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      await ready.future;
      handler.resolve(Response(
          requestOptions: options,
          data: {
            'success': true,
            'data': {
              'items': [_row()]
            }
          },
          statusCode: 200));
    }));
    final service = ContentAdminService(accountId: _admin, client: dio);
    final pending = service.list();
    await Future<void>.delayed(Duration.zero);
    dio.options.baseUrl = 'https://other.example/api/v1';
    ready.complete();
    await expectLater(pending, throwsA(isA<ContentAdminException>()));
    dio.close();

    final broken = Dio(BaseOptions(baseUrl: 'https://hercare.example/api/v1'));
    broken.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) => h.reject(DioException(
            requestOptions: o,
            response: Response(
                requestOptions: o,
                statusCode: 403,
                data: {'message': 'Bearer private-token private text'})))));
    await expectLater(
        ContentAdminService(accountId: _admin, client: broken).list(),
        throwsA(isA<ContentAdminException>()
            .having((e) => e.accessDenied, 'denied', true)
            .having((e) => e.message.contains('private-token'),
                'no private response text', false)));
    broken.close();
  });
}
