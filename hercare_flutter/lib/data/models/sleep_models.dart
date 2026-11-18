double? _number(dynamic value, double min, double max) {
  if (value == null) return null;
  final number = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  if (number == null || !number.isFinite || number < min || number > max) {
    throw const FormatException('Invalid sleep measurement');
  }
  return number;
}

int _count(dynamic value, int max) {
  final n = _number(value, 0, max.toDouble());
  if (n == null) throw const FormatException('Missing sleep count');
  if (n != n.roundToDouble()) {
    throw const FormatException('Invalid sleep count');
  }
  return n.toInt();
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid sleep response');
  }
  return value;
}

int? _integer(dynamic value, int min, int max) {
  final n = _number(value, min.toDouble(), max.toDouble());
  if (n != null && n != n.roundToDouble()) {
    throw const FormatException('Invalid sleep integer');
  }
  return n?.toInt();
}

DateTime _instant(dynamic value) {
  if (value is! String ||
      !RegExp(r'T.*(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Invalid sleep timestamp');
  }
  return DateTime.parse(value);
}

String _day(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid sleep date');
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' !=
          value) {
    throw const FormatException('Invalid sleep date');
  }
  return value;
}

List<dynamic> _list(dynamic value, int max) {
  if (value is! List || value.length > max) {
    throw const FormatException('Unbounded sleep response');
  }
  return value;
}

class SleepRecord {
  SleepRecord.fromJson(Map<String, dynamic> json)
      : date = _day(json['sleep_date']),
        bedtime = _instant(json['bedtime']),
        wake = _instant(json['wake_time']),
        minutes = _number(json['sleep_minutes'], 1, 1440)!,
        awakeMinutes = _count(json['awake_minutes'], 1439),
        quality = _integer(json['quality'], 1, 5),
        awakenings =
            json['awakenings'] == null ? null : _count(json['awakenings'], 50),
        timezoneOffset = _integer(json['timezone_offset_minutes'], -840, 840) ??
            (throw const FormatException('Missing sleep timezone')) {
    if (!wake.isAfter(bedtime) ||
        wake.difference(bedtime) > const Duration(hours: 24) ||
        timezoneOffset.abs() > 840) {
      throw const FormatException('Invalid sleep interval');
    }
    if ((wake.difference(bedtime).inMilliseconds / 60000 -
                awakeMinutes -
                minutes)
            .abs() >
        1) {
      throw const FormatException('Inconsistent sleep duration');
    }
    final localWake = wake.toUtc().subtract(Duration(minutes: timezoneOffset));
    if ('${localWake.year.toString().padLeft(4, '0')}-${localWake.month.toString().padLeft(2, '0')}-${localWake.day.toString().padLeft(2, '0')}' !=
        date) {
      throw const FormatException('Inconsistent sleep date');
    }
  }
  final String date;
  final DateTime bedtime, wake;
  final double minutes;
  final int awakeMinutes, timezoneOffset;
  final int? quality, awakenings;
  Map<String, dynamic> toJson() => {
        'sleep_date': date,
        'bedtime': bedtime.toUtc().toIso8601String(),
        'wake_time': wake.toUtc().toIso8601String(),
        'sleep_minutes': minutes,
        'awake_minutes': awakeMinutes,
        'quality': quality,
        'awakenings': awakenings,
        'timezone_offset_minutes': timezoneOffset
      };
}

class SleepWindow {
  SleepWindow.fromJson(Map<String, dynamic> json)
      : days = _count(json['days'], 30),
        nights = _count(_map(json['current'])['nights'], 30),
        previousNights = _count(_map(json['previous'])['nights'], 30),
        minimum = _count(json['minimum_nights'], 30),
        average = _number(_map(json['current'])['average_minutes'], 1, 1440),
        previousAverage =
            _number(_map(json['previous'])['average_minutes'], 1, 1440),
        quality = _number(_map(json['current'])['average_quality'], 1, 5),
        shortNights = _count(_map(json['current'])['short_nights'], 30),
        change = _number(json['change_minutes'], -1439, 1439),
        direction = json['direction'] as String {
    if (![7, 14, 30].contains(days) ||
        nights > days ||
        previousNights > days ||
        shortNights > nights ||
        ![
          'insufficient_data',
          'more_recorded_sleep',
          'less_recorded_sleep',
          'similar_recorded_sleep'
        ].contains(direction) ||
        minimum !=
            (days == 7
                ? 5
                : days == 14
                    ? 10
                    : 14) ||
        (direction == 'insufficient_data' && change != null) ||
        (direction != 'insufficient_data' &&
            (change == null || nights < minimum || previousNights < minimum))) {
      throw const FormatException('Invalid sleep trend');
    }
  }
  final int days, nights, previousNights, minimum, shortNights;
  final double? average, previousAverage, quality, change;
  final String direction;
  Map<String, dynamic> toJson() => {
        'days': days,
        'minimum_nights': minimum,
        'current': {
          'nights': nights,
          'average_minutes': average,
          'average_quality': quality,
          'short_nights': shortNights
        },
        'previous': {
          'nights': previousNights,
          'average_minutes': previousAverage
        },
        'change_minutes': change,
        'direction': direction
      };
}

class SleepCorrelation {
  SleepCorrelation.fromJson(Map<String, dynamic> json)
      : status = json['status'] as String,
        direction = json['direction'] as String,
        pairs = _count(json['paired_days'], 30),
        minimum = _count(json['minimum_days'], 30),
        coefficient = _number(json['coefficient'], -1, 1),
        shortDays = _count(_map(json['under_six_hours'])['days'], 30),
        longerDays = _count(_map(json['six_hours_or_more'])['days'], 30),
        shortMood =
            _number(_map(json['under_six_hours'])['average_mood'], 1, 5),
        longerMood =
            _number(_map(json['six_hours_or_more'])['average_mood'], 1, 5) {
    if (!['available', 'insufficient_data', 'stale', 'no_variation']
            .contains(status) ||
        !['positive', 'negative', 'no_clear_pattern', 'insufficient_data']
            .contains(direction) ||
        shortDays + longerDays != pairs ||
        minimum != 14 ||
        (status == 'available' && (coefficient == null || pairs < minimum)) ||
        (status != 'available' && coefficient != null)) {
      throw const FormatException('Invalid sleep association');
    }
  }
  final String status, direction;
  final int pairs, minimum, shortDays, longerDays;
  final double? coefficient, shortMood, longerMood;
  Map<String, dynamic> toJson() => {
        'status': status,
        'direction': direction,
        'paired_days': pairs,
        'minimum_days': minimum,
        'coefficient': coefficient,
        'under_six_hours': {'days': shortDays, 'average_mood': shortMood},
        'six_hours_or_more': {'days': longerDays, 'average_mood': longerMood}
      };
}

class SleepDigitalSummary {
  SleepDigitalSummary.fromJson(Map<String, dynamic> json)
      : sharingEnabled = json['sharing_enabled'] == true,
        fresh = json['fresh'] == true,
        days = _count(json['recorded_days'], 7),
        socialDays = _count(json['high_social_days'], 7),
        lateDays = _count(json['late_use_days'], 7),
        socialMinutes = _number(json['average_social_minutes'], 0, 1440),
        lateMinutes = _number(json['average_late_night_minutes'], 0, 480) {
    if (socialDays > days ||
        lateDays > days ||
        (!sharingEnabled && days != 0)) {
      throw const FormatException('Invalid digital summary');
    }
  }
  final bool sharingEnabled, fresh;
  final int days, socialDays, lateDays;
  final double? socialMinutes, lateMinutes;
  Map<String, dynamic> toJson() => {
        'sharing_enabled': sharingEnabled,
        'fresh': fresh,
        'recorded_days': days,
        'high_social_days': socialDays,
        'late_use_days': lateDays,
        'average_social_minutes': socialMinutes,
        'average_late_night_minutes': lateMinutes
      };
}

class SleepInsights {
  SleepInsights.fromJson(Map<String, dynamic> json)
      : asOf = _day(json['as_of']),
        stale = json['stale'] == true,
        safetyPriority = json['safety_priority'] == true,
        windows = _list(json['windows'], 3)
            .map((v) => SleepWindow.fromJson(_map(v)))
            .toList(growable: false),
        correlation = SleepCorrelation.fromJson(_map(json['correlation'])),
        patterns = _list(json['patterns'], 3).cast<String>(),
        activity = json['activity'] as String,
        digital = json['digital'] == null
            ? null
            : SleepDigitalSummary.fromJson(_map(json['digital'])) {
    if (json['version'] != 'm8-observed-v1' ||
        windows.length != 3 ||
        windows.map((w) => w.days).toSet().length != 3 ||
        patterns.any((p) => ![
              'repeated_short_sleep',
              'less_sleep_than_previous_period',
              'variable_sleep_timing'
            ].contains(p)) ||
        !['crisis', 'body_scan', 'box_breathing'].contains(activity) ||
        (safetyPriority && activity != 'crisis')) {
      throw const FormatException('Unsupported sleep insights');
    }
  }
  final String asOf, activity;
  final bool stale, safetyPriority;
  final List<SleepWindow> windows;
  final List<String> patterns;
  final SleepCorrelation correlation;
  final SleepDigitalSummary? digital;
  Map<String, dynamic> toJson() => {
        'version': 'm8-observed-v1',
        'as_of': asOf,
        'stale': stale,
        'safety_priority': safetyPriority,
        'windows': windows.map((w) => w.toJson()).toList(),
        'correlation': correlation.toJson(),
        'patterns': patterns,
        'activity': activity,
        'digital': digital?.toJson()
      };
}

class SleepDashboard {
  SleepDashboard.fromJson(Map<String, dynamic> json)
      : records = _list(json['records'], 30)
            .map((r) => SleepRecord.fromJson(_map(r)))
            .toList(growable: false),
        average = _number(_map(json['summary'])['average_minutes'], 1, 1440),
        nights = _count(_map(json['summary'])['recorded_nights'], 30),
        insights = json['insights'] == null
            ? null
            : SleepInsights.fromJson(_map(json['insights']));
  final List<SleepRecord> records;
  final double? average;
  final int nights;
  final SleepInsights? insights;
  Map<String, dynamic> toJson() => {
        'records': records.map((r) => r.toJson()).toList(),
        'summary': {'average_minutes': average, 'recorded_nights': nights},
        'insights': insights?.toJson()
      };
}
