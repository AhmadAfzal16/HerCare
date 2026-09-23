int _jsonInt(Object? value, String field) {
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed != null) return parsed.toInt();
  }
  throw FormatException('Invalid numeric value for $field.');
}

double _jsonDouble(Object? value, String field) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Invalid numeric value for $field.');
}

double? _jsonNullableDouble(Object? value, String field) {
  if (value == null) return null;
  return _jsonDouble(value, field);
}

class MoodCheckin {
  const MoodCheckin({
    required this.id,
    required this.entryDate,
    required this.moodRating,
    required this.energyLevel,
    required this.sleepQuality,
    required this.socialSupport,
    required this.compositeScore,
    this.isSynced = true,
  });

  final String id;
  final DateTime entryDate;
  final int moodRating;
  final int energyLevel;
  final int sleepQuality;
  final int socialSupport;
  final double compositeScore;
  final bool isSynced;

  factory MoodCheckin.fromJson(Map<String, dynamic> json) => MoodCheckin(
        id: json['id']?.toString() ?? '',
        entryDate: DateTime.parse(json['entry_date'] as String),
        moodRating: _jsonInt(json['mood_rating'], 'mood_rating'),
        energyLevel: _jsonInt(json['energy_level'], 'energy_level'),
        sleepQuality: _jsonInt(json['sleep_quality'], 'sleep_quality'),
        socialSupport: _jsonInt(json['social_support'], 'social_support'),
        compositeScore:
            _jsonDouble(json['composite_score'], 'composite_score'),
        isSynced: json['is_synced'] as bool? ?? true,
      );
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.entryType,
    required this.language,
    required this.processingStatus,
    required this.containsDanger,
    required this.createdAt,
    this.content,
    this.sentimentLabel,
    this.sentimentScore,
    this.distressScore,
    this.isSynced = true,
  });

  final String id;
  final String entryType;
  final String language;
  final String processingStatus;
  final String? content;
  final String? sentimentLabel;
  final double? sentimentScore;
  final double? distressScore;
  final bool containsDanger;
  final DateTime createdAt;
  final bool isSynced;

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'] as String,
        entryType: json['entry_type'] as String? ?? 'text',
        language: json['language'] as String? ?? 'en',
        processingStatus: json['processing_status'] as String? ?? 'complete',
        content: json['content'] as String?,
        sentimentLabel: json['sentiment_label'] as String?,
        sentimentScore:
            _jsonNullableDouble(json['sentiment_score'], 'sentiment_score'),
        distressScore:
            _jsonNullableDouble(json['distress_score'], 'distress_score'),
        containsDanger: json['contains_danger'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        isSynced: json['is_synced'] as bool? ?? true,
      );
}

class MoodSummary {
  const MoodSummary({
    required this.start,
    required this.end,
    required this.entries,
    required this.trend,
    this.average,
  });

  final DateTime start;
  final DateTime end;
  final int entries;
  final double? average;
  final List<double> trend;

  factory MoodSummary.fromJson(Map<String, dynamic> json) => MoodSummary(
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
        entries: _jsonInt(json['entries'], 'entries'),
        average: _jsonNullableDouble(json['average'], 'average'),
        trend: (json['mood_trend'] as List<dynamic>? ?? const [])
            .map((value) => _jsonDouble(value, 'mood_trend'))
            .toList(),
      );
}
