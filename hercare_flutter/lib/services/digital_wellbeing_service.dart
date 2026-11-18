import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../data/services/api_service.dart';

class SleepAccessException implements Exception {}

class SleepAccountException implements Exception {}

class DigitalWellbeingService {
  DigitalWellbeingService({ApiService? api, this.expectedAccountId})
      : _api = api ?? ApiService();
  final ApiService _api;
  final String? expectedAccountId;
  String get apiOrigin => _api.client.options.baseUrl;
  Options get _options => Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          headers: {
            'Cache-Control': 'no-store',
            if (expectedAccountId != null)
              'X-Sleep-Account-Id': expectedAccountId
          });
  static const channel = MethodChannel('com.hercare/telemetry');

  Future<Map<String, dynamic>> usage() async {
    try {
      if (await channel.invokeMethod<bool>('hasUsageAccess') != true) {
        return {'permission': false, 'supported': true};
      }
      final result = await channel
          .invokeMapMethod<String, dynamic>('collectDigitalWellbeing');
      return {...?result, 'permission': true, 'supported': true};
    } on MissingPluginException {
      return {'permission': false, 'supported': false};
    }
  }

  Future<void> openAccess() => channel.invokeMethod<void>('openUsageSettings');

  Future<Map<String, dynamic>> sleep() async {
    final now = DateTime.now();
    return _privateRequest(
        () => _api.client.get('/sleep', options: _options, queryParameters: {
              'as_of':
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
              'timezone_offset_minutes': -now.timeZoneOffset.inMinutes,
            }));
  }

  Future<void> saveSleep(
      {required DateTime bedtime,
      required DateTime wake,
      required int awakeMinutes,
      required int? quality,
      required int? awakenings,
      int? timezoneOffsetMinutes}) async {
    final offset = timezoneOffsetMinutes ?? -wake.timeZoneOffset.inMinutes;
    final localWake = wake.toUtc().subtract(Duration(minutes: offset));
    final date =
        '${localWake.year}-${localWake.month.toString().padLeft(2, '0')}-${localWake.day.toString().padLeft(2, '0')}';
    await _privateRequest(
        () => _api.client.put('/sleep', options: _options, data: {
              'sleep_date': date,
              'bedtime': bedtime.toUtc().toIso8601String(),
              'wake_time': wake.toUtc().toIso8601String(),
              'awake_minutes': awakeMinutes,
              'quality': quality,
              'awakenings': awakenings,
              'timezone_offset_minutes': offset,
            }));
  }

  Future<Map<String, dynamic>> _privateRequest(
      Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      if (response.data is! Map || response.data['success'] != true) {
        throw const FormatException('Invalid sleep response');
      }
      return Map<String, dynamic>.from(response.data['data'] as Map? ?? {});
    } on DioException catch (error) {
      if ([401, 403].contains(error.response?.statusCode)) {
        throw SleepAccessException();
      }
      if (error.response?.statusCode == 409) throw SleepAccountException();
      throw Exception(
          'Sleep server unavailable. Retry when connected; no automatic upload is queued.');
    }
  }
}
