class TherapyRecommendation {
  const TherapyRecommendation({
    required this.activityType,
    required this.activityId,
    required this.reason,
    required this.reasonUr,
    required this.safetyPriority,
  });

  final String activityType;
  final String activityId;
  final String reason;
  final String reasonUr;
  final bool safetyPriority;

  factory TherapyRecommendation.fromJson(Map<String, dynamic> json) =>
      TherapyRecommendation(
        activityType: json['activity_type']?.toString() ?? 'breathing',
        activityId: json['activity_id']?.toString() ?? 'box_breathing',
        reason: json['reason']?.toString() ?? '',
        reasonUr: json['reason_ur']?.toString() ?? '',
        safetyPriority: json['safety_priority'] == true,
      );
}

/// Optional monitoring around one breathing/meditation session: tension 0-10
/// before/after, a distress answer, and a short heart reading before/after.
/// Only these summary numbers are saved; camera frames and beat timings stay
/// on the phone and are discarded after the reading.
class TherapyMeasures {
  const TherapyMeasures({
    this.tensionBefore,
    this.tensionAfter,
    this.distressReported,
    this.hrBefore,
    this.hrAfter,
    this.hrvBefore,
    this.hrvAfter,
    this.physioSource,
  });

  final int? tensionBefore,
      tensionAfter,
      hrBefore,
      hrAfter,
      hrvBefore,
      hrvAfter;
  final bool? distressReported;

  /// 'camera' (fingertip, approximate) or 'band' (Bluetooth heart-rate band).
  final String? physioSource;

  bool get hasHeart =>
      hrBefore != null ||
      hrAfter != null ||
      hrvBefore != null ||
      hrvAfter != null;
  bool get isEmpty =>
      tensionBefore == null &&
      tensionAfter == null &&
      distressReported == null &&
      !hasHeart;
  int? get tensionChange => tensionBefore == null || tensionAfter == null
      ? null
      : tensionAfter! - tensionBefore!;

  TherapyMeasures copyWith({
    int? tensionBefore,
    int? tensionAfter,
    bool? distressReported,
    int? hrBefore,
    int? hrAfter,
    int? hrvBefore,
    int? hrvAfter,
    String? physioSource,
  }) =>
      TherapyMeasures(
        tensionBefore: tensionBefore ?? this.tensionBefore,
        tensionAfter: tensionAfter ?? this.tensionAfter,
        distressReported: distressReported ?? this.distressReported,
        hrBefore: hrBefore ?? this.hrBefore,
        hrAfter: hrAfter ?? this.hrAfter,
        hrvBefore: hrvBefore ?? this.hrvBefore,
        hrvAfter: hrvAfter ?? this.hrvAfter,
        physioSource: physioSource ?? this.physioSource,
      );

  /// Server/queue shape. Heart readings are only sent with their source.
  Map<String, dynamic> toJson() => {
        if (tensionBefore != null) 'tension_before': tensionBefore,
        if (tensionAfter != null) 'tension_after': tensionAfter,
        if (distressReported != null) 'distress_reported': distressReported,
        if (hasHeart && physioSource != null) ...{
          if (hrBefore != null) 'hr_before': hrBefore,
          if (hrAfter != null) 'hr_after': hrAfter,
          if (hrvBefore != null) 'hrv_before': hrvBefore,
          if (hrvAfter != null) 'hrv_after': hrvAfter,
          'physio_source': physioSource,
        },
      };

  static TherapyMeasures? fromJson(dynamic json) {
    if (json is! Map) return null;
    final source = json['physio_source'];
    final value = TherapyMeasures(
      tensionBefore: _integer(json['tension_before'], maximum: 10),
      tensionAfter: _integer(json['tension_after'], maximum: 10),
      distressReported: json['distress_reported'] is bool
          ? json['distress_reported'] as bool
          : null,
      hrBefore: _integer(json['hr_before'], minimum: 35, maximum: 220),
      hrAfter: _integer(json['hr_after'], minimum: 35, maximum: 220),
      hrvBefore: _integer(json['hrv_before'], minimum: 1, maximum: 300),
      hrvAfter: _integer(json['hrv_after'], minimum: 1, maximum: 300),
      physioSource:
          source == 'camera' || source == 'band' ? source as String : null,
    );
    return value.isEmpty ? null : value;
  }

  /// Validates a queued/outgoing map exactly as the server will.
  static bool validJson(dynamic json) {
    if (json == null) return true;
    if (json is! Map) return false;
    const ranges = {
      'tension_before': (0, 10),
      'tension_after': (0, 10),
      'hr_before': (35, 220),
      'hr_after': (35, 220),
      'hrv_before': (1, 300),
      'hrv_after': (1, 300),
    };
    for (final key in json.keys) {
      if (!ranges.containsKey(key) &&
          key != 'distress_reported' &&
          key != 'physio_source') {
        return false;
      }
    }
    var heart = false;
    for (final entry in ranges.entries) {
      final value = json[entry.key];
      if (value == null) continue;
      if (value is! int || value < entry.value.$1 || value > entry.value.$2) {
        return false;
      }
      if (entry.key.startsWith('hr')) heart = true;
    }
    final distress = json['distress_reported'];
    if (distress != null && distress is! bool) return false;
    final source = json['physio_source'];
    if (heart != (source != null)) return false;
    return source == null || source == 'camera' || source == 'band';
  }
}

class TherapySession {
  const TherapySession({
    required this.id,
    required this.activityType,
    required this.activityId,
    required this.durationSeconds,
    required this.completed,
    this.breathingParticipation,
    required this.completedAt,
    this.moodBefore,
    this.moodAfter,
    this.isSynced = true,
    this.measures,
  });

  final TherapyMeasures? measures;

  final String id;
  final String activityType;
  final String activityId;
  final int durationSeconds;
  final int? moodBefore;
  final int? moodAfter;
  final bool completed;
  final String? breathingParticipation;
  final DateTime completedAt;
  final bool isSynced;

  int? get moodChange => !completed || moodBefore == null || moodAfter == null
      ? null
      : moodAfter! - moodBefore!;

  factory TherapySession.fromJson(Map<String, dynamic> json) => TherapySession(
        id: json['id']?.toString() ?? '',
        activityType: json['activity_type']?.toString() ?? '',
        activityId: json['activity_id']?.toString() ?? '',
        durationSeconds: _integer(json['duration_seconds'], maximum: 7200) ?? 0,
        moodBefore: _integer(json['mood_before'], minimum: 1, maximum: 5),
        moodAfter: _integer(json['mood_after'], minimum: 1, maximum: 5),
        completed: json['completed'] == true,
        breathingParticipation: json['breathing_participation'] as String?,
        measures: TherapyMeasures.fromJson(json['measures']),
        completedAt:
            DateTime.tryParse(json['completed_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class TherapySummary {
  const TherapySummary({
    required this.totalSessions,
    required this.completedSessions,
    required this.totalSeconds,
    this.averageMoodChange,
    this.periodDays = 30,
    this.pairedMoodSessions = 0,
  });

  final int totalSessions;
  final int completedSessions;
  final int totalSeconds;
  final double? averageMoodChange;
  final int periodDays;
  final int pairedMoodSessions;

  factory TherapySummary.fromJson(Map<String, dynamic> json) => TherapySummary(
        totalSessions: _integer(json['total_sessions']) ?? 0,
        completedSessions: _integer(json['completed_sessions']) ?? 0,
        totalSeconds: _integer(json['total_seconds']) ?? 0,
        averageMoodChange: _numberOrNull(json['avg_mood_change']),
        periodDays:
            _integer(json['period_days'], minimum: 1, maximum: 366) ?? 30,
        pairedMoodSessions: _integer(json['paired_mood_sessions']) ?? 0,
      );

  static double? _numberOrNull(dynamic value) {
    if (value == null) return null;
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed.abs() <= 4
        ? parsed
        : null;
  }
}

int? _integer(dynamic value,
    {int minimum = 0, int maximum = 9007199254740991}) {
  final parsed = value is num ? value : num.tryParse('$value');
  if (parsed == null || !parsed.isFinite || parsed != parsed.roundToDouble()) {
    return null;
  }
  if (parsed < minimum || parsed > maximum) return null;
  return parsed.toInt();
}

class TherapyActivity {
  const TherapyActivity({
    required this.id,
    required this.type,
    required this.title,
    required this.titleUr,
    required this.description,
    required this.descriptionUr,
    required this.minutes,
  });

  final String id;
  final String type;
  final String title;
  final String titleUr;
  final String description;
  final String descriptionUr;
  final int minutes;
}

abstract final class TherapyCatalog {
  static const activities = <TherapyActivity>[
    // Best-supported patterns first: exhale-focused cyclic sighing (Balban et
    // al. 2023) and slow ~6 breaths/minute breathing (Lehrer & Gevirtz 2014).
    TherapyActivity(
        id: 'cyclic_sighing',
        type: 'breathing',
        title: 'Calming Sigh',
        titleUr: 'پرسکون آہ',
        description: 'Two short breaths in, one long breath out.',
        descriptionUr: 'دو چھوٹی سانسیں اندر، ایک لمبی سانس باہر۔',
        minutes: 5),
    TherapyActivity(
        id: 'resonance_breathing',
        type: 'breathing',
        title: 'Slow Steady Breathing',
        titleUr: 'آہستہ اور یکساں سانس',
        description: 'Six slow breaths a minute, no holding.',
        descriptionUr: 'ایک منٹ میں چھ آہستہ سانسیں، سانس روکے بغیر۔',
        minutes: 5),
    TherapyActivity(
        id: 'breathing_478',
        type: 'breathing',
        title: '4-7-8 Breathing',
        titleUr: '4-7-8 سانس',
        description: 'Slow down with a longer exhale.',
        descriptionUr: 'لمبی سانس چھوڑ کر سکون پائیں۔',
        minutes: 3),
    TherapyActivity(
        id: 'box_breathing',
        type: 'breathing',
        title: 'Box Breathing',
        titleUr: 'باکس بریتھنگ',
        description: 'Equal inhale, hold, exhale, and rest.',
        descriptionUr: 'برابر سانس، روکنا، چھوڑنا اور آرام۔',
        minutes: 4),
    TherapyActivity(
        id: 'diaphragmatic',
        type: 'breathing',
        title: 'Belly Breathing',
        titleUr: 'پیٹ سے سانس',
        description: 'Gentle diaphragmatic breathing.',
        descriptionUr: 'نرم ڈایافرامی سانس کی مشق۔',
        minutes: 3),
    TherapyActivity(
        id: 'body_scan',
        type: 'meditation',
        title: 'Body Scan',
        titleUr: 'باڈی اسکین',
        description: 'Notice and soften tension.',
        descriptionUr: 'جسم میں تناؤ محسوس کریں اور نرم کریں۔',
        minutes: 5),
    TherapyActivity(
        id: 'muscle_relaxation',
        type: 'meditation',
        title: 'Muscle Relaxation',
        titleUr: 'پٹھوں کا آرام',
        description: 'Release tension one area at a time.',
        descriptionUr: 'ایک ایک حصے کا تناؤ ختم کریں۔',
        minutes: 5),
    TherapyActivity(
        id: 'mindfulness',
        type: 'meditation',
        title: 'Mindful Pause',
        titleUr: 'ذہنی توقف',
        description: 'Return attention to this moment.',
        descriptionUr: 'توجہ موجودہ لمحے میں لائیں۔',
        minutes: 3),
    TherapyActivity(
        id: 'thought_challenge',
        type: 'cbt',
        title: 'Thought Challenge',
        titleUr: 'خیال کو پرکھیں',
        description: 'Build a more balanced thought.',
        descriptionUr: 'زیادہ متوازن خیال بنائیں۔',
        minutes: 5),
    TherapyActivity(
        id: 'behavior_plan',
        type: 'cbt',
        title: 'One Small Step',
        titleUr: 'ایک چھوٹا قدم',
        description: 'Plan one achievable supportive action.',
        descriptionUr: 'ایک قابلِ عمل مددگار قدم چنیں۔',
        minutes: 3),
    TherapyActivity(
        id: 'grounding_54321',
        type: 'cbt',
        title: '5-4-3-2-1 Grounding',
        titleUr: '5-4-3-2-1 گراؤنڈنگ',
        description: 'Reconnect with your five senses.',
        descriptionUr: 'پانچ حواس سے موجودہ لمحے میں آئیں۔',
        minutes: 3),
    TherapyActivity(
        id: 'worry_time',
        type: 'cbt',
        title: 'Worry Time',
        titleUr: 'فکر کا وقت',
        description: 'Contain worries in a short planned window.',
        descriptionUr: 'فکروں کے لیے مختصر مقررہ وقت رکھیں۔',
        minutes: 5),
    TherapyActivity(
        id: 'memory_match',
        type: 'game',
        title: 'Memory Match',
        titleUr: 'یادداشت میچ',
        description: 'A tiny four-pair memory game.',
        descriptionUr: 'چار جوڑوں کا ہلکا یادداشت کھیل۔',
        minutes: 2),
    TherapyActivity(
        id: 'breathing_bubbles',
        type: 'game',
        title: 'Breathing Bubbles',
        titleUr: 'سانس کے بلبلے',
        description: 'Tap bubbles slowly with each exhale.',
        descriptionUr: 'ہر سانس چھوڑتے ہوئے آہستہ بلبلہ چھوئیں۔',
        minutes: 2),
    TherapyActivity(
        id: 'color_calm',
        type: 'game',
        title: 'Color Calm',
        titleUr: 'پرسکون رنگ',
        description: 'Follow a gentle color sequence.',
        descriptionUr: 'نرم رنگوں کی ترتیب مکمل کریں۔',
        minutes: 2),
    TherapyActivity(
        id: 'domestic_puzzle',
        type: 'game',
        title: 'A Peaceful Home',
        titleUr: 'پرسکون گھر',
        description: 'Match three household items to their places.',
        descriptionUr: 'گھر کی تین چیزوں کو ان کی جگہ سے ملائیں۔',
        minutes: 2),
  ];

  static TherapyActivity byId(String id) => activities.firstWhere(
        (value) => value.id == id,
        orElse: () => activities[1],
      );
}
