import 'package:dio/dio.dart';

import '../data/services/api_service.dart';

class GuardianAccessException implements Exception {
  const GuardianAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GuardianService {
  GuardianService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;
  String? _accountId;
  void bindAccount(String? id) => _accountId = id;
  Options get _options => Options(headers: {
        if (_accountId != null) 'X-Guardian-Account-Id': _accountId,
      });

  Future<T> _request<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DioException catch (error) {
      if ([401, 403, 409].contains(error.response?.statusCode)) {
        throw const GuardianAccessException(
            'Guardian access is unavailable. Check your account, link and sharing permission.');
      }
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        if (message is String && message.isNotEmpty) throw Exception(message);
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty) {
          throw Exception(errors.first.toString());
        }
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw Exception('Connection timed out. Please try again.');
        case DioExceptionType.connectionError:
          throw Exception(
              'Could not connect to HerCare. Check your internet connection.');
        default:
          throw Exception('Something went wrong. Please try again.');
      }
    }
  }

  Map<String, dynamic> _body(Response<dynamic> response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('The server returned an invalid response.');
    }
    return data;
  }

  Future<Map<String, dynamic>> generateInvite() => _request(() async {
        final response =
            await _api.client.post('/guardian/invite', options: _options);
        return _body(response);
      });

  Future<Map<String, dynamic>> refreshInvite() => _request(() async {
        final response = await _api.client
            .post('/guardian/invite/refresh', options: _options);
        return _body(response);
      });

  Future<Map<String, dynamic>> acceptInvite({
    required String inviteCode,
    required String guardianName,
    required String relationship,
  }) =>
      _request(() async {
        final response = await _api.client
            .post('/guardian/accept', options: _options, data: {
          'invite_code': inviteCode.toUpperCase(),
          'guardian_name': guardianName,
          'relationship': relationship,
        });
        return _body(response);
      });

  Future<Map<String, dynamic>?> getLink() => _request(() async {
        final response =
            await _api.client.get('/guardian/link', options: _options);
        return _body(response)['data'] as Map<String, dynamic>?;
      });

  Future<void> revokeLink() => _request(() async {
        await _api.client.delete('/guardian/link', options: _options);
      });

  Future<Map<String, dynamic>> getDashboard({String lang = 'en'}) =>
      _request(() async {
        final response = await _api.client.get(
          '/guardian/dashboard',
          options: _options,
          queryParameters: {'lang': lang},
        );
        return _body(response)['data'] as Map<String, dynamic>;
      });

  Future<List<dynamic>> getReports({String type = 'weekly', int limit = 7}) =>
      _request(() async {
        final response = await _api.client.get(
          '/guardian/reports',
          options: _options,
          queryParameters: {'type': type, 'limit': limit},
        );
        return _body(response)['data'] as List<dynamic>;
      });

  Future<Map<String, dynamic>> getWellbeingTrends() => _request(() async {
        final response = await _api.client
            .get('/guardian/wellbeing-trends', options: _options);
        return _body(response)['data'] as Map<String, dynamic>;
      });

  Future<Map<String, dynamic>> getReportById(String reportId) =>
      _request(() async {
        final response = await _api.client
            .get('/guardian/reports/$reportId', options: _options);
        return _body(response)['data'] as Map<String, dynamic>;
      });

  Future<Map<String, dynamic>> generateReport({
    required String periodType,
    String? anchorDate,
  }) =>
      _request(() async {
        final response = await _api.client
            .post('/guardian/reports/generate', options: _options, data: {
          'period_type': periodType,
          if (anchorDate != null) 'anchor_date': anchorDate,
        });
        return _body(response);
      });

  Future<List<dynamic>> getAlerts({int limit = 20}) => _request(() async {
        final response = await _api.client.get(
          '/guardian/alerts',
          options: _options,
          queryParameters: {'limit': limit},
        );
        return _body(response)['data'] as List<dynamic>;
      });

  Future<void> markAlertsRead({List<String> alertIds = const []}) =>
      _request(() async {
        await _api.client.patch('/guardian/alerts/read',
            options: _options, data: {'alert_ids': alertIds});
      });
}
