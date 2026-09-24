import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/screening_models.dart';
import '../data/services/api_service.dart';
import '../data/services/local_storage_service.dart';

class ScreeningService {
  ScreeningService({ApiService? api, LocalStorageService? storage})
      : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  static const _activeDraftKey = 'active_screening_draft_v1';
  final ApiService _api;
  final LocalStorageService _storage;

  static String requestId() {
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

  Future<ScreeningInstrument> getInstrument(String type) async {
    try {
      final response = await _api.get('/screening/instruments/$type');
      return ScreeningInstrument.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ScreeningAssessment> start({
    required String instrumentType,
    required String language,
  }) async {
    try {
      final response = await _api.post('/screening/assessments', data: {
        'instrument_type': instrumentType,
        'language': language,
        'client_request_id': requestId(),
      });
      return ScreeningAssessment.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ScreeningAssessment> getAssessment(String id) async {
    try {
      final response = await _api.get('/screening/assessments/$id');
      return ScreeningAssessment.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> saveDraft(String assessmentId, Map<int, int> answers) async {
    final payload = _answerPayload(answers);
    await saveLocalDraft(assessmentId, answers);
    try {
      await _api.client.put(
        '/screening/assessments/$assessmentId/draft',
        data: {'answers': payload},
      );
    } on DioException catch (error) {
      if (!_isOffline(error)) throw _error(error);
    }
  }

  Future<ScreeningAssessment> submit(
    String assessmentId,
    Map<int, int> answers,
  ) async {
    try {
      final response = await _api.post(
        '/screening/assessments/$assessmentId/submit',
        data: {'answers': _answerPayload(answers)},
      );
      await clearLocalDraft();
      return ScreeningAssessment.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ScreeningAssessment?> getLatest({String type = 'epds'}) async {
    try {
      final response = await _api.get(
        '/screening/assessments/latest',
        queryParameters: {'instrument': type},
      );
      final data = response.data['data'];
      return data is Map<String, dynamic>
          ? ScreeningAssessment.fromJson(data)
          : null;
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<List<ScreeningAssessment>> getHistory({
    String type = 'epds',
    int limit = 20,
  }) async {
    try {
      final response = await _api.get(
        '/screening/assessments/history',
        queryParameters: {'instrument': type, 'limit': limit},
      );
      return (response.data['data'] as List<dynamic>)
          .map((value) => ScreeningAssessment.fromJson(
                value as Map<String, dynamic>,
              ))
          .toList(growable: false);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ScreeningReminder> getReminder({String type = 'epds'}) async {
    try {
      final response = await _api.get(
        '/screening/reminder',
        queryParameters: {'instrument': type},
      );
      return ScreeningReminder.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> saveLocalDraft(String id, Map<int, int> answers) =>
      _storage.setSecureString(
        _activeDraftKey,
        jsonEncode({
          'assessment_id': id,
          'answers': answers.map((key, value) => MapEntry('$key', value)),
        }),
      );

  Future<({String id, Map<int, int> answers})?> readLocalDraft() async {
    final raw = await _storage.getSecureString(_activeDraftKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final answers = (data['answers'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
      );
      return (id: data['assessment_id'] as String, answers: answers);
    } catch (_) {
      await clearLocalDraft();
      return null;
    }
  }

  Future<void> clearLocalDraft() =>
      _storage.deleteSecureString(_activeDraftKey);

  List<Map<String, int>> _answerPayload(Map<int, int> answers) =>
      answers.entries
          .map((entry) => {
                'question_number': entry.key,
                'option_index': entry.value,
              })
          .toList(growable: false)
        ..sort((left, right) =>
            left['question_number']!.compareTo(right['question_number']!));

  bool _isOffline(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  Exception _error(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['message'] is String) {
      return Exception(body['message'] as String);
    }
    return Exception(_isOffline(error)
        ? 'Could not connect to HerCare. Your answers remain safely saved on this device.'
        : 'Could not complete the screening request. Please try again.');
  }
}
