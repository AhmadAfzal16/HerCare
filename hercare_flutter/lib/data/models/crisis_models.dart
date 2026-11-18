/// M10 deliberately keeps private plans separate from public help information.
class CrisisPlan {
  const CrisisPlan({
    this.version = 0,
    this.copingStep = '',
    this.supportPersonName = '',
    this.supportPhone = '',
    this.updatedAt,
  });

  final int version;
  final String copingStep;
  final String supportPersonName;
  final String supportPhone;
  final DateTime? updatedAt;

  bool get isEmpty =>
      copingStep.isEmpty && supportPersonName.isEmpty && supportPhone.isEmpty;

  factory CrisisPlan.fromJson(Map<String, dynamic> json) => CrisisPlan(
        version: _integer(json['version'], 0, 1000000000),
        copingStep: _text(json['coping_step'], 500),
        supportPersonName: _text(json['support_person_name'], 80),
        supportPhone: _text(json['support_phone'], 24),
        updatedAt: _date(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'coping_step': copingStep,
        'support_person_name': supportPersonName,
        'support_phone': supportPhone,
        if (updatedAt != null)
          'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toRequest() => {...toJson()}..remove('updated_at');
}

class CrisisGuardian {
  const CrisisGuardian({
    required this.linkId,
    required this.name,
    required this.phone,
    this.safeToContactConfirmed = false,
  });
  final String linkId;
  final String name;
  final String phone;
  final bool safeToContactConfirmed;

  factory CrisisGuardian.fromJson(Map<String, dynamic> json) => CrisisGuardian(
        linkId: _identifier(json['link_id']),
        name: _text(json['name'], 80),
        phone: _text(json['phone'], 24),
        safeToContactConfirmed: json['safe_to_contact_confirmed'] == true,
      );
}

class CrisisEvent {
  const CrisisEvent({
    required this.id,
    required this.sourceType,
    required this.status,
    required this.triggeredAt,
    this.severity = 'high',
    this.guardianNotification = 'not_requested',
    this.outcome,
    this.notificationDelivery,
  });
  final String id;
  final String sourceType;
  final String status;
  final DateTime triggeredAt;
  final String severity;
  final String guardianNotification;
  final String? outcome;
  final String? notificationDelivery;

  bool get isClosed => status == 'resolved';
  factory CrisisEvent.fromJson(Map<String, dynamic> json) {
    final status = _text(json['status'], 24);
    if (!const ['open', 'active', 'triggered', 'acknowledged', 'resolved']
        .contains(status)) {
      throw const FormatException('Invalid crisis status');
    }
    return CrisisEvent(
      id: _identifier(json['id']),
      sourceType: _text(json['source_type'], 40),
      status: status,
      triggeredAt: _date(json['triggered_at']) ??
          (throw const FormatException('Missing event date')),
      severity: _text(json['severity'], 24),
      guardianNotification: _text(json['guardian_notification'], 24),
      outcome: json['outcome'] == null ? null : _text(json['outcome'], 40),
      notificationDelivery: json['notification_delivery'] == null
          ? null
          : _text(json['notification_delivery'], 30),
    );
  }
}

class CrisisSupport {
  const CrisisSupport({
    this.plan = const CrisisPlan(),
    this.guardian,
    this.openEvent,
  });
  final CrisisPlan plan;
  final CrisisGuardian? guardian;
  final CrisisEvent? openEvent;

  factory CrisisSupport.fromJson(Map<String, dynamic> json) => CrisisSupport(
        plan: CrisisPlan.fromJson(_object(json['plan'])),
        guardian: json['guardian'] == null
            ? null
            : CrisisGuardian.fromJson(_object(json['guardian'])),
        openEvent: json['open_event'] == null
            ? null
            : CrisisEvent.fromJson(_object(json['open_event'])),
      );
}

class CrisisHistory {
  const CrisisHistory({this.events = const [], this.nextCursor});
  final List<CrisisEvent> events;
  final String? nextCursor;
  factory CrisisHistory.fromJson(Map<String, dynamic> json) {
    final values = json['events'];
    if (values is! List || values.length > 20) {
      throw const FormatException('Invalid event history');
    }
    return CrisisHistory(
      events:
          values.map((value) => CrisisEvent.fromJson(_object(value))).toList(),
      nextCursor:
          json['next_cursor'] == null ? null : _text(json['next_cursor'], 256),
    );
  }
}

class CrisisContact {
  const CrisisContact({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.phone,
    required this.kind,
    required this.coverageEn,
    required this.coverageUr,
    required this.hoursEn,
    required this.hoursUr,
    required this.sourceUrl,
    required this.verifiedAt,
  });
  final String id, nameEn, nameUr, phone, kind;
  final String coverageEn, coverageUr, hoursEn, hoursUr, sourceUrl;
  final DateTime verifiedAt;

  String name(bool urdu) => urdu ? nameUr : nameEn;
  String coverage(bool urdu) => urdu ? coverageUr : coverageEn;
  String hours(bool urdu) => urdu ? hoursUr : hoursEn;

  factory CrisisContact.fromJson(Map<String, dynamic> json) => CrisisContact(
        id: _identifier(json['id']),
        nameEn: _text(json['name'], 160),
        nameUr: _text(json['name_ur'], 200),
        phone: _text(json['phone'], 24),
        kind: _text(json['type'], 30),
        coverageEn: _text(json['caution'], 500),
        coverageUr: _text(json['caution_ur'], 600),
        hoursEn: _text(json['hours_en'], 160),
        hoursUr: _text(json['hours_ur'], 200),
        sourceUrl: _text(json['source_url'], 500),
        verifiedAt: _date(json['verified_on']) ??
            (throw const FormatException('Missing verification date')),
      );
}

class CrisisRegion {
  const CrisisRegion({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    this.emergencyNumber,
    required this.sourceUrl,
    required this.coverageNotice,
    required this.coverageNoticeUr,
  });
  final String id, nameEn, nameUr;
  final String? emergencyNumber;
  final String sourceUrl, coverageNotice, coverageNoticeUr;
  String name(bool urdu) => urdu ? nameUr : nameEn;

  factory CrisisRegion.fromJson(Map<String, dynamic> json) {
    return CrisisRegion(
      id: _identifier(json['id']),
      nameEn: _text(json['name'], 100),
      nameUr: _text(json['name_ur'], 120),
      emergencyNumber: json['emergency_number'] == null
          ? null
          : _text(json['emergency_number'], 24),
      sourceUrl: _text(json['source_url'], 500),
      coverageNotice: _text(json['coverage_notice'], 500),
      coverageNoticeUr: _text(json['coverage_notice_ur'], 600),
    );
  }
}

class CrisisCatalog {
  const CrisisCatalog({
    required this.version,
    required this.reviewedAt,
    required this.regions,
    required this.contacts,
    required this.notice,
    required this.noticeUr,
  });
  final String version;
  final DateTime reviewedAt;
  final List<CrisisRegion> regions;
  final List<CrisisContact> contacts;
  final String notice, noticeUr;

  factory CrisisCatalog.fromJson(Map<String, dynamic> json) {
    final regions = json['regions'];
    final contacts = json['contacts'];
    if (regions is! List ||
        regions.length > 30 ||
        contacts is! List ||
        contacts.length > 20) {
      throw const FormatException('Invalid region catalog');
    }
    return CrisisCatalog(
      version: _text(json['version'], 80),
      reviewedAt: _date(json['verified_on']) ??
          (throw const FormatException('Missing catalog date')),
      regions: regions.map((r) => CrisisRegion.fromJson(_object(r))).toList(),
      contacts:
          contacts.map((c) => CrisisContact.fromJson(_object(c))).toList(),
      notice: _text(json['notice'], 600),
      noticeUr: _text(json['notice_ur'], 800),
    );
  }
}

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

String _text(dynamic value, int max) {
  if (value == null) return '';
  if (value is! String || value.length > max) {
    throw const FormatException('Invalid text');
  }
  return value;
}

String _identifier(dynamic value) {
  final id = _text(value, 100);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
    throw const FormatException('Invalid identifier');
  }
  return id;
}

int _integer(dynamic value, int min, int max) {
  if (value == null) return min;
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid version');
  }
  return value;
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.length > 50) {
    throw const FormatException('Invalid date');
  }
  return DateTime.tryParse(value)?.toUtc() ??
      (throw const FormatException('Invalid date'));
}
