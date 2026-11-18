import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/crisis_models.dart';
import '../data/services/api_service.dart';

class CrisisAccessException implements Exception {
  const CrisisAccessException();
}

class CrisisConflictException implements Exception {
  const CrisisConflictException();
}

/// Private support is deliberately not cached by the HTTP client.
/// Mutations are never queued or automatically retried by this service.
class CrisisService {
  CrisisService({ApiService? api, this.expectedAccountId})
      : _api = api ?? ApiService();
  final ApiService _api;
  final String? expectedAccountId;
  static const _timeout = Duration(seconds: 8);

  Options get _options =>
      Options(receiveTimeout: _timeout, sendTimeout: _timeout, headers: {
        'Cache-Control': 'no-store',
        if (expectedAccountId != null) 'X-Crisis-Account-Id': expectedAccountId,
      });

  Future<T> _request<T>(Future<Response<dynamic>> Function() call,
      T Function(Map<String, dynamic>) parse) async {
    try {
      final response = await call();
      final body = response.data;
      final data = body is Map<String, dynamic> ? body['data'] : null;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid crisis response');
      }
      return parse(data);
    } on DioException catch (error) {
      if ([401, 403].contains(error.response?.statusCode)) {
        throw const CrisisAccessException();
      }
      if (error.response?.statusCode == 409) {
        throw const CrisisConflictException();
      }
      // Never expose private fields, server exception details, or request body.
      throw Exception('Crisis support server unavailable. Use direct help.');
    }
  }

  Future<CrisisSupport> support() => _request(
      () => _api.client.get('/crisis/support', options: _options),
      CrisisSupport.fromJson);

  Future<CrisisCatalog> contacts() => _request(
      () => _api.client.get('/crisis/contacts', options: _options),
      CrisisCatalog.fromJson);

  Future<CrisisPlan> savePlan(CrisisPlan plan) => _request(
      () => _api.client
          .put('/crisis/plan', data: plan.toRequest(), options: _options),
      CrisisPlan.fromJson);

  Future<CrisisPlan> deletePlan(int version) => _request(
      () => _api.client.delete('/crisis/plan',
          queryParameters: {'version': version}, options: _options),
      CrisisPlan.fromJson);

  Future<CrisisGuardian?>
      guardianSafety(String linkId, bool confirmed) =>
          _request(
              () => _api.client.put('/crisis/guardian-safety',
                  options: _options,
                  data: {'guardian_link_id': linkId, 'confirmed': confirmed}),
              (data) => data['guardian'] == null
                  ? null
                  : CrisisGuardian.fromJson(data['guardian']));

  Future<CrisisEvent> requestHelp({
    required String requestId,
    required bool notifyGuardian,
    String? guardianLinkId,
  }) =>
      _request(
          () => _api.client.post('/crisis/events', options: _options, data: {
                'client_request_id': requestId,
                'notify_guardian': notifyGuardian,
                if (guardianLinkId != null) 'guardian_link_id': guardianLinkId,
              }),
          CrisisEvent.fromJson);

  Future<CrisisEvent> updateEvent(String id,
          {required String status, String? outcome}) =>
      _request(
          () =>
              _api.client.patch('/crisis/events/$id', options: _options, data: {
                'status': status,
                if (outcome != null) 'outcome': outcome,
              }),
          CrisisEvent.fromJson);

  Future<CrisisHistory> history({String? before}) => _request(
      () => _api.client.get('/crisis/events',
          options: _options,
          queryParameters: {'limit': 20, if (before != null) 'before': before}),
      CrisisHistory.fromJson);

  static String requestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
