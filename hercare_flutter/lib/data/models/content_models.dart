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
    this.reasonCodes = const [],
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

  /// Server reason codes, first one shown on the card. Sent back only as the
  /// single code of the card she opened, so the operator report can tell which
  /// recommendation reasons are useful.
  final List<String> reasonCodes;
  String? get primaryReason => reasonCodes.isEmpty ? null : reasonCodes.first;

  /// The YouTube video ID for reviewed YouTube media, used for a preview image.
  String? get youtubeId {
    final uri = Uri.tryParse(mediaUrl ?? '');
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final id = host == 'youtu.be'
        ? (uri.pathSegments.isEmpty ? null : uri.pathSegments.first)
        : (host == 'www.youtube.com' || host == 'youtube.com') &&
                uri.path == '/watch'
            ? uri.queryParameters['v']
            : null;
    return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)
        ? id
        : null;
  }

  String? get thumbnailUrl => youtubeId == null
      ? null
      : 'https://i.ytimg.com/vi/$youtubeId/hqdefault.jpg';

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
      reasonCodes: _list(json['reason_codes'], 10)
          .whereType<String>()
          .where((code) => RegExp(r'^[a-z_]{1,24}$').hasMatch(code))
          .toList(),
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
        'reason_codes': reasonCodes,
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
    ..remove('reason_codes')
    ..remove('media_url')
    ..remove('feedback');
}

class ContentPreferences {
  const ContentPreferences(
      {this.religiousEnabled = false,
      this.musicEnabled = false,
      this.disabledCategories = const [],
      this.interests = const [],
      this.preferredFormats = const [],
      this.version = 0});

  /// Topics she can choose; the server maps each to reviewed catalogue tags.
  static const interestKeys = [
    'sleep',
    'calm',
    'music',
    'low_mood',
    'anxiety',
    'feeding',
    'body_recovery',
    'baby_bonding',
    'relationships',
    'faith',
    'learning',
  ];
  final bool religiousEnabled, musicEnabled;
  final List<String> disabledCategories;
  final List<String> interests, preferredFormats;
  final int version;
  factory ContentPreferences.fromJson(Map<String, dynamic> json) =>
      ContentPreferences(
        religiousEnabled: json['religious_enabled'] == true,
        musicEnabled: json['music_enabled'] == true,
        disabledCategories: _list(json['disabled_categories'], 7)
            .whereType<String>()
            .where(ContentItem.categories.contains)
            .toList(),
        interests: _list(json['interests'], interestKeys.length)
            .whereType<String>()
            .where(interestKeys.contains)
            .toList(),
        preferredFormats: _list(json['preferred_formats'], 4)
            .whereType<String>()
            .where(ContentItem.formats.contains)
            .toList(),
        version: _integer(json['version'], 0, 2147483647) ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'religious_enabled': religiousEnabled,
        'music_enabled': musicEnabled,
        'disabled_categories': disabledCategories,
        'interests': interests,
        'preferred_formats': preferredFormats,
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

/// An unreviewed result from trusted YouTube channels. Text is untrusted and
/// only ever rendered as plain text; links open after an explicit choice.
class LiveVideo {
  const LiveVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.topic,
    this.durationSeconds,
    this.isMusic = false,
    this.isReligious = false,
    this.category = 'soothing',
    this.reasonEn = '',
    this.reasonUr = '',
  });
  final String videoId,
      title,
      channelTitle,
      topic,
      category,
      reasonEn,
      reasonUr;
  final int? durationSeconds;
  final bool isMusic, isReligious;

  String get mediaUrl => 'https://www.youtube.com/watch?v=$videoId';
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
  String reason(bool ur) => ur && reasonUr.isNotEmpty ? reasonUr : reasonEn;

  factory LiveVideo.fromJson(Map<String, dynamic> json) {
    final id = _text(json['video_id'], 11);
    final title = _text(json['title'], 200);
    final category = _text(json['category'], 32);
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
        title.isEmpty ||
        !ContentItem.categories.contains(category) ||
        json['reviewed'] == true) {
      throw const FormatException('Invalid live result');
    }
    return LiveVideo(
      videoId: id,
      title: title,
      channelTitle: _text(json['channel_title'], 120),
      topic: _text(json['topic'], 24),
      durationSeconds: _integer(json['duration_seconds'], 1, 4 * 3600),
      isMusic: json['is_music'] == true,
      isReligious: json['is_religious'] == true,
      category: category,
      reasonEn: _text(json['reason_en'], 300),
      reasonUr: _text(json['reason_ur'], 400),
    );
  }
}

class LiveFeed {
  const LiveFeed(
      {this.enabled = false,
      this.items = const [],
      this.noticeEn = '',
      this.noticeUr = '',
      this.safetyPriority = false});
  final bool enabled, safetyPriority;
  final List<LiveVideo> items;
  final String noticeEn, noticeUr;
  String notice(bool ur) => ur && noticeUr.isNotEmpty ? noticeUr : noticeEn;
  factory LiveFeed.fromJson(Map<String, dynamic> json) => LiveFeed(
        enabled: json['enabled'] == true,
        safetyPriority: json['safety_priority'] == true,
        noticeEn: _text(json['notice_en'], 400),
        noticeUr: _text(json['notice_ur'], 500),
        items: _list(json['items'], 8)
            .map((value) =>
                LiveVideo.fromJson(Map<String, dynamic>.from(value as Map)))
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
