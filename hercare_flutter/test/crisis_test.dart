import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/crisis_models.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/data/services/local_storage_service.dart';
import 'package:hercare/presentation/crisis/crisis_grounding.dart';
import 'package:hercare/presentation/crisis/crisis_links.dart';
import 'package:hercare/presentation/crisis/crisis_plan_cache.dart';
import 'package:hercare/presentation/crisis/crisis_support_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/services/crisis_service.dart';
import 'package:hercare/services/care_directory_service.dart';
import 'package:hercare/data/models/care_directory.dart';
import 'package:hercare/presentation/crisis/care_directory_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('strict bounded parsing, source catalog and safe launch URLs', () async {
    final catalog = CrisisCatalog.fromJson(
        jsonDecode(await rootBundle.loadString('assets/crisis_contacts.json')));
    expect(catalog.regions.first.emergencyNumber, isNull);
    expect(catalog.regions.first.id, 'unspecified');
    expect(catalog.contacts.length, 3);
    expect(() => CrisisPlan.fromJson({'version': '1'}), throwsFormatException);
    expect(() => CrisisPlan.fromJson({'coping_step': 'x' * 501}),
        throwsFormatException);
    expect(CrisisLinks.phoneUri('+92 (304) 111-1741').toString(),
        'tel:+923041111741');
    for (final unsafe in [
      '*123#',
      '1122;123',
      'https://evil.test',
      '1122?body=private',
      '1122\n;1'
    ]) {
      expect(() => CrisisLinks.phoneUri(unsafe), throwsFormatException);
    }
    final map = CrisisLinks.mapUri();
    expect(map.scheme, 'https');
    expect(map.host, 'www.google.com');
    expect(map.queryParameters,
        {'api': '1', 'query': 'nearest emergency department'});
    expect(
        CrisisService.requestId(),
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('encrypted plan download is owner-scoped, bounded and expires',
      () async {
    var now = DateTime.utc(2026, 10, 11);
    final cache = CrisisPlanCache(now: () => now);
    await cache.save('mother-a', _plan);
    expect((await cache.read('mother-a'))!.plan.copingStep, _plan.copingStep);
    expect(await cache.read('mother-b'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    now = now.add(const Duration(days: 31));
    expect(await cache.read('mother-a'), isNull);
    expect(
        await const FlutterSecureStorage()
            .read(key: 'm10_private_plan_v1_mother-a'),
        isNull);
    expect(() => cache.read('../other-account'), throwsFormatException);
  });

  test('logout clears offline plans without clearing language preference',
      () async {
    final cache = CrisisPlanCache();
    await cache.save('mother-a', _plan);
    final storage = LocalStorageService();
    await storage.setString('app_language', 'ur');
    await storage.clearUserSession();
    expect(await cache.read('mother-a'), isNull);
    expect(await storage.getString('app_language'), 'ur');
  });

  for (final language in ['en', 'ur']) {
    testWidgets(
        'signed-out immediate help at 320px 200% $language requires no input form',
        (tester) async {
      final service = _FakeService()..unavailable = true;
      final links = _FakeLinks();
      await _mount(tester, service, links, language: language);
      expect(service.supportReads, 0);
      expect(
          find.byKey(const ValueKey('crisis-emergency-call')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crisis-emergency-call')));
      await tester.pumpAndSettle();
      expect(
          find.text(language == 'ur'
              ? 'اس وقت آپ کس علاقے میں ہیں؟'
              : 'Where are you right now?'),
          findsOneWidget);
      await _reveal(tester, find.text(language == 'ur' ? 'پنجاب' : 'Punjab'));
      await tester.tap(find.text(language == 'ur' ? 'پنجاب' : 'Punjab'));
      await tester.pumpAndSettle();
      expect(links.phones, ['1122']);
      expect(service.requests, isEmpty);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('external maps require explicit approval and use no app location',
      (tester) async {
    final service = _FakeService(), links = _FakeLinks();
    await _mount(tester, service, links);
    await _reveal(tester, find.byKey(const ValueKey('crisis-map-emergency')));
    await tester.tap(find.byKey(const ValueKey('crisis-map-emergency')));
    await tester.pumpAndSettle();
    expect(links.maps, isEmpty);
    expect(
        find.textContaining(
            'This action does not request location in HerCare.'),
        findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(links.maps, [false]);
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guardian role gets generic support, never a mother private plan',
      (tester) async {
    final service = _FakeService(), links = _FakeLinks();
    await _mount(tester, service, links, account: 'guardian-a', guardian: true);
    expect(service.supportReads, 0);
    expect(find.byKey(const ValueKey('crisis-trusted-call')), findsNothing);
    await _reveal(tester, find.text('Helping someone safely'));
    expect(find.byKey(const ValueKey('crisis-edit-plan')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source-checked directory opens without login and urgent help returns',
      (tester) async {
    final raw = await tester
        .runAsync(() => rootBundle.loadString('assets/care_facilities.json'));
    final catalog = CareDirectory.fromJson(jsonDecode(raw!),
        approvedHosts: careInstitutionHosts);
    final service = _FakeService()..unavailable = true;
    await _mount(tester, service, _FakeLinks(),
        careDirectory: _FakeCareDirectory(catalog));
    await _reveal(tester, find.byKey(const ValueKey('crisis-care-directory')));
    await tester.tap(find.byKey(const ValueKey('crisis-care-directory')));
    await tester.pumpAndSettle();
    expect(find.byType(CareDirectoryScreen), findsOneWidget);
    expect(service.supportReads, 0);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.byKey(const ValueKey('care-urgent')));
    await tester.pumpAndSettle();
    expect(find.byType(CareDirectoryScreen), findsNothing);
    expect(find.byKey(const ValueKey('crisis-emergency-call')), findsOneWidget);
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'offline downloaded personal contact works with no guardian notification queue',
      (tester) async {
    final service = _FakeService()..unavailable = true;
    final links = _FakeLinks(), cache = _FakeCache()..plans['mother-a'] = _plan;
    await _mount(tester, service, links, account: 'mother-a', cache: cache);
    await _reveal(tester, find.byKey(const ValueKey('crisis-trusted-call')));
    await tester.tap(find.byKey(const ValueKey('crisis-trusted-call')));
    await tester.pumpAndSettle();
    expect(links.phones, [_plan.supportPhone]);
    await _reveal(tester, find.byKey(const ValueKey('crisis-request-help')));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('crisis-request-help')))
            .onPressed,
        isNull);
    expect(service.requests, isEmpty);
    expect(find.byKey(const ValueKey('crisis-safe-guardian')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'guardian urgent permission needs explicit confirmation and defaults off',
      (tester) async {
    final service = _FakeService(), links = _FakeLinks();
    await _mount(tester, service, links, account: 'mother-a');
    await _reveal(tester, find.byKey(const ValueKey('crisis-safe-guardian')));
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('crisis-safe-guardian')))
            .value,
        false);
    await tester.tap(find.byKey(const ValueKey('crisis-safe-guardian')));
    await tester.pumpAndSettle();
    expect(service.permissionChanges, isEmpty);
    expect(find.textContaining('future urgent safety alerts'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(service.permissionChanges, [true]);
    await _reveal(tester, find.byKey(const ValueKey('crisis-safe-guardian')));
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('crisis-safe-guardian')))
            .value,
        true);
    await tester.tap(find.byKey(const ValueKey('crisis-safe-guardian')));
    await tester.pumpAndSettle();
    expect(service.permissionChanges, [true, false]);
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uncertain request never retries automatically and manual retry keeps UUID',
      (tester) async {
    final service = _FakeService()..failFirstRequest = true;
    await _mount(tester, service, _FakeLinks(), account: 'mother-a');
    await _reveal(tester, find.byKey(const ValueKey('crisis-request-help')));
    await tester.tap(find.byKey(const ValueKey('crisis-request-help')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(service.requests.length, 1);
    expect(service.notifyValues, [false]);
    await tester.pump(const Duration(seconds: 20));
    expect(service.requests.length, 1);
    await _reveal(tester, find.text('Retry the same request'));
    await tester.tap(find.text('Retry the same request'));
    await tester.pumpAndSettle();
    expect(service.requests.length, 2);
    expect(service.requests.first, service.requests.last);
    expect(service.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opening a call does not resolve an event; closure requires explicit outcome',
      (tester) async {
    final service = _FakeService()..hasOpenEvent = true;
    final links = _FakeLinks();
    await _mount(tester, service, links, account: 'mother-a');
    await tester.tap(find.byKey(const ValueKey('crisis-trusted-call')));
    await tester.pumpAndSettle();
    expect(service.updates, isEmpty);
    await _reveal(tester, find.text('Close this record'));
    await tester.tap(find.text('Close this record'));
    await tester.pumpAndSettle();
    expect(service.updates, isEmpty);
    await _reveal(tester, find.text('I contacted a trusted person'));
    await tester.tap(find.text('I contacted a trusted person'));
    await tester.pumpAndSettle();
    expect(service.updates, ['resolved:support_contacted']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only three optional plan fields, guardian not automatically chosen',
      (tester) async {
    final service = _FakeService()..plan = const CrisisPlan(version: 3);
    await _mount(tester, service, _FakeLinks(), account: 'mother-a');
    await _reveal(tester, find.byKey(const ValueKey('crisis-edit-plan')));
    await tester.tap(find.byKey(const ValueKey('crisis-edit-plan')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('crisis-plan-phone')));
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('crisis-plan-phone')))
            .controller!
            .text,
        '');
    await _reveal(tester, find.byKey(const ValueKey('crisis-plan-save')));
    await tester.tap(find.byKey(const ValueKey('crisis-plan-save')));
    await tester.pumpAndSettle();
    expect(service.savedPlans.single.version, 3);
    expect(service.savedPlans.single.isEmpty, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download requires consent and removal deletes only account copy',
      (tester) async {
    final cache = _FakeCache();
    await _mount(tester, _FakeService(), _FakeLinks(),
        account: 'mother-a', cache: cache);
    await _reveal(tester, find.byKey(const ValueKey('crisis-download-plan')));
    await tester.tap(find.byKey(const ValueKey('crisis-download-plan')));
    await tester.pumpAndSettle();
    expect(cache.plans, isEmpty);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(cache.plans.keys, ['mother-a']);
    await _reveal(tester, find.byKey(const ValueKey('crisis-download-plan')));
    await tester.tap(find.byKey(const ValueKey('crisis-download-plan')));
    await tester.pumpAndSettle();
    expect(cache.plans, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account changes clear private state and unauthorized access clears download',
      (tester) async {
    final cache = _FakeCache()..plans['mother-a'] = _plan;
    final service = _FakeService();
    await _mount(tester, service, _FakeLinks(),
        account: 'mother-a', cache: cache);
    expect(find.byKey(const ValueKey('crisis-trusted-call')), findsOneWidget);
    service.denied = true;
    await _mount(tester, service, _FakeLinks(),
        account: 'mother-b', cache: cache);
    expect(find.byKey(const ValueKey('crisis-trusted-call')), findsNothing);
    expect(cache.cleared, contains('mother-b'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'grounding is opt-in, respects reduced motion and never infers safety',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true, accessibleNavigation: true),
      child: Scaffold(body: CrisisGrounding(isUrdu: false)),
    )));
    expect(find.textContaining('Notice 3 things'), findsNothing);
    await tester.tap(find.text('Optional grounding'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Notice 3 things'), findsOneWidget);
    await tester.tap(find.text('Stop grounding'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'private editor disappears immediately when authenticated account changes',
      (tester) async {
    final auth = _FakeAuth('mother-a');
    await _mount(tester, _FakeService(), _FakeLinks(),
        account: 'mother-a', auth: auth);
    await _reveal(tester, find.byKey(const ValueKey('crisis-edit-plan')));
    await tester.tap(find.byKey(const ValueKey('crisis-edit-plan')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const ValueKey('crisis-plan-coping')));
    expect(find.byKey(const ValueKey('crisis-plan-coping')), findsOneWidget);
    auth.changeAccount('mother-b');
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byKey(const ValueKey('crisis-emergency-call')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'logout with guardian confirmation open removes private identity and makes no write',
      (tester) async {
    final auth = _FakeAuth('mother-a');
    final service = _FakeService();
    await _mount(tester, service, _FakeLinks(),
        account: 'mother-a', auth: auth);
    await _reveal(tester, find.byKey(const ValueKey('crisis-safe-guardian')));
    await tester.tap(find.byKey(const ValueKey('crisis-safe-guardian')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only confirm if contacting Linked guardian'),
        findsOneWidget);
    auth.changeAccount(null);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Only confirm if contacting Linked guardian'),
        findsNothing);
    expect(service.permissionChanges, isEmpty);
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

const _plan = CrisisPlan(
    version: 1,
    copingStep: 'Sit with someone safe.',
    supportPersonName: 'My sister',
    supportPhone: '+923001234567');

Future<void> _mount(WidgetTester tester, _FakeService service, _FakeLinks links,
    {String? account,
    String language = 'en',
    bool guardian = false,
    _FakeCache? cache,
    CareDirectoryService? careDirectory,
    _FakeAuth? auth}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final identity = auth ?? _FakeAuth(account, guardian: guardian);
  addTearDown(identity.dispose);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: identity),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Directionality(
                textDirection:
                    language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
                child: child!)),
        home: CrisisSupportScreen(
            key: ValueKey(account),
            accountId: account,
            isGuardian: guardian,
            service: service,
            careDirectory: careDirectory,
            cache: cache ?? _FakeCache(),
            links: links),
      )));
  await tester.pumpAndSettle();
}

class _FakeAuth extends AuthProvider {
  _FakeAuth(this.accountId, {this.guardian = false});
  String? accountId;
  final bool guardian;
  @override
  UserModel? get user => accountId == null
      ? null
      : UserModel(
          id: accountId!,
          phone: '+923001234567',
          role: guardian ? 'guardian' : 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026, 10, 11));
  void changeAccount(String? id) {
    accountId = id;
    notifyListeners();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // A call feedback snackbar must expire before dragging the underlying list.
  await tester.pump(const Duration(seconds: 7));
  await tester.pumpAndSettle();
  final list = find.byType(ListView).last;
  final scrollable =
      find.descendant(of: list, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(finder, 180,
      scrollable: scrollable, maxScrolls: 40);
  await tester.pumpAndSettle();
}

class _FakeCareDirectory extends CareDirectoryService {
  _FakeCareDirectory(this.catalog);
  final CareDirectory catalog;
  @override
  Future<CareDirectorySnapshot> offline() async =>
      CareDirectorySnapshot(catalog);
  @override
  Future<CareDirectorySnapshot> refresh() async => throw Exception('Offline');
}

class _FakeLinks extends CrisisLinks {
  final phones = <String>[];
  final maps = <bool>[];
  @override
  Future<bool> call(String phone) async {
    phones.add(phone);
    return true;
  }

  @override
  Future<bool> openDialer() async => true;
  @override
  Future<bool> map({bool mentalHealth = false}) async {
    maps.add(mentalHealth);
    return true;
  }
}

class _FakeCache extends CrisisPlanCache {
  final plans = <String, CrisisPlan>{};
  final cleared = <String>[];
  @override
  bool get available => true;
  @override
  Future<CachedCrisisPlan?> read(String id) async => plans[id] == null
      ? null
      : CachedCrisisPlan(plan: plans[id]!, savedAt: DateTime.now());
  @override
  Future<void> save(String id, CrisisPlan plan) async {
    plans[id] = plan;
  }

  @override
  Future<void> clear(String id) async {
    plans.remove(id);
    cleared.add(id);
  }
}

class _FakeService extends CrisisService {
  bool unavailable = false,
      denied = false,
      failFirstRequest = false,
      hasOpenEvent = false;
  int supportReads = 0;
  CrisisPlan plan = _plan;
  CrisisGuardian guardian = const CrisisGuardian(
      linkId: 'safe-link', name: 'Linked guardian', phone: '+923111234567');
  final requests = <String>[], updates = <String>[];
  final notifyValues = <bool>[], permissionChanges = <bool>[];
  final savedPlans = <CrisisPlan>[];
  CrisisEvent event({String status = 'triggered'}) => CrisisEvent(
      id: 'event-id',
      sourceType: 'manual',
      status: status,
      triggeredAt: DateTime.utc(2026, 10, 11));
  @override
  Future<CrisisCatalog> contacts() async =>
      throw Exception('offline public API');
  @override
  Future<CrisisSupport> support() async {
    supportReads++;
    if (denied) throw const CrisisAccessException();
    if (unavailable) throw Exception('offline');
    return CrisisSupport(
        plan: plan,
        guardian: guardian,
        openEvent: hasOpenEvent ? event() : null);
  }

  @override
  Future<CrisisGuardian?> guardianSafety(String id, bool confirmed) async {
    permissionChanges.add(confirmed);
    guardian = CrisisGuardian(
        linkId: id,
        name: guardian.name,
        phone: guardian.phone,
        safeToContactConfirmed: confirmed);
    return guardian;
  }

  @override
  Future<CrisisEvent> requestHelp(
      {required String requestId,
      required bool notifyGuardian,
      String? guardianLinkId}) async {
    requests.add(requestId);
    notifyValues.add(notifyGuardian);
    if (failFirstRequest && requests.length == 1) throw Exception('timeout');
    return event();
  }

  @override
  Future<CrisisEvent> updateEvent(String id,
      {required String status, String? outcome}) async {
    updates.add('$status:${outcome ?? ''}');
    return event(status: status);
  }

  @override
  Future<CrisisPlan> savePlan(CrisisPlan value) async {
    savedPlans.add(value);
    plan = value;
    return plan;
  }

  @override
  Future<CrisisHistory> history({String? before}) async =>
      const CrisisHistory();
}
