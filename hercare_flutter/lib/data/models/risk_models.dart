int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _doubleValue(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
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
  });

  final String id;
  final String modelVersion;
  final String modelScope;
  final int? horizonDays;
  final double depressionProbability;
  final String riskLevel;
  final double confidence;
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
        confidence: _doubleValue(json['confidence']),
        dataCompleteness: _doubleValue(json['data_completeness']),
        contributors: (json['contributors'] as List<dynamic>? ?? const [])
            .map((value) =>
                RiskContributor.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        generatedAt: DateTime.parse(json['generated_at'] as String),
        isClinicalForecast: json['is_clinical_forecast'] == true,
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
