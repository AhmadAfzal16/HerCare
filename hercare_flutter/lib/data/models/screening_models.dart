int _asInt(Object? value, String field) {
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Invalid value for $field.');
}

class ScreeningOption {
  const ScreeningOption({
    required this.index,
    required this.textEn,
    required this.textUr,
    required this.score,
  });

  final int index;
  final String textEn;
  final String textUr;
  final int score;

  factory ScreeningOption.fromJson(Map<String, dynamic> json) =>
      ScreeningOption(
        index: _asInt(json['index'], 'index'),
        textEn: json['text_en'] as String,
        textUr: json['text_ur'] as String,
        score: _asInt(json['score'], 'score'),
      );
}

class ScreeningQuestion {
  const ScreeningQuestion({
    required this.number,
    required this.textEn,
    required this.textUr,
    required this.options,
  });

  final int number;
  final String textEn;
  final String textUr;
  final List<ScreeningOption> options;

  factory ScreeningQuestion.fromJson(Map<String, dynamic> json) =>
      ScreeningQuestion(
        number: _asInt(json['number'], 'number'),
        textEn: json['text_en'] as String,
        textUr: json['text_ur'] as String,
        options: (json['options'] as List<dynamic>)
            .map((value) =>
                ScreeningOption.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class ScreeningInstrument {
  const ScreeningInstrument({
    required this.type,
    required this.name,
    required this.version,
    required this.scoringVersion,
    required this.timeframeDays,
    required this.maxScore,
    required this.crisisQuestion,
    required this.questions,
  });

  final String type;
  final String name;
  final String version;
  final String scoringVersion;
  final int timeframeDays;
  final int maxScore;
  final int crisisQuestion;
  final List<ScreeningQuestion> questions;

  factory ScreeningInstrument.fromJson(Map<String, dynamic> json) =>
      ScreeningInstrument(
        type: json['type'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        scoringVersion: json['scoring_version'] as String,
        timeframeDays: _asInt(json['timeframe_days'], 'timeframe_days'),
        maxScore: _asInt(json['max_score'], 'max_score'),
        crisisQuestion: _asInt(json['crisis_question'], 'crisis_question'),
        questions: (json['questions'] as List<dynamic>)
            .map((value) =>
                ScreeningQuestion.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class ScreeningAssessment {
  const ScreeningAssessment({
    required this.id,
    required this.instrumentType,
    required this.instrumentVersion,
    required this.scoringVersion,
    required this.language,
    required this.status,
    required this.selfHarmPositive,
    required this.startedAt,
    required this.updatedAt,
    this.totalScore,
    this.riskLevel,
    this.completedAt,
    this.answers = const {},
  });

  final String id;
  final String instrumentType;
  final String instrumentVersion;
  final String scoringVersion;
  final String language;
  final String status;
  final int? totalScore;
  final String? riskLevel;
  final bool selfHarmPositive;
  final DateTime startedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;
  final Map<int, int> answers;

  factory ScreeningAssessment.fromJson(Map<String, dynamic> json) {
    final answerMap = <int, int>{};
    for (final value in json['answers'] as List<dynamic>? ?? const []) {
      final answer = value as Map<String, dynamic>;
      answerMap[_asInt(answer['question_number'], 'question_number')] =
          _asInt(answer['option_index'], 'option_index');
    }
    return ScreeningAssessment(
      id: json['id'] as String,
      instrumentType: json['instrument_type'] as String,
      instrumentVersion: json['instrument_version'] as String,
      scoringVersion: json['scoring_version'] as String,
      language: json['language'] as String,
      status: json['status'] as String,
      totalScore: json['total_score'] == null
          ? null
          : _asInt(json['total_score'], 'total_score'),
      riskLevel: json['risk_level'] as String?,
      selfHarmPositive: json['self_harm_positive'] as bool? ?? false,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      answers: answerMap,
    );
  }
}

class ScreeningReminder {
  const ScreeningReminder({
    required this.instrumentType,
    required this.due,
    this.dueAt,
  });

  final String instrumentType;
  final bool due;
  final DateTime? dueAt;

  factory ScreeningReminder.fromJson(Map<String, dynamic> json) =>
      ScreeningReminder(
        instrumentType: json['instrument_type'] as String,
        due: json['due'] as bool? ?? false,
        dueAt: json['due_at'] == null
            ? null
            : DateTime.parse(json['due_at'] as String),
      );
}
