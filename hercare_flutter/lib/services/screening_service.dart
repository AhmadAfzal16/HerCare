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
  String? _accountId;
  void bindAccount(String? id) => _accountId = id;
  Options get _options => Options(headers: {
        if (_accountId != null) 'X-Screening-Account-Id': _accountId,
      });
  String get _draftKey => _accountId == null
      ? _activeDraftKey
      : 'screening_draft_v2:${Uri.encodeComponent(_api.client.options.baseUrl)}:$_accountId';

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

  Future<ScreeningInstrument> getInstrument(String type,
      {String? version}) async {
    try {
      final response = await _api.client.get('/screening/instruments/$type',
          options: _options,
          queryParameters: version == null ? null : {'version': version});
      return ScreeningInstrument.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<List<ScheduledScreening>> getSchedule() async {
    try {
      final response =
          await _api.client.get('/screening/schedule', options: _options);
      return (response.data['data'] as List<dynamic>)
          .map((value) =>
              ScheduledScreening.fromJson(value as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (error) {
      throw Exception(_isOffline(error)
          ? 'Could not refresh your tests. Check your connection and retry.'
          : 'Could not load your test schedule. Please retry.');
    }
  }

  Future<ScreeningAssessment> start({
    required String instrumentType,
    required String language,
  }) async {
    try {
      final response = await _api.client
          .post('/screening/assessments', options: _options, data: {
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
      final response = await _api.client
          .get('/screening/assessments/$id', options: _options);
      return ScreeningAssessment.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> saveDraft(String assessmentId, Map<int, int> answers) async {
    final payload = _answerPayload(answers);
    try {
      await _api.client.put(
        '/screening/assessments/$assessmentId/draft',
        options: _options,
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
    final draftKey = _draftKey;
    try {
      final response = await _api.client.post(
        '/screening/assessments/$assessmentId/submit',
        options: _options,
        data: {'answers': _answerPayload(answers)},
      );
      await _storage.deleteSecureString(draftKey);
      return ScreeningAssessment.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<ScreeningAssessment?> getLatest({String type = 'epds'}) async {
    try {
      final response = await _api.client.get(
        '/screening/assessments/latest',
        options: _options,
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
      final response = await _api.client.get(
        '/screening/assessments/history',
        options: _options,
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
      final response = await _api.client.get(
        '/screening/reminder',
        options: _options,
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
        _draftKey,
        jsonEncode({
          'assessment_id': id,
          'answers': answers.map((key, value) => MapEntry('$key', value)),
        }),
      );

  Future<({String id, Map<int, int> answers})?> readLocalDraft() async {
    final key = _draftKey;
    final raw = await _storage.getSecureString(key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final answers = (data['answers'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
      );
      return (id: data['assessment_id'] as String, answers: answers);
    } catch (_) {
      await _storage.deleteSecureString(key);
      return null;
    }
  }

  Future<void> clearLocalDraft() => _storage.deleteSecureString(_draftKey);

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
