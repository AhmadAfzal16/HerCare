import 'dart:math' as math;

/// Public, source-checked institutions, never a doctor ranking or diagnosis.
class CareFacility {
  const CareFacility({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.region,
    required this.cityEn,
    required this.cityUr,
    required this.addressEn,
    required this.addressUr,
    required this.phone,
    required this.serviceEn,
    required this.serviceUr,
    required this.sourceUrls,
    required this.checkedOn,
    required this.reviewDueOn,
    this.latitude,
    this.longitude,
    this.coordinatesSourceUrl,
    this.coordinateKind,
    this.serverStale = false,
    this.serverReviewStatus,
  });

  final String id, nameEn, nameUr, region, cityEn, cityUr;
  final String addressEn, addressUr, phone, serviceEn, serviceUr;
  final List<Uri> sourceUrls;
  final DateTime checkedOn, reviewDueOn;
  final double? latitude, longitude;
  final Uri? coordinatesSourceUrl;
  final String? coordinateKind;
  final bool serverStale;
  final String? serverReviewStatus;

  String name(bool urdu) => urdu ? nameUr : nameEn;
  String city(bool urdu) => urdu ? cityUr : cityEn;
  String address(bool urdu) => urdu ? addressUr : addressEn;
  String service(bool urdu) => urdu ? serviceUr : serviceEn;
  String reviewStatus(DateTime now) => _reviewStatus(
      checkedOn, reviewDueOn, now, serverReviewStatus, serverStale);
  bool reviewIsDue(DateTime now) => reviewStatus(now) != 'current';
  bool get hasCoordinates => latitude != null && longitude != null;

  factory CareFacility.fromJson(Map<String, dynamic> json,
      {required Set<String> approvedHosts}) {
    _publicFields(json, _facilityFields, const {'review_status', 'stale'});
    _runtimeFields(json);
    if (json['verification_status'] != 'official_source_checked' ||
        json['clinical_approval'] != false ||
        json['availability'] != 'unknown') {
      throw const FormatException('Invalid facility verification');
    }
    final sources = json['source_urls'];
    if (sources is! List || sources.isEmpty || sources.length > 5) {
      throw const FormatException('Invalid facility sources');
    }
    final checked = _date(json['checked_on']);
    final review = _date(json['review_due_on']);
    _reviewDates(checked, review);
    final phone = _text(json['phone'], 24);
    if (!RegExp(r'^\+?[0-9\s()-]{3,24}$').hasMatch(phone) ||
        !RegExp(r'^\+?[0-9]{3,15}$')
            .hasMatch(phone.replaceAll(RegExp(r'[\s()-]'), ''))) {
      throw const FormatException('Invalid facility phone');
    }
    double? latitude, longitude;
    Uri? coordinatesSource;
    String? coordinateKind;
    if (json['latitude'] != null || json['longitude'] != null) {
      latitude = _coordinate(json['latitude'], -90, 90);
      longitude = _coordinate(json['longitude'], -180, 180);
      coordinatesSource =
          sourceUri(json['coordinates_source_url'], approvedHosts);
      final kind = json['coordinate_kind'];
      if (!const ['official_geo_point', 'official_map_view_center']
          .contains(kind)) {
        throw const FormatException('Invalid coordinate provenance');
      }
      coordinateKind = kind as String;
    } else if (json['coordinates_source_url'] != null ||
        json['coordinate_kind'] != null) {
      throw const FormatException('Coordinates missing');
    }
    return CareFacility(
      id: _identifier(json['id']),
      nameEn: _text(json['name'], 160),
      nameUr: _text(json['name_ur'], 200),
      region: _identifier(json['region']),
      cityEn: _text(json['city'], 100),
      cityUr: _text(json['city_ur'], 120),
      addressEn: _text(json['address'], 400),
      addressUr: _text(json['address_ur'], 500),
      phone: phone,
      serviceEn: _text(json['service'], 400),
      serviceUr: _text(json['service_ur'], 500),
      sourceUrls: List.unmodifiable(
          sources.map((source) => sourceUri(source, approvedHosts))),
      checkedOn: checked,
      reviewDueOn: review,
      latitude: latitude,
      longitude: longitude,
      coordinatesSourceUrl: coordinatesSource,
      coordinateKind: coordinateKind,
      serverStale: json['stale'] == true,
      serverReviewStatus: json['review_status'],
    );
  }

  /// Only published institution coordinates are used; never a city centre.
  double? distanceKm(CarePosition position) {
    if (!hasCoordinates) return null;
    const radians = math.pi / 180;
    final latDelta = (latitude! - position.latitude) * radians;
    final lonDelta = (longitude! - position.longitude) * radians;
    final a = math.pow(math.sin(latDelta / 2), 2) +
        math.cos(position.latitude * radians) *
            math.cos(latitude! * radians) *
            math.pow(math.sin(lonDelta / 2), 2);
    return 6371 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

class CareDirectory {
  const CareDirectory({
    required this.version,
    required this.checkedOn,
    required this.reviewDueOn,
    required this.noticeEn,
    required this.noticeUr,
    required this.facilities,
    this.serverStale = false,
    this.serverReviewStatus,
  });
  final String version, noticeEn, noticeUr;
  final DateTime checkedOn, reviewDueOn;
  final List<CareFacility> facilities;
  final bool serverStale;
  final String? serverReviewStatus;
  String notice(bool urdu) => urdu ? noticeUr : noticeEn;

  String reviewStatus(DateTime now) {
    final own = _reviewStatus(
        checkedOn, reviewDueOn, now, serverReviewStatus, serverStale);
    final statuses = [
      own,
      ...facilities.map((entry) => entry.reviewStatus(now))
    ];
    if (statuses.contains('date_unconfirmed')) return 'date_unconfirmed';
    if (statuses.contains('review_due')) return 'review_due';
    return 'current';
  }

  factory CareDirectory.fromJson(Map<String, dynamic> json,
      {required Set<String> approvedHosts}) {
    _publicFields(json, _catalogFields,
        const {'approved_domains', 'review_status', 'stale'});
    _runtimeFields(json);
    if (json.containsKey('approved_domains')) {
      final domains = json['approved_domains'];
      if (domains is! List ||
          domains.isEmpty ||
          domains.length > 30 ||
          domains.any((domain) =>
              domain is! String || !approvedHosts.contains(domain)) ||
          domains.toSet().length != domains.length) {
        throw const FormatException('Invalid catalog source domains');
      }
    }
    final entries = json['facilities'];
    if (entries is! List || entries.isEmpty || entries.length > 30) {
      throw const FormatException('Invalid facility catalog');
    }
    final facilities = entries.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid facility');
      }
      return CareFacility.fromJson(entry, approvedHosts: approvedHosts);
    }).toList(growable: false);
    if (facilities.map((entry) => entry.id).toSet().length !=
        facilities.length) {
      throw const FormatException('Duplicate facility');
    }
    final checked = _date(json['checked_on']);
    final due = _date(json['review_due_on']);
    _reviewDates(checked, due);
    if (facilities.any((entry) => entry.checkedOn.isAfter(checked))) {
      throw const FormatException('Facility checked after catalog');
    }
    return CareDirectory(
      version: _text(json['version'], 80),
      checkedOn: checked,
      reviewDueOn: due,
      noticeEn: _text(json['notice'], 1200),
      noticeUr: _text(json['notice_ur'], 1600),
      facilities: List.unmodifiable(facilities),
      serverStale: json['stale'] == true,
      serverReviewStatus: json['review_status'],
    );
  }

  List<CareFacility> listed({String? city, CarePosition? position}) {
    final result = facilities
        .where((entry) => city == null || entry.cityEn == city)
        .toList();
    result.sort((a, b) {
      if (position != null) {
        final left = a.distanceKm(position), right = b.distanceKm(position);
        if (left != null && right != null) {
          final order = left.compareTo(right);
          if (order != 0) return order;
        } else if (left != null) {
          return -1;
        } else if (right != null) {
          return 1;
        }
      }
      return a.nameEn.compareTo(b.nameEn);
    });
    return result;
  }
}

const _catalogFields = {
  'version',
  'checked_on',
  'review_due_on',
  'notice',
  'notice_ur',
  'facilities',
};
const _facilityFields = {
  'id',
  'name',
  'name_ur',
  'region',
  'city',
  'city_ur',
  'address',
  'address_ur',
  'phone',
  'service',
  'service_ur',
  'source_urls',
  'checked_on',
  'review_due_on',
  'verification_status',
  'clinical_approval',
  'availability',
  'latitude',
  'longitude',
  'coordinates_source_url',
  'coordinate_kind',
};

void _publicFields(
    Map<String, dynamic> json, Set<String> required, Set<String> optional) {
  if (required.any((key) => !json.containsKey(key)) ||
      json.keys
          .any((key) => !required.contains(key) && !optional.contains(key))) {
    throw const FormatException('Unexpected public catalog fields');
  }
}

void _runtimeFields(Map<String, dynamic> json) {
  final hasStatus = json.containsKey('review_status');
  final hasStale = json.containsKey('stale');
  if ((hasStatus &&
          !const ['current', 'review_due', 'date_unconfirmed']
              .contains(json['review_status'])) ||
      (hasStale && json['stale'] is! bool) ||
      (hasStatus &&
          hasStale &&
          json['stale'] != (json['review_status'] != 'current'))) {
    throw const FormatException('Invalid review metadata');
  }
}

void _reviewDates(DateTime checked, DateTime due) {
  if (due.isBefore(checked) ||
      due.difference(checked) > const Duration(days: 180)) {
    throw const FormatException('Invalid review interval');
  }
}

String _reviewStatus(DateTime checked, DateTime due, DateTime now,
    String? serverStatus, bool serverStale) {
  final utc = now.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  if (checked.isAfter(day)) return 'date_unconfirmed';
  if (due.isBefore(day)) return 'review_due';
  if (serverStatus != null && serverStatus != 'current') return serverStatus;
  if (serverStale) return 'date_unconfirmed';
  return 'current';
}

/// An ephemeral foreground fix, deliberately without a serialization method.
class CarePosition {
  const CarePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
  });
  final double latitude, longitude, accuracyMeters;
  final DateTime recordedAt;
  factory CarePosition.fromNative(Map<dynamic, dynamic> value,
      {required DateTime now}) {
    final timestamp = value['recorded_at'];
    final recorded = timestamp is num &&
            timestamp.isFinite &&
            timestamp >= 0 &&
            timestamp <= 8640000000000000 &&
            timestamp == timestamp.roundToDouble()
        ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt(), isUtc: true)
        : throw const FormatException('Invalid location time');
    final age = now.difference(recorded);
    if (age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -30)) {
      throw const FormatException('Location is not current');
    }
    return CarePosition(
      latitude: _coordinate(value['latitude'], -90, 90),
      longitude: _coordinate(value['longitude'], -180, 180),
      accuracyMeters: _coordinate(value['accuracy'], 1, 10000),
      recordedAt: recorded,
    );
  }
}

Uri sourceUri(dynamic raw, Set<String> approvedHosts) {
  final uri = Uri.tryParse(_text(raw, 700));
  if (uri == null ||
      uri.scheme != 'https' ||
      !approvedHosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment ||
      (uri.query.isNotEmpty &&
          !(uri.host == 'bipbs.gob.pk' && uri.query == 'page_id=1906'))) {
    throw const FormatException('Unapproved institution source');
  }
  return uri;
}

String _text(dynamic value, int limit) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > limit ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid public catalog text');
  }
  return value.trim();
}

String _identifier(dynamic value) {
  final result = _text(value, 80);
  if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(result)) {
    throw const FormatException('Invalid catalog identifier');
  }
  return result;
}

DateTime _date(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid review date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid review date');
  }
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

double _coordinate(dynamic value, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    throw const FormatException('Invalid coordinate');
  }
  return value.toDouble();
}
