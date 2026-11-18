import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/providers/risk_provider.dart';
import 'package:hercare/presentation/risk/recovery_panel.dart';
import 'package:hercare/services/risk_service.dart';

void main() {
  for (final urdu in [false, true]) {
    testWidgets(
        'observed monitoring is safe at 320px and 200% text (${urdu ? 'Urdu' : 'English'})',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
              textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
              child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: RecoveryPanel(
                              provider: _MonitoringProvider(),
                              isUrdu: urdu)))))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('monitoring-safety-review')),
          findsOneWidget);
      expect(find.text(urdu ? 'حفاظتی جائزہ ضروری ہے' : 'Safety review needed'),
          findsOneWidget);
      expect(
          find.text(urdu
              ? 'مجموعی اسکور کم درج ہوا؛ حفاظتی جائزہ پھر بھی ضروری ہے۔'
              : 'Lower total recorded; safety review is still needed.'),
          findsOneWidget);
      expect(find.text('Lower recorded symptom score'), findsNothing);
      expect(find.text('94%'), findsNothing);
      final future =
          find.byKey(const ValueKey('future-probability-unavailable'));
      await tester.ensureVisible(future);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final details = find
          .text(urdu ? 'ماڈل کی اختیاری معلومات' : 'Optional model details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find
          .text(urdu ? 'اختیاری معلومات محفوظ کریں' : 'Save optional details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale screening does not announce improvement', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RecoveryPanel(
                    provider: _MonitoringProvider(stale: true),
                    isUrdu: false)))));
    await tester.pumpAndSettle();
    expect(find.text('Lower recorded symptom score'), findsNothing);
    expect(find.textContaining('older than its follow-up schedule'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final urdu in [false, true]) {
    testWidgets(
        'recovery and optional details fit a small screen (${urdu ? 'Urdu' : 'English'})',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = _ReadyProvider();
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
              textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
              child: MediaQuery(
                  data:
                      const MediaQueryData(textScaler: TextScaler.linear(1.4)),
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: RecoveryPanel(
                              provider: provider, isUrdu: urdu)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final details = find
          .text(urdu ? 'ماڈل کی اختیاری معلومات' : 'Optional model details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last = find
          .text(urdu ? 'اختیاری معلومات محفوظ کریں' : 'Save optional details');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final consent = find.byType(SwitchListTile);
      await tester.ensureVisible(consent);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(consent).onChanged, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}

class _ReadyProvider extends RiskProvider {
  _ReadyProvider() : super(service: RiskService());
  @override
  Map<String, dynamic> get recovery => {
        'periods': [
          {
            'window_days': 7,
            'direction': 'recorded_index_increased',
            'relative_index_change_percent': 2.0,
            'index_change_points': 1.0,
            'current': {'index_mean': 51.0},
            'previous': {'index_mean': 50.0}
          }
        ],
        'screening_changes': [],
      };
  @override
  Map<String, dynamic> get modelContext => {
        'number_of_children': null,
        'basic_needs_affordable': null,
        'mother_in_law_relationship': null,
      };
  @override
  Map<String, dynamic> get research => {'enabled': false, 'eligible': false};
}

class _MonitoringProvider extends _ReadyProvider {
  _MonitoringProvider({this.stale = false});
  final bool stale;
  @override
  Map<String, dynamic> get recovery => {
        ...super.recovery,
        'depression_monitoring': {
          'status': 'observed_monitoring_only',
          'requires_safety_review': !stale,
          'screening_trends': [
            {
              'instrument': 'epds',
              'previous_score': 16,
              'current_score': 12,
              'score_change_points': -4,
              'direction': 'lower_recorded_symptoms',
              'previous_date': '2026-10-02',
              'current_date': '2026-10-09',
              'stale': stale,
              'safety_positive': !stale,
            },
            {
              'instrument': 'phq9',
              'previous_score': null,
              'current_score': null,
              'score_change_points': null,
              'direction': 'insufficient_data',
              'stale': false,
              'safety_positive': false,
            },
          ],
          'future_outlook': {
            'status': 'not_trained',
            'probability': .94,
            'horizon_days': 14,
          },
          'supporting_signals': {
            'mood': {'status': 'observed', 'windows': []},
            'sleep': {
              'status': 'observed',
              'direction': 'descriptive_only',
              'windows': [
                {
                  'window_days': 7,
                  'previous': {
                    'sleep_minutes_mean': 350,
                    'awakenings_mean': 3,
                    'quality_mean': 2,
                    'bedtime_minute': {'mean_minute': 1435},
                    'wake_minute': {'mean_minute': 425},
                  },
                  'current': {
                    'sleep_minutes_mean': 370,
                    'awakenings_mean': 2,
                    'quality_mean': 3,
                    'bedtime_minute': {'mean_minute': 5},
                    'wake_minute': {'mean_minute': 430},
                  },
                }
              ],
            },
          },
        },
      };
}
