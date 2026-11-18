import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../data/models/risk_models.dart';
import '../data/services/api_service.dart';

class RiskService {
  RiskService({ApiService? api}) : _api = api ?? ApiService();

  static const _channel = MethodChannel('com.hercare/telemetry');
  final ApiService _api;
  String? _accountId;
  int _generation = 0;

  void bindAccount(String? id) {
    if (_accountId == id) return;
    _accountId = id;
    _generation++;
  }

  Options get _options => Options(followRedirects: false, headers: {
        if (_accountId != null) 'X-Risk-Account-Id': _accountId,
      });

  Future<TelemetryPermissions> permissions() async {
    try {
      final platform = await _channel.invokeMethod<String>('platform');
      if (platform != 'android') {
        return const TelemetryPermissions(
          isAndroid: false,
          notificationAccess: false,
          usageAccess: false,
        );
      }
      final results = await Future.wait([
        _channel.invokeMethod<bool>('hasNotificationAccess'),
        _channel.invokeMethod<bool>('hasUsageAccess'),
      ]);
      return TelemetryPermissions(
        isAndroid: true,
        notificationAccess: results[0] ?? false,
        usageAccess: results[1] ?? false,
      );
    } on PlatformException {
      return const TelemetryPermissions(
        isAndroid: false,
        notificationAccess: false,
        usageAccess: false,
      );
    } on MissingPluginException {
      return const TelemetryPermissions(
        isAndroid: false,
        notificationAccess: false,
        usageAccess: false,
      );
    }
  }

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<void> openUsageSettings() =>
      _channel.invokeMethod<void>('openUsageSettings');

  Future<void> setMonitoringEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>(
        'setMonitoringEnabled',
        {'enabled': enabled},
      );
    } on PlatformException {
      // Non-Android platforms remain supported without passive monitoring.
    } on MissingPluginException {
      // Non-Android platforms remain supported without passive monitoring.
    }
  }

  Future<RiskStatus> getStatus() async {
    try {
      final response = await _api.client.get('/risk/status', options: _options);
      return RiskStatus.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<RiskStatus> updateConsent(bool enabled) async {
    try {
      final response = await _api.client.patch(
        '/risk/consent',
        data: {'enabled': enabled},
        options: _options,
      );
      return RiskStatus.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<TelemetrySnapshot> collectAndSync() async {
    final generation = _generation;
    final options = _options;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'collectTelemetry',
      );
      if (raw == null) throw Exception('Telemetry is unavailable.');
      if (generation != _generation) throw StateError('Account changed.');
      final snapshot = TelemetrySnapshot.fromMap(raw);
      await _api.client.post(
        '/risk/telemetry',
        data: snapshot.toApiJson(_requestId()),
        options: options,
      );
      return snapshot;
    } on DioException catch (error) {
      throw _error(error);
    } on PlatformException {
      throw Exception('Passive telemetry is available on Android only.');
    } on MissingPluginException {
      throw Exception('Passive telemetry is available on Android only.');
    }
  }

  Future<RiskPrediction> generatePrediction() async {
    try {
      final response =
          await _api.client.post('/risk/predictions', options: _options);
      return RiskPrediction.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<RiskPrediction?> latest() async {
    try {
      final response =
          await _api.client.get('/risk/predictions/latest', options: _options);
      final data = response.data['data'];
      return data is Map<String, dynamic>
          ? RiskPrediction.fromJson(data)
          : null;
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<Map<String, dynamic>> recovery() async =>
      (await _api.client.get('/risk/recovery', options: _options)).data['data']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> modelContext() async =>
      (await _api.client.get('/risk/context', options: _options)).data['data']
          as Map<String, dynamic>;

  Future<void> saveModelContext(Map<String, dynamic> values) async {
    await _api.client.put('/risk/context', data: values, options: _options);
  }

  Future<Map<String, dynamic>> m4Reports() => _m4Request('GET', '');

  Future<Map<String, dynamic>> saveM4Checkin(
    Map<String, int?> values, {
    required String date,
  }) =>
      _m4Request('PUT', '/context-checkin', data: {...values, 'date': date});

  Future<Map<String, dynamic>> setM4TextConsent(bool enabled) =>
      _m4Request('PUT', '/text-consent', data: {'enabled': enabled});

  Future<Map<String, dynamic>> _m4Request(String method, String path,
      {Map<String, dynamic>? data}) async {
    final options = _options..method = method;
    try {
      final response = await _api.client
          .request('/risk/m4$path', data: data, options: options);
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw const FormatException('Invalid M4 response.');
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<Map<String, dynamic>> researchConsent() async =>
      (await _api.get('/research/consent')).data['data']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> setResearchConsent(bool enabled) async =>
      (await _api.client.put('/research/consent', data: {
        'enabled': enabled,
        'policy_version': 'research-aggregate-v1',
        'timezone': 'Asia/Karachi',
      }))
          .data['data'] as Map<String, dynamic>;

  String _requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final value =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Exception _error(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['message'] is String) {
      return Exception(body['message'] as String);
    }
    return Exception('Could not update risk insights. Please try again.');
  }
}
