import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/risk_models.dart';

void main() {
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
    expect(prediction.confidence, 0.55);
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
