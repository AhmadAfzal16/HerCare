import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../data/models/therapy_models.dart';
import '../data/services/api_service.dart';
import '../data/services/local_storage_service.dart';
import 'mood_service.dart';

class TherapyAccountException implements Exception {
  @override
  String toString() => 'Your account changed. Reopen this activity.';
}

class TherapyAccessException implements Exception {
  @override
  String toString() =>
      'Please sign in and review your consent to save activity progress.';
}

class TherapyQueueException implements Exception {
  TherapyQueueException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TherapyPendingIssue {
  const TherapyPendingIssue(
      {required this.requestId,
      required this.activityId,
      required this.completedAt,
      required this.statusCode});
  final String requestId, activityId;
  final DateTime completedAt;
  final int statusCode;
  String get reason => statusCode == 409
      ? 'This save conflicts with a previous request. It was retained, not duplicated.'
      : 'This record was not accepted. It may be invalid or older than 90 days.';
  String get reasonUr => statusCode == 409
      ? 'یہ ریکارڈ پچھلی درخواست سے مختلف ہے۔ اسے محفوظ رکھا گیا ہے، دوبارہ شامل نہیں کیا گیا۔'
      : 'یہ ریکارڈ قبول نہیں ہوا۔ ممکن ہے یہ نامعتبر ہو یا 90 دن سے پرانا ہو۔';
}

/// Private requests and a bounded, encrypted, owner-specific outbox.
/// The old ownerless SharedPreferences queue is deliberately never replayed.
class TherapyService {
  TherapyService({ApiService? api, LocalStorageService? storage})
      : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  final ApiService _api;
  final LocalStorageService _storage;
  String? _accountId;
  bool _bound = false, _offline = false;
  int _generation = 0;
  Future<void> _queueTail = Future.value();
  Future<void>? _sync;
  int? _syncGeneration;
  String? _syncOrigin;
  String? _syncWarning;
  List<TherapyPendingIssue> _pendingIssues = const [];

  bool get isOffline => _offline;
  String? get syncWarning => _syncWarning;
  List<TherapyPendingIssue> get pendingIssues =>
      List.unmodifiable(_pendingIssues);
  void bindAccount(String? id) {
    if (_bound && _accountId == id) return;
    _bound = true;
    _accountId = id;
    _generation++;
    _offline = false;
    _syncWarning = null;
    _pendingIssues = const [];
  }

  String get _origin => _api.client.options.baseUrl;
  void _check(int generation, String origin) {
    if (generation != _generation ||
        origin != _origin ||
        (_bound && _accountId == null)) {
      throw TherapyAccountException();
    }
  }

  Options get _privateOptions => Options(headers: {
        'Cache-Control': 'no-store',
        if (_accountId != null) 'X-Therapy-Account-Id': _accountId,
      });

  String? _queueKey(String origin) => _accountId == null
      ? null
      : 'pending_therapy_sessions_v2:${base64Url.encode(utf8.encode(jsonEncode([
              origin,
              _accountId
            ])))}';

  Future<T> _queueOperation<T>(Future<T> Function() action) {
    final result = _queueTail.then((_) => action());
    _queueTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<TherapyRecommendation?> recommendation() async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    try {
      final response = await _api.client
          .get('/therapy/recommendation', options: _privateOptions);
      _check(generation, origin);
      _offline = false;
      return TherapyRecommendation.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      _check(generation, origin);
      if (_isOffline(error)) {
        _offline = true;
        return null;
      }
      throw _error(error);
    }
  }

  Future<TherapySummary?> summary() async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    try {
      final response =
          await _api.client.get('/therapy/summary', options: _privateOptions);
      _check(generation, origin);
      _offline = false;
      return TherapySummary.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      _check(generation, origin);
      if (_isOffline(error)) {
        _offline = true;
        return null;
      }
      throw _error(error);
    }
  }

  Future<List<TherapySession>> history({int limit = 30}) async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    try {
      final response = await _api.client.get('/therapy/sessions',
          options: _privateOptions,
          queryParameters: {'limit': limit.clamp(1, 100)});
      _check(generation, origin);
      _offline = false;
      return (response.data['data'] as List<dynamic>)
          .map(
              (value) => TherapySession.fromJson(value as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      _check(generation, origin);
      if (_isOffline(error)) {
        _offline = true;
        final key = _queueKey(origin);
        if (key == null || kIsWeb) return const [];
        final pending = await _queueOperation(() => _readQueue(key));
        _check(generation, origin);
        return pending.reversed.take(limit.clamp(1, 100)).map((item) {
          final payload = item['payload'] as Map<String, dynamic>;
          return TherapySession(
            id: payload['client_request_id'] as String,
            activityType: payload['activity_type'] as String,
            activityId: payload['activity_id'] as String,
            durationSeconds: payload['duration_seconds'] as int,
            moodBefore: payload['mood_before'] as int?,
            moodAfter: payload['mood_after'] as int?,
            breathingParticipation:
                payload['breathing_participation'] as String?,
            measures: TherapyMeasures.fromJson(payload['measures']),
            completed: payload['completed'] as bool,
            completedAt:
                DateTime.parse(payload['client_completed_at'] as String),
            isSynced: false,
          );
        }).toList();
      }
      throw _error(error);
    }
  }

  Future<TherapySession> record({
    required String type,
    required String activityId,
    required int durationSeconds,
    int? moodBefore,
    int? moodAfter,
    String? breathingParticipation,
    bool completed = true,
    String? clientRequestId,
    DateTime? clientCompletedAt,
    TherapyMeasures? measures,
  }) async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    final key = _queueKey(origin);
    final measureJson = measures?.toJson();
    final payload = <String, dynamic>{
      if (measureJson != null && measureJson.isNotEmpty)
        'measures': measureJson,
      'activity_type': type,
      'activity_id': activityId,
      'duration_seconds': durationSeconds.clamp(1, 7200),
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      if (breathingParticipation != null)
        'breathing_participation': breathingParticipation,
      'completed': completed,
      'client_request_id': clientRequestId ?? MoodService.requestId(),
      'client_completed_at':
          (clientCompletedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    _validatePayload(payload);
    try {
      final session = await _send(payload, generation, origin);
      if (key != null && !kIsWeb) {
        try {
          await _acknowledge(
              key, payload['client_request_id'] as String, generation, origin);
        } on TherapyQueueException {
          // The server acknowledgement is valid even if unrelated old local
          // storage is corrupt. Keep that storage and disclose the sync issue.
          _syncWarning =
              'Activity saved on the server. Older offline storage could not be read safely and was retained.';
        }
      }
      _check(generation, origin);
      return session;
    } on DioException catch (error) {
      _check(generation, origin);
      if (!_isOffline(error)) throw _error(error);
      _offline = true;
      if (kIsWeb || key == null) {
        throw TherapyQueueException(
            'Connection unavailable. Progress was not saved. Reconnect and retry.');
      }
      final recordedAt =
          DateTime.parse(payload['client_completed_at'] as String);
      await _enqueue(key, payload, recordedAt, generation, origin);
      _check(generation, origin);
      return TherapySession(
        id: payload['client_request_id'] as String,
        activityType: type,
        activityId: activityId,
        durationSeconds: payload['duration_seconds'] as int,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        breathingParticipation: breathingParticipation,
        measures: TherapyMeasures.fromJson(payload['measures']),
        completed: completed,
        completedAt: recordedAt,
        isSynced: false,
      );
    }
  }

  Future<void> syncPending() async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    final key = _queueKey(origin);
    if (key == null || kIsWeb) return;
    if (_sync != null &&
        _syncGeneration == generation &&
        _syncOrigin == origin) {
      return _sync!;
    }
    _syncGeneration = generation;
    _syncOrigin = origin;
    final work = _syncPendingFor(key, generation, origin);
    _sync = work;
    try {
      await work;
    } finally {
      if (_syncGeneration == generation && _syncOrigin == origin) _sync = null;
    }
  }

  Future<void> _syncPendingFor(
      String key, int generation, String origin) async {
    _syncWarning = null;
    final pending = await _queueOperation(() => _readQueue(key));
    for (final item in pending) {
      _check(generation, origin);
      if (item['rejection_status'] != null) continue;
      final payload = Map<String, dynamic>.from(item['payload'] as Map);
      try {
        await _send(payload, generation, origin);
        await _acknowledge(
            key, payload['client_request_id'] as String, generation, origin);
      } on DioException catch (error) {
        _check(generation, origin);
        final mapped = _error(error);
        if (mapped is TherapyAccessException ||
            mapped is TherapyAccountException) {
          _pendingIssues = const [];
          _syncWarning = null;
          throw mapped;
        }
        if (_isOffline(error)) {
          _offline = true;
          _syncWarning =
              'Some activity progress is still stored on this phone. Reconnect to sync it.';
          break;
        }
        final status = error.response?.statusCode;
        if ([400, 409, 422].contains(status)) {
          await _markRejected(key, payload['client_request_id'] as String,
              status!, generation, origin);
          continue;
        }
        _syncWarning =
            'Some activity progress could not sync yet. It is retained; try again later.';
        break;
      } on TherapyAccountException {
        rethrow;
      } catch (_) {
        // An invalid acknowledgement cannot prove that a record was saved.
        _syncWarning =
            'A save could not be confirmed. Its original request is retained for a safe retry.';
        break;
      }
    }
    _check(generation, origin);
    await _refreshIssues(key, generation, origin);
    if (_pendingIssues.isNotEmpty) {
      _syncWarning =
          '${_pendingIssues.length} unsent activity record(s) need review. Other valid records can still sync.';
    }
  }

  Future<void> _refreshIssues(String key, int generation, String origin) async {
    final queue = await _queueOperation(() => _readQueue(key));
    _check(generation, origin);
    _pendingIssues =
        queue.where((item) => item['rejection_status'] != null).map((item) {
      final payload = item['payload'] as Map<String, dynamic>;
      return TherapyPendingIssue(
        requestId: payload['client_request_id'] as String,
        activityId: payload['activity_id'] as String,
        completedAt: DateTime.parse(payload['client_completed_at'] as String),
        statusCode: item['rejection_status'] as int,
      );
    }).toList();
  }

  Future<void> _markRejected(
          String key, String id, int status, int generation, String origin) =>
      _queueOperation(() async {
        _check(generation, origin);
        final queue = await _readQueue(key);
        _check(generation, origin);
        for (final item in queue) {
          if ((item['payload'] as Map)['client_request_id'] == id) {
            item['rejection_status'] = status;
            item['rejected_at'] = DateTime.now().toUtc().toIso8601String();
          }
        }
        await _writeQueue(key, queue);
      });

  /// The caller must confirm deletion and pass the owner captured by that UI.
  /// Only a rejected local record is removable; server history is untouched.
  Future<void> discardPending(String id,
      {required String expectedAccountId}) async {
    await _recoverPending(id, expectedAccountId, discard: true);
  }

  Future<void> retryPending(String id,
      {required String expectedAccountId}) async {
    await _recoverPending(id, expectedAccountId, discard: false);
    await syncPending();
  }

  Future<void> _recoverPending(String id, String expectedAccountId,
      {required bool discard}) async {
    final generation = _generation, origin = _origin;
    _check(generation, origin);
    if (_accountId == null || expectedAccountId != _accountId) {
      throw TherapyAccountException();
    }
    final key = _queueKey(origin);
    if (key == null || kIsWeb) throw TherapyAccountException();
    await _queueOperation(() async {
      _check(generation, origin);
      final queue = await _readQueue(key);
      _check(generation, origin);
      final index = queue.indexWhere((item) =>
          (item['payload'] as Map)['client_request_id'] == id &&
          item['rejection_status'] != null);
      if (index < 0) {
        throw TherapyQueueException(
            'This rejected local record is no longer available. Refresh activity history.');
      }
      if (discard) {
        queue.removeAt(index);
      } else {
        queue[index].remove('rejection_status');
        queue[index].remove('rejected_at');
      }
      await _writeQueue(key, queue);
    });
    await _refreshIssues(key, generation, origin);
    _syncWarning = _pendingIssues.isEmpty
        ? null
        : '${_pendingIssues.length} unsent activity record(s) need review.';
  }

  Future<TherapySession> _send(
      Map<String, dynamic> payload, int generation, String origin) async {
    _check(generation, origin);
    final response = await _api.client
        .post('/therapy/sessions', data: payload, options: _privateOptions);
    _check(generation, origin);
    final body = response.data;
    final data = body is Map ? body['data'] : null;
    if (body is! Map ||
        body['success'] != true ||
        data is! Map<String, dynamic> ||
        data['id'] is! String ||
        (data['id'] as String).isEmpty) {
      throw const FormatException(
          'Invalid activity progress response. Retry the same save.');
    }
    _offline = false;
    return TherapySession.fromJson(data);
  }

  Future<void> _acknowledge(
          String key, String id, int generation, String origin) =>
      _queueOperation(() async {
        _check(generation, origin);
        final queue = await _readQueue(key);
        _check(generation, origin);
        queue.removeWhere(
            (item) => (item['payload'] as Map)['client_request_id'] == id);
        await _writeQueue(key, queue);
      });

  Future<void> _enqueue(String key, Map<String, dynamic> payload,
          DateTime recordedAt, int generation, String origin) =>
      _queueOperation(() async {
        _check(generation, origin);
        final queue = await _readQueue(key);
        _check(generation, origin);
        final matches = queue.where((item) =>
            (item['payload'] as Map)['client_request_id'] ==
            payload['client_request_id']);
        if (matches.isNotEmpty) {
          if (jsonEncode(matches.first['payload']) != jsonEncode(payload)) {
            throw TherapyQueueException(
                'This save has already been queued. Retry without changing its ratings.');
          }
          return;
        }
        if (queue.length >= 100) {
          throw TherapyQueueException(
              'Offline activity storage is full. Reconnect before saving another activity.');
        }
        queue.add({
          'payload': payload,
          'recorded_at': recordedAt.toUtc().toIso8601String()
        });
        await _writeQueue(key, queue);
      });

  Future<List<Map<String, dynamic>>> _readQueue(String key) async {
    final raw = await _storage.getSecureString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      if (utf8.encode(raw).length > 64 * 1024) {
        throw const FormatException();
      }
      final parsed = jsonDecode(raw);
      if (parsed is! List || parsed.length > 100) {
        throw const FormatException();
      }
      return parsed.map((value) {
        final item = Map<String, dynamic>.from(value as Map);
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        _validatePayload(payload);
        if (DateTime.tryParse('${item['recorded_at']}') == null) {
          throw const FormatException();
        }
        if (item['rejection_status'] != null &&
            (item['rejection_status'] is! int ||
                ![400, 409, 422].contains(item['rejection_status']) ||
                DateTime.tryParse('${item['rejected_at']}') == null)) {
          throw const FormatException();
        }
        return <String, dynamic>{
          'payload': payload,
          'recorded_at': item['recorded_at'],
          if (item['rejection_status'] != null)
            'rejection_status': item['rejection_status'],
          if (item['rejection_status'] != null)
            'rejected_at': item['rejected_at'],
        };
      }).toList();
    } catch (_) {
      throw TherapyQueueException(
          'Offline activity storage could not be read safely. It was not replayed or deleted.');
    }
  }

  Future<void> _writeQueue(String key, List<Map<String, dynamic>> queue) async {
    if (queue.isEmpty) {
      await _storage.deleteSecureString(key);
      return;
    }
    final raw = jsonEncode(queue);
    if (utf8.encode(raw).length > 64 * 1024) {
      throw TherapyQueueException(
          'Offline activity storage is full. Reconnect before saving another activity.');
    }
    await _storage.setSecureString(key, raw);
  }

  void _validatePayload(Map<String, dynamic> payload) {
    const fields = {
      'activity_type',
      'activity_id',
      'duration_seconds',
      'mood_before',
      'mood_after',
      'breathing_participation',
      'measures',
      'completed',
      'client_request_id',
      'client_completed_at',
    };
    final measures = payload['measures'];
    if (measures != null &&
        (!TherapyMeasures.validJson(measures) ||
            !{'breathing', 'meditation'}.contains(payload['activity_type']))) {
      throw const FormatException('Invalid practice measures.');
    }
    final duration = payload['duration_seconds'];
    if (payload.keys.any((key) => !fields.contains(key)) ||
        !{'breathing', 'meditation', 'cbt', 'game'}
            .contains(payload['activity_type']) ||
        payload['activity_id'] is! String ||
        !RegExp(r'^[a-z0-9_]{1,64}$')
            .hasMatch(payload['activity_id'] as String) ||
        duration is! int ||
        duration < 1 ||
        duration > 7200 ||
        payload['completed'] is! bool ||
        payload['client_completed_at'] is! String ||
        DateTime.tryParse(payload['client_completed_at'] as String) == null ||
        payload['client_request_id'] is! String ||
        !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                caseSensitive: false)
            .hasMatch(payload['client_request_id'] as String)) {
      throw const FormatException('Invalid activity progress.');
    }
    for (final field in ['mood_before', 'mood_after']) {
      final value = payload[field];
      if (value != null && (value is! int || value < 1 || value > 5)) {
        throw const FormatException('Mood ratings must be between 1 and 5.');
      }
    }
    final participation = payload['breathing_participation'];
    if (participation != null &&
        (payload['activity_type'] != 'breathing' ||
            !{'most_cues', 'some_cues', 'stopped_early'}
                .contains(participation))) {
      throw const FormatException('Invalid breathing participation response.');
    }
  }

  bool _isOffline(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  Exception _error(DioException error) {
    if ([401, 403].contains(error.response?.statusCode)) {
      return TherapyAccessException();
    }
    final body = error.response?.data;
    if (error.response?.statusCode == 409 &&
        body is Map &&
        (body['code'] == 'ACCOUNT_CHANGED' ||
            (body['message'] is String &&
                (body['message'] as String)
                    .startsWith('Your account changed.')))) {
      return TherapyAccountException();
    }
    return Exception(
        'Could not save activity progress. Your previous save ID is kept; please retry.');
  }
}
