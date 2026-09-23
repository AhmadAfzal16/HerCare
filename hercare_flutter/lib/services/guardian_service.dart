import 'package:dio/dio.dart';

import '../data/services/api_service.dart';

class GuardianService {
  GuardianService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<T> _request<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DioException catch (error) {
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
        final response = await _api.post('/guardian/invite');
        return _body(response);
      });

  Future<Map<String, dynamic>> refreshInvite() => _request(() async {
        final response = await _api.post('/guardian/invite/refresh');
        return _body(response);
      });

  Future<Map<String, dynamic>> acceptInvite({
    required String inviteCode,
    required String guardianName,
    required String relationship,
  }) =>
      _request(() async {
        final response = await _api.post('/guardian/accept', data: {
          'invite_code': inviteCode.toUpperCase(),
          'guardian_name': guardianName,
          'relationship': relationship,
        });
        return _body(response);
      });

  Future<Map<String, dynamic>?> getLink() => _request(() async {
        final response = await _api.get('/guardian/link');
        return _body(response)['data'] as Map<String, dynamic>?;
      });

  Future<void> revokeLink() => _request(() async {
        await _api.delete('/guardian/link');
      });

  Future<Map<String, dynamic>> getDashboard({String lang = 'en'}) =>
      _request(() async {
        final response = await _api.get(
          '/guardian/dashboard',
          queryParameters: {'lang': lang},
        );
        return _body(response)['data'] as Map<String, dynamic>;
      });

  Future<List<dynamic>> getReports({String type = 'weekly', int limit = 7}) =>
      _request(() async {
        final response = await _api.get(
          '/guardian/reports',
          queryParameters: {'type': type, 'limit': limit},
        );
        return _body(response)['data'] as List<dynamic>;
      });

  Future<Map<String, dynamic>> getReportById(String reportId) =>
      _request(() async {
        final response = await _api.get('/guardian/reports/$reportId');
        return _body(response)['data'] as Map<String, dynamic>;
      });

  Future<Map<String, dynamic>> generateReport({
    required String periodType,
    String? anchorDate,
  }) =>
      _request(() async {
        final response = await _api.post('/guardian/reports/generate', data: {
          'period_type': periodType,
          if (anchorDate != null) 'anchor_date': anchorDate,
        });
        return _body(response);
      });

  Future<List<dynamic>> getAlerts({int limit = 20}) => _request(() async {
        final response = await _api.get(
          '/guardian/alerts',
          queryParameters: {'limit': limit},
        );
        return _body(response)['data'] as List<dynamic>;
      });

  Future<void> markAlertsRead({List<String> alertIds = const []}) =>
      _request(() async {
        await _api
            .patch('/guardian/alerts/read', data: {'alert_ids': alertIds});
      });
}
