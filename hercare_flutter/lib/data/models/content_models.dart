/// Server-managed M11 catalogue models. No recommendations or clinical scores
/// are manufactured on the phone; only formatting and safe action routing live here.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.version,
    required this.titleEn,
    required this.titleUr,
    required this.summaryEn,
    required this.summaryUr,
    required this.bodyEn,
    required this.bodyUr,
    required this.category,
    required this.format,
    required this.audience,
    this.isReligious = false,
    this.isMusic = false,
    this.mediaUrl,
    this.sourceUrl,
    this.sourceName = '',
    this.licenseName = '',
    this.attribution = '',
    this.arabicText = '',
    this.transliteration = '',
    this.verseReference = '',
    this.activityType,
    this.activityId,
    this.durationSeconds,
    this.reasonEn = '',
    this.reasonUr = '',
    this.saved = false,
    this.feedback,
    this.reviewAfter,
    this.availableFrom,
    this.availableUntil,
  });

  static const categories = {
    'quran',
    'islamic',
    'soothing',
    'psychoeducation',
    'bonding',
    'game',
    'activity'
  };
  static const formats = {'article', 'audio', 'video', 'activity'};
  final String id, titleEn, titleUr, summaryEn, summaryUr, bodyEn, bodyUr;
  final int version;
  final String category, format, audience;
  final bool isReligious, isMusic, saved;
  final String? mediaUrl, sourceUrl, activityType, activityId, feedback;
  final String sourceName, licenseName, attribution;
  final String arabicText, transliteration, verseReference, reasonEn, reasonUr;
  final int? durationSeconds;
  final DateTime? reviewAfter;
  final DateTime? availableFrom, availableUntil;

  String title(bool ur) => ur && titleUr.isNotEmpty ? titleUr : titleEn;
  String summary(bool ur) => ur && summaryUr.isNotEmpty ? summaryUr : summaryEn;
  String body(bool ur) => ur && bodyUr.isNotEmpty ? bodyUr : bodyEn;
  String reason(bool ur) => ur && reasonUr.isNotEmpty ? reasonUr : reasonEn;
  bool get canSaveOffline =>
      format == 'article' &&
      (bodyEn.isNotEmpty || bodyUr.isNotEmpty || arabicText.isNotEmpty);

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    final id = _text(json['id'], 100);
    final category = _text(json['category'], 32);
    final format = _text(json['format'], 32);
    final audience = _text(json['audience'], 32);
    final title = _text(json['title_en'], 240);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) ||
        !categories.contains(category) ||
        !formats.contains(format) ||
        !{'mother', 'guardian', 'both'}.contains(audience) ||
        title.isEmpty) {
      throw const FormatException('Invalid content catalogue entry');
    }
    final feedback = _optionalText(json['feedback'], 24);
    return ContentItem(
      id: id,
      version: _integer(json['version'], 1, 2147483647) ?? 1,
      titleEn: title,
      titleUr: _text(json['title_ur'], 400),
      summaryEn: _text(json['summary_en'], 2000),
      summaryUr: _text(json['summary_ur'], 3000),
      bodyEn: _text(json['body_en'], 24000),
      bodyUr: _text(json['body_ur'], 30000),
      category: category,
      format: format,
      audience: audience,
      isReligious: json['is_religious'] == true ||
          category == 'quran' ||
          category == 'islamic',
      isMusic: json['is_music'] == true,
      mediaUrl: _optionalText(json['media_url'], 2048),
      sourceUrl: _optionalText(json['source_url'], 2048),
      sourceName: _text(json['source_name'], 300),
      licenseName: _text(json['license_name'], 500),
      attribution: _text(json['attribution'], 2000),
      arabicText: _text(json['arabic_text'], 12000),
      transliteration: _text(json['transliteration'], 12000),
      verseReference: _text(json['verse_reference'], 200),
      activityType: _optionalText(json['activity_type'], 30),
      activityId: _optionalText(json['activity_id'], 100),
      durationSeconds: _integer(json['duration_seconds'], 1, 7200),
      reasonEn: _text(json['reason_en'], 1000),
      reasonUr: _text(json['reason_ur'], 1500),
      saved: json['saved'] == true,
      feedback: {'helpful', 'not_helpful', 'dismissed'}.contains(feedback)
          ? feedback
          : null,
      reviewAfter: _date(json['review_after']),
      availableFrom: _date(json['available_from']),
      availableUntil: _date(json['available_until']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'title_en': titleEn,
        'title_ur': titleUr,
        'summary_en': summaryEn,
        'summary_ur': summaryUr,
        'body_en': bodyEn,
        'body_ur': bodyUr,
        'category': category,
        'format': format,
        'audience': audience,
        'is_religious': isReligious,
        'is_music': isMusic,
        'media_url': mediaUrl,
        'source_url': sourceUrl,
        'source_name': sourceName,
        'license_name': licenseName,
        'attribution': attribution,
        'arabic_text': arabicText,
        'transliteration': transliteration,
        'verse_reference': verseReference,
        'activity_type': activityType,
        'activity_id': activityId,
        'duration_seconds': durationSeconds,
        'reason_en': reasonEn,
        'reason_ur': reasonUr,
        'saved': saved,
        'feedback': feedback,
        'review_after': reviewAfter?.toIso8601String(),
        'available_from': availableFrom?.toIso8601String(),
        'available_until': availableUntil?.toIso8601String(),
      };

  /// Offline copies contain only explicitly saved educational text, not a
  /// health-derived ranking, media URL, recommendation reason or feedback.
  Map<String, dynamic> toOfflineJson() => toJson()
    ..remove('reason_en')
    ..remove('reason_ur')
    ..remove('media_url')
    ..remove('feedback');
}

class ContentPreferences {
  const ContentPreferences(
      {this.religiousEnabled = false,
      this.musicEnabled = false,
      this.disabledCategories = const [],
      this.version = 0});
  final bool religiousEnabled, musicEnabled;
  final List<String> disabledCategories;
  final int version;
  factory ContentPreferences.fromJson(Map<String, dynamic> json) =>
      ContentPreferences(
        religiousEnabled: json['religious_enabled'] == true,
        musicEnabled: json['music_enabled'] == true,
        disabledCategories: _list(json['disabled_categories'], 7)
            .whereType<String>()
            .where(ContentItem.categories.contains)
            .toList(),
        version: _integer(json['version'], 0, 2147483647) ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'religious_enabled': religiousEnabled,
        'music_enabled': musicEnabled,
        'disabled_categories': disabledCategories,
        'version': version,
      };
  bool allows(ContentItem item) =>
      (religiousEnabled || !item.isReligious) &&
      (musicEnabled || !item.isMusic) &&
      !disabledCategories.contains(item.category);
}

class ContentFeed {
  const ContentFeed(
      {required this.items,
      this.dailyVerse,
      required this.preferences,
      required this.catalogRevision,
      required this.generatedAt,
      this.refreshAfterSeconds = 30,
      this.safetyPriority = false,
      this.emptyReason,
      this.allowedMediaHosts = const []});
  final List<ContentItem> items;
  final ContentItem? dailyVerse;
  final ContentPreferences preferences;
  final String catalogRevision;
  final DateTime generatedAt;
  final int refreshAfterSeconds;
  final bool safetyPriority;
  final String? emptyReason;
  final List<String> allowedMediaHosts;
  factory ContentFeed.fromJson(Map<String, dynamic> json) => ContentFeed(
        items: _list(json['items'], 100)
            .map((value) =>
                ContentItem.fromJson(Map<String, dynamic>.from(value as Map)))
            .toList(),
        dailyVerse: json['daily_verse'] is Map
            ? ContentItem.fromJson(
                Map<String, dynamic>.from(json['daily_verse'] as Map))
            : null,
        preferences: ContentPreferences.fromJson(
            Map<String, dynamic>.from(json['preferences'] as Map? ?? const {})),
        catalogRevision: _text(json['catalog_revision'], 200),
        generatedAt:
            DateTime.tryParse(_text(json['generated_at'], 64))?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        refreshAfterSeconds:
            _integer(json['refresh_after_seconds'], 30, 600) ?? 30,
        safetyPriority: json['safety_priority'] == true,
        emptyReason: _optionalText(json['empty_reason'], 100),
        allowedMediaHosts: _list(json['allowed_media_hosts'], 100)
            .whereType<String>()
            .where((host) => RegExp(r'^[a-z0-9.-]{1,253}$').hasMatch(host))
            .toList(),
      );
}

List<dynamic> _list(dynamic value, int maximum) {
  if (value == null) return const [];
  if (value is! List || value.length > maximum) {
    throw const FormatException('Invalid bounded content list');
  }
  return value;
}

String _text(dynamic value, int maximum) {
  if (value == null) return '';
  if (value is! String || value.length > maximum) {
    throw const FormatException('Invalid content text');
  }
  return value;
}

String? _optionalText(dynamic value, int maximum) =>
    value == null ? null : _text(value, maximum);
int? _integer(dynamic value, int minimum, int maximum) {
  final number = value is num ? value : num.tryParse('$value');
  return number != null &&
          number.isFinite &&
          number == number.roundToDouble() &&
          number >= minimum &&
          number <= maximum
      ? number.toInt()
      : null;
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  final result = DateTime.tryParse(_text(value, 64));
  if (result == null) {
    throw const FormatException('Invalid content availability');
  }
  return result.toUtc();
}
