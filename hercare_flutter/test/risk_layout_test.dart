import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    await tester.scrollUntilVisible(
      find.text('Research baseline'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Research baseline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeRiskService extends RiskService {
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
  Future<TelemetryPermissions> permissions() async =>
      const TelemetryPermissions(
        isAndroid: true,
        notificationAccess: false,
        usageAccess: false,
      );

  @override
  Future<void> setMonitoringEnabled(bool enabled) async {}
}
