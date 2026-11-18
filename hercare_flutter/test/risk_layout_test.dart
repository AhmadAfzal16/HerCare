import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hercare/data/models/risk_models.dart';
import 'package:hercare/presentation/risk/risk_insights_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/risk_provider.dart';
import 'package:hercare/services/risk_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('risk insights remain overflow-free on a small phone',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(
            create: (_) => RiskProvider(service: _FakeRiskService()),
          ),
        ],
        child: const MaterialApp(home: RiskInsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('22.0 / 100 concern points'), findsOneWidget);
    await tester.tap(find.text('Daily').first);
    await tester.pumpAndSettle();
    expect(find.text('5.0 / 100 concern points'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Research baseline'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Research baseline'), findsOneWidget);
    await tester.tap(find.text('Research baseline'));
    await tester.pumpAndSettle();
    final action = find.text('Run research baseline');
    await tester.scrollUntilVisible(action, 140);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('68%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('risk insights submits only the chosen context answers and date',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
    final service = _FakeRiskService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(create: (_) => RiskProvider(service: service)),
        ],
        child: const MaterialApp(home: RiskInsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final questionnaire = find.text('What changed this week?');
    await tester.scrollUntilVisible(questionnaire, 180);
    await tester.tap(questionnaire);
    await tester.pumpAndSettle();
    final answer = find.byKey(const ValueKey('m4-financial_strain-2'));
    await tester.scrollUntilVisible(answer, 100);
    await tester.tap(answer);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('m4-save-context'));
    await tester.scrollUntilVisible(save, 200);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.checkin, {
      'date': '2026-11-13',
      'financial_strain': 2,
      'relationship_strain': null,
      'support_gap': null,
      'recovery_difficulty': null,
    });
    expect(find.text('Check-in saved.'), findsOneWidget);
  });

  test('risk provider discards reports from a previous account', () async {
    final oldReport = Completer<Map<String, dynamic>>();
    final service = _FakeRiskService(delayedReport: oldReport.future);
    final provider = RiskProvider(service: service);
    addTearDown(provider.dispose);
    provider.bindAccount('first');
    final request = provider.initialize();
    provider.bindAccount('second');
    service.delayedReport = null;
    await provider.initialize();
    oldReport.complete({'as_of': '2026-11-12'});
    await request;
    expect(provider.m4?['as_of'], '2026-11-13');
    provider.bindAccount(null);
    expect(provider.m4, isNull);
  });

  testWidgets('mood support opens the soothing category of the curated catalog',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const RiskInsightsScreen()),
      GoRoute(
        path: '/content',
        builder: (_, state) => Scaffold(
          body: Text(
              'Catalog category: ${state.uri.queryParameters['category']}'),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(
            create: (_) => RiskProvider(
              service: _FakeRiskService(
                nextStep: 'mood_support',
                findings: const ['epds_falling', 'supporting_changes'],
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Changes worth checking'), findsOneWidget);
    expect(find.textContaining('EPDS fell'), findsOneWidget);
    await tester.tap(find.text('Explore mood support'));
    await tester.pumpAndSettle();
    expect(find.text('Catalog category: soothing'), findsOneWidget);
  });
}

class _FakeRiskService extends RiskService {
  _FakeRiskService({
    this.delayedReport,
    this.nextStep = 'continue_checkins',
    this.findings = const [],
  });

  Future<Map<String, dynamic>>? delayedReport;
  Map<String, dynamic>? checkin;
  final String nextStep;
  final List<String> findings;

  @override
  Future<Map<String, dynamic>> m4Reports() async {
    final pending = delayedReport;
    if (pending != null) return pending;
    return {
      'as_of': '2026-11-13',
      'text_enabled': false,
      'checkin': checkin,
      'reports': [
        for (final (period, points) in [('weekly', 22.0), ('daily', 5.0)])
          {
            'period': period,
            'start_date': period == 'weekly' ? '2026-11-07' : '2026-11-13',
            'end_date': '2026-11-13',
            'score': points,
            'coverage': 54,
            'level': 'monitor',
            'direction': 'unchanged',
            'next_step': nextStep,
            'findings': findings,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> saveM4Checkin(
    Map<String, int?> values, {
    required String date,
  }) async =>
      checkin = {'date': date, ...values};

  @override
  Future<Map<String, dynamic>> recovery() async => {
        'periods': [
          for (final days in [1, 7, 14, 30])
            {
              'window_days': days,
              'direction': 'recorded_index_increased',
              'relative_index_change_percent': 2.0,
              'index_change_points': 1.0,
              'current': {'index_mean': 51.0},
              'previous': {'index_mean': 50.0},
            }
        ],
        'screening_changes': [],
      };

  @override
  Future<Map<String, dynamic>> modelContext() async => {
        'number_of_children': null,
        'basic_needs_affordable': null,
        'mother_in_law_relationship': null,
      };

  @override
  Future<Map<String, dynamic>> researchConsent() async =>
      {'enabled': false, 'eligible': false};
  @override
  Future<RiskStatus> getStatus() async => const RiskStatus(consentTier3: true);

  @override
  Future<RiskPrediction?> latest() async => RiskPrediction(
        id: 'prediction-id',
        modelVersion: 'm4-ensemble-v1',
        modelScope: 'cross_sectional_baseline',
        depressionProbability: .64,
        riskLevel: 'high',
        confidence: .56,
        dataCompleteness: .82,
        contributors: const [
          RiskContributor(factor: 'recent_screening', strength: .7),
          RiskContributor(factor: 'late_night_use', strength: .4),
        ],
        generatedAt: DateTime.utc(2026, 9, 24),
        isClinicalForecast: false,
      );

  @override
  Future<RiskPrediction> generatePrediction() async => RiskPrediction(
        id: 'new-prediction-id',
        modelVersion: 'm4-ensemble-v1',
        modelScope: 'cross_sectional_baseline',
        depressionProbability: .68,
        riskLevel: 'high',
        confidence: .56,
        dataCompleteness: .82,
        contributors: const [],
        generatedAt: DateTime.utc(2026, 11, 13),
        isClinicalForecast: false,
      );

  @override
  Future<TelemetryPermissions> permissions() async =>
      const TelemetryPermissions(
        isAndroid: true,
        notificationAccess: false,
        usageAccess: false,
      );

  @override
  Future<void> setMonitoringEnabled(bool enabled) async {}
}
