import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/models/therapy_models.dart';
import '../data/services/api_service.dart';
import '../data/services/local_storage_service.dart';
import 'mood_service.dart';

class TherapyService {
  TherapyService({ApiService? api, LocalStorageService? storage})
      : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  static const _pendingKey = 'pending_therapy_sessions_v1';
  final ApiService _api;
  final LocalStorageService _storage;

  Future<TherapyRecommendation?> recommendation() async {
    try {
      final response = await _api.get('/therapy/recommendation');
      return TherapyRecommendation.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      if (_isOffline(error)) return null;
      throw _error(error);
    }
  }

  Future<TherapySummary?> summary() async {
    try {
      final response = await _api.get('/therapy/summary');
      return TherapySummary.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      if (_isOffline(error)) return null;
      throw _error(error);
    }
  }

  Future<List<TherapySession>> history({int limit = 30}) async {
    try {
      final response = await _api
          .get('/therapy/sessions', queryParameters: {'limit': limit});
      return (response.data['data'] as List<dynamic>)
          .map(
              (value) => TherapySession.fromJson(value as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      if (_isOffline(error)) return const [];
      throw _error(error);
    }
  }

  Future<TherapySession> record({
    required String type,
    required String activityId,
    required int durationSeconds,
    int? moodBefore,
    int? moodAfter,
    bool completed = true,
  }) async {
    final payload = <String, dynamic>{
      'activity_type': type,
      'activity_id': activityId,
      'duration_seconds': durationSeconds.clamp(1, 7200),
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      'completed': completed,
      'client_request_id': MoodService.requestId(),
    };
    try {
      return await _send(payload);
    } on DioException catch (error) {
      if (!_isOffline(error)) throw _error(error);
      await _enqueue(payload);
      return TherapySession(
        id: payload['client_request_id'] as String,
        activityType: type,
        activityId: activityId,
        durationSeconds: durationSeconds,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        completed: completed,
        completedAt: DateTime.now(),
        isSynced: false,
      );
    }
  }

  Future<void> syncPending() async {
    final raw = await _storage.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return;
    final pending = (jsonDecode(raw) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final remaining = <Map<String, dynamic>>[];
    for (final item in pending) {
      try {
        await _send(item);
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        if (_isOffline(error) || status >= 500) remaining.add(item);
      } catch (_) {
        // Invalid queued records are discarded rather than retried forever.
      }
    }
    await _storage.setString(_pendingKey, jsonEncode(remaining));
  }

  Future<TherapySession> _send(Map<String, dynamic> payload) async {
    final response = await _api.post('/therapy/sessions', data: payload);
    return TherapySession.fromJson(
        response.data['data'] as Map<String, dynamic>);
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final raw = await _storage.getString(_pendingKey);
    final items = raw == null || raw.isEmpty
        ? <dynamic>[]
        : jsonDecode(raw) as List<dynamic>;
    items.add(payload);
    if (items.length > 100) items.removeRange(0, items.length - 100);
    await _storage.setString(_pendingKey, jsonEncode(items));
  }

  bool _isOffline(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  Exception _error(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['message'] is String) {
      return Exception(body['message']);
    }
    return Exception('Could not update activity progress. Please try again.');
  }
}
