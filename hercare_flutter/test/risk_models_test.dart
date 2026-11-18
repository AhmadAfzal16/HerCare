import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/risk_models.dart';

void main() {
  test('missing or untrained future probability is not a zero estimate', () {
    for (final value in [null, 0.62, '0.62', 'NaN', double.infinity]) {
      final outlook = FutureDepressionOutlook.fromJson({
        'status': 'not_trained',
        'probability': value,
        'horizon_days': 14,
      });
      expect(outlook.probability, isNull);
      expect(outlook.horizonDays, 14);
    }
    expect(FutureDepressionOutlook.fromJson({}).probability, isNull);
  });

  test('monitoring keeps instruments separate and safety overrides summary',
      () {
    final monitoring = DepressionMonitoring.fromJson({
      'status': 'observed_monitoring_only',
      'requires_safety_review': false,
      'screening_trends': [
        {
          'instrument': 'epds',
          'previous_score': '15',
          'current_score': '11',
          'score_change_points': '-4',
          'direction': 'lower_recorded_symptoms',
          'safety_positive': true,
          'stale': false,
          'current_date': '2026-10-09',
        },
        {
          'instrument': 'phq9',
          'previous_score': null,
          'current_score': 8,
          'score_change_points': null,
          'direction': 'insufficient_data',
        },
      ],
      'future_outlook': {'status': 'not_trained', 'probability': null},
      'supporting_signals': {'mood': {}, 'sleep': {}},
    });
    expect(monitoring.requiresSafetyReview, isTrue);
    expect(monitoring.screeningTrends.first.scoreChangePoints, -4);
    expect(monitoring.screeningTrends.last.previousScore, isNull);
    expect(monitoring.futureOutlook.probability, isNull);
    expect(monitoring.sleep.windows, isEmpty);
  });

  test('a negative latest item does not erase a recorded safety response', () {
    final monitoring = DepressionMonitoring.fromJson({
      'requires_safety_review': false,
      'safety_history': {'recorded_positive_count': '1'},
      'screening_trends': [
        {
          'instrument': 'epds',
          'current_score': 8,
          'previous_score': 12,
          'score_change_points': -4,
          'direction': 'lower_recorded_symptoms',
          'safety_positive': false,
        },
      ],
    });
    expect(monitoring.screeningTrends.single.safetyPositive, isFalse);
    expect(monitoring.requiresSafetyReview, isTrue);
  });

  test('risk prediction safely parses PostgreSQL numeric values', () {
    final prediction = RiskPrediction.fromJson({
      'id': 'prediction-id',
      'model_version': 'm4-ensemble-v1',
      'model_scope': 'cross_sectional_baseline',
      'horizon_days': null,
      'depression_probability': '0.62345',
      'risk_level': 'high',
      'confidence': '0.55',
      'data_completeness': '0.83',
      'contributors': [
        {'factor': 'low_mood', 'strength': '0.75'},
      ],
      'generated_at': '2026-09-24T00:00:00.000Z',
      'is_clinical_forecast': false,
    });

    expect(prediction.depressionProbability, closeTo(0.62345, 0.00001));
    expect(prediction.confidence, isNull);
    expect(prediction.contributors.single.strength, 0.75);
    expect(prediction.isClinicalForecast, isFalse);
  });

  test('native telemetry parsing keeps aggregate counters only', () {
    final snapshot = TelemetrySnapshot.fromMap({
      'local_date': '2026-09-24',
      'timezone_offset_minutes': -300,
      'notifications_seen': 20,
      'message_notifications': 12,
      'negative_notifications': 3,
      'distress_notifications': 1,
      'abuse_notifications': 0,
      'screen_time_minutes': 180,
      'social_minutes': 60,
      'late_night_minutes': 15,
      'app_switches': 44,
      'notification_access': true,
      'usage_access': true,
      'analysis_version': 'on-device-lexicon-v1',
    });

    final json = snapshot.toApiJson(
      '11111111-1111-4111-8111-111111111111',
    );
    expect(json['negative_notifications'], 3);
    expect(json.containsKey('preview'), isFalse);
    expect(json.containsKey('content'), isFalse);
  });
}
