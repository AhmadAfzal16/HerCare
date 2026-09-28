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

class TherapySession {
  const TherapySession({
    required this.id,
    required this.activityType,
    required this.activityId,
    required this.durationSeconds,
    required this.completed,
    required this.completedAt,
    this.moodBefore,
    this.moodAfter,
    this.isSynced = true,
  });

  final String id;
  final String activityType;
  final String activityId;
  final int durationSeconds;
  final int? moodBefore;
  final int? moodAfter;
  final bool completed;
  final DateTime completedAt;
  final bool isSynced;

  int? get moodChange =>
      moodBefore == null || moodAfter == null ? null : moodAfter! - moodBefore!;

  factory TherapySession.fromJson(Map<String, dynamic> json) => TherapySession(
        id: json['id']?.toString() ?? '',
        activityType: json['activity_type']?.toString() ?? '',
        activityId: json['activity_id']?.toString() ?? '',
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        moodBefore: (json['mood_before'] as num?)?.toInt(),
        moodAfter: (json['mood_after'] as num?)?.toInt(),
        completed: json['completed'] != false,
        completedAt:
            DateTime.tryParse(json['completed_at']?.toString() ?? '') ??
                DateTime.now(),
      );
}

class TherapySummary {
  const TherapySummary({
    required this.totalSessions,
    required this.completedSessions,
    required this.totalSeconds,
    this.averageMoodChange,
  });

  final int totalSessions;
  final int completedSessions;
  final int totalSeconds;
  final double? averageMoodChange;

  factory TherapySummary.fromJson(Map<String, dynamic> json) => TherapySummary(
        totalSessions: (json['total_sessions'] as num?)?.toInt() ?? 0,
        completedSessions: (json['completed_sessions'] as num?)?.toInt() ?? 0,
        totalSeconds: (json['total_seconds'] as num?)?.toInt() ?? 0,
        averageMoodChange: _numberOrNull(json['avg_mood_change']),
      );

  static double? _numberOrNull(dynamic value) {
    if (value == null) return null;
    return value is num ? value.toDouble() : double.tryParse('$value');
  }
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
  ];

  static TherapyActivity byId(String id) => activities.firstWhere(
        (value) => value.id == id,
        orElse: () => activities[1],
      );
}
