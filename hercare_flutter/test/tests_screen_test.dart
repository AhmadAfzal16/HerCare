import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hercare/data/models/screening_models.dart';
import 'package:hercare/presentation/epds/tests_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/push_destination.dart';
import 'package:hercare/services/screening_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in ['en', 'ur']) {
    for (final width in [280.0, 320.0, 600.0]) {
      testWidgets('Tests layout $language, width $width, large text',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(Size(width, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: TestsScreen(service: _ScheduleService()),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 9; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -350));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('PHQ-9 opens directly and refreshes after returning',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final service = _ScheduleService(phqDue: true);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => TestsScreen(service: service)),
      GoRoute(
          path: '/phq9',
          builder: (context, state) => Scaffold(
              body: TextButton(
                  onPressed: () => context.pop(),
                  child: Text(
                      'PHQ draft: ${state.uri.queryParameters['draft']}')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('start-phq9'));
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('PHQ draft: phq-draft'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Failed schedule offers retry, not a false up-to-date state',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final service = _ScheduleService()..fail = true;
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: MaterialApp(home: TestsScreen(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('You’re up to date'), findsNothing);
    service.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('EPDS'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-phq9')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Reminder destinations reject other accounts, roles and arbitrary links',
      () {
    const data = {
      'route': '/tests',
      'type': 'screening_reminder',
      'recipient_id': 'mother-1'
    };
    String? destination(Map<String, dynamic> payload,
            {String id = 'mother-1',
            String role = 'mother',
            bool onboarded = true}) =>
        pushDestination(payload,
            userId: id, role: role, onboardingComplete: onboarded);
    expect(destination(data), '/tests');
    expect(destination(data, id: 'mother-2'), isNull);
    expect(destination(data, role: 'guardian'), isNull);
    expect(destination(data, onboarded: false), isNull);
    expect(destination({...data, 'route': '/admin'}), isNull);
    expect(
        destination({'route': '/tests', 'type': 'screening_reminder'}), isNull);
    expect(
        destination({'route': '/notifications', 'type': 'guardian_alert'},
            role: 'guardian'),
        '/notifications');
  });
}

class _ScheduleService extends ScreeningService {
  _ScheduleService({this.phqDue = false});
  final bool phqDue;
  int calls = 0;
  bool fail = false;

  @override
  Future<List<ScheduledScreening>> getSchedule() async {
    calls++;
    if (fail) throw Exception('offline');
    return [
      ScheduledScreening(
          instrumentType: 'epds',
          intervalDays: 7,
          due: true,
          dueAt: DateTime.now().subtract(const Duration(days: 1))),
      ScheduledScreening(
          instrumentType: 'phq9',
          intervalDays: 14,
          due: phqDue,
          dueAt: DateTime.now().add(const Duration(days: 14)),
          draftId: phqDue ? 'phq-draft' : null),
    ];
  }
}
