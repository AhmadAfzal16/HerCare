import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/community_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/community/community_composer.dart';
import 'package:hercare/presentation/community/community_members.dart';
import 'package:hercare/presentation/community/community_screen.dart';
import 'package:hercare/presentation/community/community_widgets.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/community_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community_test.dart' show FakeCommunity, postData;

class _Auth extends AuthProvider {
  String? id = 'mother-a';
  String role = 'mother';
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
  void change(String? value, {String role = 'mother'}) {
    id = value;
    this.role = role;
    notifyListeners();
  }
}

class _Service extends FakeCommunity {
  Completer<CommunityPage>? pending;
  int feedCalls = 0, submitCalls = 0;
  bool denied = false, deleted = false, suspended = true, cancelled = false;
  bool uncertain = false, includeReplies = false;
  String? blocked;
  final submissions = <Map<String, dynamic>>[];
  final schedules = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> status() async {
    if (denied) {
      throw const CommunityException('Access removed', statusCode: 403);
    }
    return super.status();
  }

  @override
  Future<CommunityPage> feed(
      {String? topic,
      String? cursor,
      bool mine = false,
      bool includeReplies = false,
      String? sessionId}) async {
    feedCalls++;
    this.includeReplies = includeReplies;
    return pending == null
        ? CommunityPage({
            'items': [postData],
            'next_cursor': null
          })
        : await pending!.future;
  }

  @override
  Future<CommunityPost> detail(String id) async {
    if (deleted || blocked != null) {
      throw const CommunityException('Discussion unavailable', statusCode: 404);
    }
    return CommunityPost({...postData, 'is_mine': true});
  }

  @override
  Future<void> remove(String id) async {
    deleted = true;
  }

  @override
  Future<void> block(String id, {bool active = true}) async {
    blocked = active ? id : null;
  }

  @override
  Future<List<Map<String, dynamic>>> blocks() async => [
        if (blocked != null) {'id': blocked, 'alias': 'Kind Willow'}
      ];
  @override
  Future<Map<String, dynamic>> submit(Map<String, dynamic> data) async {
    submitCalls++;
    submissions.add(Map<String, dynamic>.from(data));
    if (uncertain && submitCalls == 1) {
      throw const CommunityException('Timeout');
    }
    return {'safety_support': false};
  }

  @override
  Future<Map<String, dynamic>> members({String? cursor}) async => {
        'items': [
          {
            'id': 'member',
            'alias': 'Kind Willow 0123456789',
            'suspended': suspended,
            'joined_at': '2026-09-26T12:00:00Z'
          }
        ],
        'next_cursor': null
      };
  @override
  Future<void> suspend(String id, bool suspended, String reason) async {
    this.suspended = suspended;
  }

  @override
  Future<List<Map<String, dynamic>>> sessions() async => [
        {
          'id': 'session',
          'title': 'Supportive questions for the circle',
          'description':
              'Discuss recovery support with a verified professional.',
          'expert_name': 'Test professional',
          'credentials': 'Credentials verified by operator',
          'starts_at': DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
          'ends_at': DateTime.now()
              .add(const Duration(hours: 3))
              .toUtc()
              .toIso8601String(),
          'cancelled': cancelled
        }
      ];
  @override
  Future<void> cancelSession(String id) async {
    cancelled = true;
  }

  @override
  Future<void> schedule(Map<String, dynamic> data) async {
    schedules.add(Map<String, dynamic>.from(data));
    if (uncertain && schedules.length == 1) {
      throw const CommunityException('Timeout');
    }
  }
}

Widget _app(Widget home,
        {_Auth? auth, double scale = 1, bool keyboard = false}) =>
    MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          if (auth != null)
            ChangeNotifierProvider<AuthProvider>.value(value: auth)
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
            home: home));

Finder _activeScroll() => find
    .descendant(
        of: find.byType(CommunityDialog).evaluate().isNotEmpty
            ? find.byType(CommunityDialog).last
            : find.byType(ListView).last,
        matching: find.byType(Scrollable))
    .first;

Future<void> _show(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 30 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(_activeScroll(), const Offset(0, -100));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'service pins account, does not follow redirects, includes owned replies',
      () async {
    late RequestOptions request;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      request = options;
      handler.resolve(Response(requestOptions: options, data: {
        'success': true,
        'data': {'items': [], 'next_cursor': null}
      }));
    }));
    await CommunityService(client: dio, accountId: 'mother-a')
        .feed(mine: true, includeReplies: true, cursor: 'opaque');
    expect(request.headers['X-Community-Account-Id'], 'mother-a');
    expect(request.followRedirects, false);
    expect(request.queryParameters,
        {'mine': 'true', 'include_replies': 'true', 'cursor': 'opaque'});
    dio.close();
  });

  test('typed service failures distinguish access loss and uncertain delivery',
      () async {
    for (final status in [401, 403, 404, 409, 422, 429, 503]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
                requestOptions: options,
                statusCode: status,
                data: {'message': 'Private debug body'})));
      }));
      try {
        await CommunityService(client: dio).status();
        fail('Expected failure');
      } on CommunityException catch (error) {
        expect(error.statusCode, status);
        expect(error.accessDenied, status == 401 || status == 403);
        expect(error.deliveryUncertain, status >= 500);
        if (status >= 500) {
          expect(error.toString(), isNot(contains('Private debug body')));
        }
      }
      dio.close();
    }
  });

  test('invalid response is not accepted as a committed submission', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler
          .resolve(Response(requestOptions: options, data: {'success': false}));
    }));
    await expectLater(
        CommunityService(client: dio).submit({'body': 'words'}),
        throwsA(isA<CommunityException>()
            .having((e) => e.invalidResponse, 'invalid response', true)));
    dio.close();
  });

  testWidgets('late previous-account response cannot repopulate the community',
      (tester) async {
    final auth = _Auth();
    final service = _Service()..pending = Completer<CommunityPage>();
    await tester
        .pumpWidget(_app(CommunityScreen(service: service), auth: auth));
    await tester.pump();
    expect(service.feedCalls, 1);
    auth.change('mother-b');
    await tester.pump();
    service.pending!.complete(CommunityPage({
      'items': [postData],
      'next_cursor': null
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text(postData['body'] as String), findsNothing);
    auth.change('mother-a');
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(service.feedCalls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['switch', 'logout', 'guardian']) {
    testWidgets('composer draft is disposed after $change', (tester) async {
      final auth = _Auth();
      final service = _Service();
      await tester.pumpWidget(
          _app(CommunityComposer(service: service, urdu: false), auth: auth));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField).first, 'Private mother title');
      await tester.enterText(
          find.byType(TextField).last, 'Private mother draft');
      auth.change(change == 'logout' ? null : 'other',
          role: change == 'guardian' ? 'guardian' : 'mother');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Private mother'), findsNothing);
      expect(service.submitCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('access denial removes previously loaded private/community text',
      (tester) async {
    final service = _Service();
    await tester
        .pumpWidget(_app(CommunityScreen(service: service, moderation: true)));
    await tester.pumpAndSettle();
    expect(find.text(postData['body'] as String), findsOneWidget);
    service.denied = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Access removed'), findsOneWidget);
    expect(find.text(postData['body'] as String), findsNothing);
  });

  testWidgets('thread deletion removes retained parent and reply controls',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(
        _app(CommunityScreen(service: service, parentId: 'thread')));
    await tester.pumpAndSettle();
    final menu = find.descendant(
        of: find.byType(CommunityPostCard).first,
        matching: find.byType(PopupMenuButton<String>));
    await _show(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.deleted, true);
    expect(find.text(postData['body'] as String), findsNothing);
    expect(find.text('Write a reply'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My posts requests owned replies and closed Q&A is read-only',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(_app(CommunityScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My posts'));
    await tester.pumpAndSettle();
    expect(service.includeReplies, true);
    await tester.pumpWidget(_app(CommunityScreen(
        service: service, sessionId: 'session', sessionClosed: true)));
    await tester.pumpAndSettle();
    expect(find.text('Share an experience'), findsNothing);
    expect(find.textContaining('This Q&A is closed.'), findsOneWidget);
  });

  testWidgets('ambiguous post retry preserves UUID and locks draft editing',
      (tester) async {
    final service = _Service()..uncertain = true;
    await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            CommunityComposer(service: service, urdu: false))),
                child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'A hopeful day');
    await tester.enterText(
        find.byType(TextField).last, 'A family member helped me today.');
    await _show(tester, find.text('Send for review'));
    await tester.tap(find.text('Send for review'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        true);
    await _show(tester, find.text('Retry this message'));
    await tester.tap(find.text('Retry this message'));
    await tester.pumpAndSettle();
    expect(service.submissions.length, 2);
    expect(service.submissions.first, service.submissions.last);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('moderator restores an alias without a pending queue item',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(_app(CommunityMembers(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore member'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Reviewed and resolved');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.suspended, false);
    expect(find.text('Active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account change disposes an open moderator dialog and prevents its write',
      (tester) async {
    final auth = _Auth()..role = 'admin';
    final service = _Service();
    await tester
        .pumpWidget(_app(CommunityMembers(service: service), auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore member'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Private review reason');
    await tester.pumpAndSettle();
    auth.change('another-admin', role: 'admin');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Private review reason'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
    expect(service.suspended, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'moderator cancels Q&A while approved discussions remain readable',
      (tester) async {
    final service = _Service();
    await tester
        .pumpWidget(_app(CommunitySessions(service: service, admin: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel session').last);
    await tester.pumpAndSettle();
    expect(service.cancelled, true);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Read discussion'), findsOneWidget);
  });

  testWidgets(
      'composer follows current app language rather than opening snapshot',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(_app(Builder(builder: (ctx) {
      context = ctx;
      return CommunityComposer(service: _Service(), urdu: false);
    })));
    await tester.pumpAndSettle();
    await context.read<LanguageProvider>().toggleLocale();
    await tester.pumpAndSettle();
    expect(find.text('حلقے میں بات کریں'), findsOneWidget);
    expect(find.text('Share with the circle'), findsNothing);
  });

  testWidgets(
      'ambiguous Q&A scheduling retries exactly once with original UUID',
      (tester) async {
    final service = _Service()..uncertain = true;
    await tester
        .pumpWidget(_app(CommunitySessions(service: service, admin: true)));
    await tester.pumpAndSettle();
    await _show(tester, find.text('Schedule a session'));
    await tester.tap(find.text('Schedule a session'));
    await tester.pumpAndSettle();
    final texts = [
      'Supportive Q&A',
      'A moderated discussion about support.',
      'Test professional',
      'Verified credentials'
    ];
    for (var i = 0; i < texts.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), texts[i]);
    }
    await _show(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await _show(tester, find.text('Schedule'));
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(service.schedules.length, 1);
    expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((field) => field.enabled == false),
        true);
    await _show(tester, find.text('Retry scheduling'));
    await tester.tap(find.text('Retry scheduling'));
    await tester.pumpAndSettle();
    expect(service.schedules.length, 2);
    expect(service.schedules.first, service.schedules.last);
    expect(service.schedules.first['client_request_id'],
        matches(RegExp(r'^[a-f0-9]{8}-[a-f0-9-]{27}$')));
    expect(find.byType(CommunityDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ur']) {
    for (final mode in ['sessions', 'members', 'schedule', 'reason']) {
      testWidgets('$mode $language fits 320x480 at double text with keyboard',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _Service();
        await tester.pumpWidget(_app(
            mode == 'members' || mode == 'reason'
                ? CommunityMembers(service: service)
                : CommunitySessions(service: service, admin: true),
            scale: 2,
            keyboard: true));
        await tester.pumpAndSettle();
        if (mode == 'schedule') {
          final button = find
              .text(language == 'en' ? 'Schedule a session' : 'نشست طے کریں');
          await _show(tester, button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        if (mode == 'reason') {
          final button =
              find.text(language == 'en' ? 'Restore member' : 'رکن بحال کریں');
          await _show(tester, button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 6; i++) {
          await tester.drag(_activeScroll(), const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
