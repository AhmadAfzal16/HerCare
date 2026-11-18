import 'package:dio/dio.dart';
import '../data/services/api_service.dart';

class PrivacySettings {
  const PrivacySettings(
      {required this.basic, required this.guardian, required this.telemetry});
  final bool basic, guardian, telemetry;
  factory PrivacySettings.fromJson(dynamic data) {
    if (data is! Map ||
        data['consent_tier1'] is! bool ||
        data['consent_tier2'] is! bool ||
        data['consent_tier3'] is! bool) {
      throw const FormatException('Invalid privacy settings');
    }
    return PrivacySettings(
        basic: data['consent_tier1'],
        guardian: data['consent_tier2'],
        telemetry: data['consent_tier3']);
  }
}

class PrivacyService {
  PrivacyService({Dio? client}) : _client = client ?? ApiService().client;
  final Dio _client;
  Future<PrivacySettings> read(String accountId) => _request(accountId);
  Future<PrivacySettings> update(String accountId, String field, bool value) {
    if (!['consent_tier2', 'consent_tier3'].contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    return _request(accountId, data: {field: value});
  }

  Future<PrivacySettings> _request(String accountId,
      {Map<String, bool>? data}) async {
    final options = Options(headers: {'X-Privacy-Account-Id': accountId});
    final response = data == null
        ? await _client.get('/onboarding/consent', options: options)
        : await _client.patch('/onboarding/consent',
            data: data, options: options);
    if (response.data is! Map || response.data['success'] != true) {
      throw const FormatException('Invalid privacy response');
    }
    return PrivacySettings.fromJson(response.data['data']);
  }
}
