int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

double? _finiteNullableDouble(Object? value) {
  if (value == null) return null;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

Map<String, dynamic> _objectMap(Object? value) => value is Map
    ? {for (final entry in value.entries) '${entry.key}': entry.value}
    : const {};

/// Observed questionnaire changes are not a depression diagnosis or forecast.
class ScreeningSymptomTrend {
  const ScreeningSymptomTrend({
    required this.instrument,
    required this.direction,
    required this.stale,
    required this.safetyPositive,
    this.previousScore,
    this.currentScore,
    this.scoreChangePoints,
    this.previousDate,
    this.currentDate,
    this.reason,
  });

  final String instrument;
  final String direction;
  final bool stale;
  final bool safetyPositive;
  final double? previousScore;
  final double? currentScore;
  final double? scoreChangePoints;
  final String? previousDate;
  final String? currentDate;
  final String? reason;

  factory ScreeningSymptomTrend.fromJson(Map<String, dynamic> json) =>
      ScreeningSymptomTrend(
        instrument: json['instrument'] as String? ?? 'unknown',
        direction: json['direction'] as String? ?? 'insufficient_data',
        stale: json['stale'] == true,
        safetyPositive: json['safety_positive'] == true,
        previousScore: _finiteNullableDouble(json['previous_score']),
        currentScore: _finiteNullableDouble(json['current_score']),
        scoreChangePoints: _finiteNullableDouble(json['score_change_points']),
        previousDate: json['previous_date'] as String?,
        currentDate: json['current_date'] as String?,
        reason: json['reason'] as String?,
      );
}

class FutureDepressionOutlook {
  const FutureDepressionOutlook({
    required this.status,
    required this.horizonDays,
    this.probability,
  });

  final String status;
  final int horizonDays;
  final double? probability;

  factory FutureDepressionOutlook.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String? ?? 'unavailable';
    final parsed = _finiteNullableDouble(json['probability']);
    // A missing/untrained forecast must not become 0% or a baseline estimate.
    final available =
        status == 'available' || status == 'externally_validated_and_approved';
    return FutureDepressionOutlook(
      status: status,
      horizonDays: _intValue(json['horizon_days'], fallback: 14),
      probability: available && parsed != null && parsed >= 0 && parsed <= 1
          ? parsed
          : null,
    );
  }
}

class SupportingMonitoringSignal {
  const SupportingMonitoringSignal({
    required this.status,
    required this.direction,
    required this.windows,
  });

  final String status;
  final String direction;
  final List<Map<String, dynamic>> windows;

  factory SupportingMonitoringSignal.fromJson(Map<String, dynamic> json) =>
      SupportingMonitoringSignal(
        status: json['status'] as String? ?? 'insufficient_data',
        direction: json['direction'] as String? ?? 'descriptive_only',
        windows: (json['windows'] as List? ?? const [])
            .whereType<Map>()
            .map(_objectMap)
            .toList(growable: false),
      );
}

class DepressionMonitoring {
  const DepressionMonitoring({
    required this.status,
    required this.requiresSafetyReview,
    required this.screeningTrends,
    required this.futureOutlook,
    required this.mood,
    required this.sleep,
  });

  final String status;
  final bool requiresSafetyReview;
  final List<ScreeningSymptomTrend> screeningTrends;
  final FutureDepressionOutlook futureOutlook;
  final SupportingMonitoringSignal mood;
  final SupportingMonitoringSignal sleep;

  factory DepressionMonitoring.fromJson(Map<String, dynamic> json) {
    final signals = _objectMap(json['supporting_signals']);
    final safetyHistory = _objectMap(json['safety_history']);
    final recordedSafetyCount =
        _finiteNullableDouble(safetyHistory['recorded_positive_count']) ?? 0;
    final trends = (json['screening_trends'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ScreeningSymptomTrend.fromJson(_objectMap(row)))
        .toList(growable: false);
    return DepressionMonitoring(
      status: json['status'] as String? ?? 'unavailable',
      requiresSafetyReview: json['requires_safety_review'] == true ||
          recordedSafetyCount > 0 ||
          trends.any((trend) => trend.safetyPositive),
      screeningTrends: trends,
      futureOutlook:
          FutureDepressionOutlook.fromJson(_objectMap(json['future_outlook'])),
      mood: SupportingMonitoringSignal.fromJson(_objectMap(signals['mood'])),
      sleep: SupportingMonitoringSignal.fromJson(_objectMap(signals['sleep'])),
    );
  }
}

class TelemetryPermissions {
  const TelemetryPermissions({
    required this.isAndroid,
    required this.notificationAccess,
    required this.usageAccess,
  });

  final bool isAndroid;
  final bool notificationAccess;
  final bool usageAccess;
  bool get fullyEnabled => notificationAccess && usageAccess;
}

class TelemetrySnapshot {
  const TelemetrySnapshot({
    required this.localDate,
    required this.notificationsSeen,
    required this.messageNotifications,
    required this.negativeNotifications,
    required this.distressNotifications,
    required this.abuseNotifications,
    required this.screenTimeMinutes,
    required this.socialMinutes,
    required this.lateNightMinutes,
    required this.appSwitches,
    required this.notificationAccess,
    required this.usageAccess,
    required this.analysisVersion,
    required this.timezoneOffsetMinutes,
  });

  final String localDate;
  final int notificationsSeen;
  final int messageNotifications;
  final int negativeNotifications;
  final int distressNotifications;
  final int abuseNotifications;
  final int screenTimeMinutes;
  final int socialMinutes;
  final int lateNightMinutes;
  final int appSwitches;
  final bool notificationAccess;
  final bool usageAccess;
  final String analysisVersion;
  final int timezoneOffsetMinutes;

  factory TelemetrySnapshot.fromMap(Map<Object?, Object?> value) =>
      TelemetrySnapshot(
        localDate: '${value['local_date']}',
        notificationsSeen: _intValue(value['notifications_seen']),
        messageNotifications: _intValue(value['message_notifications']),
        negativeNotifications: _intValue(value['negative_notifications']),
        distressNotifications: _intValue(value['distress_notifications']),
        abuseNotifications: _intValue(value['abuse_notifications']),
        screenTimeMinutes: _intValue(value['screen_time_minutes']),
        socialMinutes: _intValue(value['social_minutes']),
        lateNightMinutes: _intValue(value['late_night_minutes']),
        appSwitches: _intValue(value['app_switches']),
        notificationAccess: value['notification_access'] == true,
        usageAccess: value['usage_access'] == true,
        analysisVersion: '${value['analysis_version']}',
        timezoneOffsetMinutes: _intValue(value['timezone_offset_minutes']),
      );

  Map<String, Object> toApiJson(String requestId) => {
        'local_date': localDate,
        'timezone_offset_minutes': timezoneOffsetMinutes,
        'notifications_seen': notificationsSeen,
        'message_notifications': messageNotifications,
        'negative_notifications': negativeNotifications,
        'distress_notifications': distressNotifications,
        'abuse_notifications': abuseNotifications,
        'screen_time_minutes': screenTimeMinutes,
        'social_minutes': socialMinutes,
        'late_night_minutes': lateNightMinutes,
        'app_switches': appSwitches,
        'notification_access': notificationAccess,
        'usage_access': usageAccess,
        'analysis_version': analysisVersion,
        'client_request_id': requestId,
      };
}

class RiskContributor {
  const RiskContributor({required this.factor, required this.strength});
  final String factor;
  final double strength;

  factory RiskContributor.fromJson(Map<String, dynamic> json) =>
      RiskContributor(
        factor: json['factor'] as String? ?? 'unknown',
        strength: _doubleValue(json['strength']),
      );
}

class RiskPrediction {
  const RiskPrediction({
    required this.id,
    required this.modelVersion,
    required this.modelScope,
    required this.depressionProbability,
    required this.riskLevel,
    required this.confidence,
    required this.dataCompleteness,
    required this.contributors,
    required this.generatedAt,
    required this.isClinicalForecast,
    this.horizonDays,
    this.confidenceType = 'not_estimated',
    this.validationStatus = 'research_only',
  });

  final String id;
  final String modelVersion;
  final String modelScope;
  final int? horizonDays;
  final double depressionProbability;
  final String riskLevel;
  final double? confidence;
  final String confidenceType;
  final String validationStatus;
  final double dataCompleteness;
  final List<RiskContributor> contributors;
  final DateTime generatedAt;
  final bool isClinicalForecast;

  factory RiskPrediction.fromJson(Map<String, dynamic> json) => RiskPrediction(
        id: json['id'] as String,
        modelVersion: json['model_version'] as String,
        modelScope: json['model_scope'] as String,
        horizonDays: json['horizon_days'] == null
            ? null
            : _intValue(json['horizon_days']),
        depressionProbability: _doubleValue(json['depression_probability']),
        riskLevel: json['risk_level'] as String,
        confidence: json['confidence_type'] == 'calibrated' &&
                json['confidence'] != null
            ? _doubleValue(json['confidence'])
            : null,
        confidenceType: json['confidence_type'] as String? ?? 'not_estimated',
        validationStatus:
            json['validation_status'] as String? ?? 'research_only',
        dataCompleteness: _doubleValue(json['data_completeness']),
        contributors: (json['contributors'] as List<dynamic>? ?? const [])
            .map((value) =>
                RiskContributor.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        generatedAt: DateTime.parse(json['generated_at'] as String),
        isClinicalForecast: json['is_clinical_forecast'] == true &&
            json['validation_status'] == 'externally_validated_and_approved',
      );
}

class RiskStatus {
  const RiskStatus({required this.consentTier3, this.lastTelemetryAt});
  final bool consentTier3;
  final DateTime? lastTelemetryAt;

  factory RiskStatus.fromJson(Map<String, dynamic> json) {
    final telemetry = json['latest_telemetry'];
    return RiskStatus(
      consentTier3: json['consent_tier3'] == true,
      lastTelemetryAt:
          telemetry is Map<String, dynamic> && telemetry['updated_at'] is String
              ? DateTime.parse(telemetry['updated_at'] as String)
              : null,
    );
  }
}
