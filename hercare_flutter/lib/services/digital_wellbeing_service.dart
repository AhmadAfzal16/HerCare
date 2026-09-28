import 'package:flutter/services.dart';
import '../data/services/api_service.dart';

class DigitalWellbeingService {
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
    final response = await ApiService().get('/sleep');
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<void> saveSleep(
      {required DateTime bedtime,
      required DateTime wake,
      required int awakeMinutes,
      required int quality,
      required int awakenings}) async {
    final date =
        '${wake.year}-${wake.month.toString().padLeft(2, '0')}-${wake.day.toString().padLeft(2, '0')}';
    await ApiService().client.put('/sleep', data: {
      'sleep_date': date,
      'bedtime': bedtime.toUtc().toIso8601String(),
      'wake_time': wake.toUtc().toIso8601String(),
      'awake_minutes': awakeMinutes,
      'quality': quality,
      'awakenings': awakenings,
      'timezone_offset_minutes': -wake.timeZoneOffset.inMinutes,
    });
  }
}
