import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../data/models/mood_models.dart';
import '../data/models/voice_transcript.dart';
import '../data/services/api_service.dart';
import '../data/services/local_storage_service.dart';

class MoodAccessException implements Exception {}

class MoodAccountException implements Exception {}

class MoodService {
  MoodService({ApiService? api, LocalStorageService? storage})
      : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  static const _pendingCheckinsKey = 'pending_mood_checkins_v1';
  static const _pendingJournalsKey = 'pending_private_journals_v1';

  final ApiService _api;
  final LocalStorageService _storage;
  String? _accountId;
  int _generation = 0;
  bool _bound = false;
  Future<void> _queueTail = Future.value();
  Future<void>? _sync;
  int? _syncGeneration;
  Future<T> _queueOperation<T>(Future<T> Function() action) {
    final operation = _queueTail.then((_) => action());
    _queueTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  void bindAccount(String? id) {
    if (_bound && _accountId == id) return;
    _bound = true;
    _accountId = id;
    _generation++;
  }

  Options get _privateOptions => Options(headers: {
        'Cache-Control': 'no-store',
        if (_accountId != null) 'X-Mood-Account-Id': _accountId,
      });
  void _check(int generation) {
    if (generation != _generation || (_bound && _accountId == null)) {
      throw MoodAccountException();
    }
  }

  String _key(String base) {
    _check(_generation);
    final origin = _api.client.options.baseUrl;
    return _accountId == null ? base : '$base:$origin:$_accountId';
  }

  Future<VoiceTranscript?> getTranscript(String id) async {
    final generation = _generation;
    _check(generation);
    try {
      final response = await _api.client
          .get('/mood/voice/$id/transcription', options: _privateOptions);
      _check(generation);
      return VoiceTranscript.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      _check(generation);
      if (error.response?.statusCode == 404) return null;
      throw _error(error);
    }
  }

  Future<VoiceTranscript> requestTranscript(String id) async {
    final generation = _generation;
    _check(generation);
    try {
      final response = await _api.client.post('/mood/voice/$id/transcription',
          options: _privateOptions, data: <String, dynamic>{});
      _check(generation);
      return VoiceTranscript.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<bool> confirmTranscript(
      String id, String content, int revision, String requestId) async {
    final generation = _generation;
    _check(generation);
    try {
      final response = await _api.client.put('/mood/voice/$id/transcription',
          options: _privateOptions,
          data: {
            'content': content,
            'revision': revision,
            'client_request_id': requestId
          });
      _check(generation);
      if (response.data['success'] != true ||
          response.data['data']['confirmed'] != true ||
          response.data['data']['contains_danger'] is! bool) {
        throw const FormatException('Invalid confirmation response');
      }
      return response.data['data']['contains_danger'] == true;
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> cancelTranscript(String id) async {
    _check(_generation);
    try {
      await _api.client
          .delete('/mood/voice/$id/transcription', options: _privateOptions);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  static double _compositeScore(
      int mood, int? energy, int? sleep, int? support) {
    final observations = <(int, double)>[(mood, .4)];
    if (energy != null) observations.add((energy, .2));
    if (sleep != null) observations.add((sleep, .2));
    if (support != null) observations.add((support, .2));
    final weight = observations.fold<double>(0, (sum, item) => sum + item.$2);
    final weighted =
        observations.fold<double>(0, (sum, item) => sum + item.$1 * item.$2);
    return double.parse((weighted / weight).toStringAsFixed(2));
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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

  Future<MoodCheckin?> getToday(DateTime date) async {
    try {
      final response = await _api.client.get(
        '/mood/today',
        options: _privateOptions,
        queryParameters: {'date': dateKey(date)},
      );
      final data = response.data['data'];
      return data is Map<String, dynamic> ? MoodCheckin.fromJson(data) : null;
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<MoodCheckin> saveCheckin({
    required DateTime date,
    required int moodRating,
    int? energyLevel,
    int? sleepQuality,
    int? socialSupport,
    String? clientRequestId,
  }) async {
    final generation = _generation;
    _check(generation);
    final queueKey = _key(_pendingCheckinsKey);
    final payload = <String, dynamic>{
      'entry_date': dateKey(date),
      'mood_rating': moodRating,
      'energy_level': energyLevel,
      'sleep_quality': sleepQuality,
      'social_support': socialSupport,
      'client_request_id': clientRequestId ?? requestId(),
    };
    try {
      final response = await _api.client.put(
        '/mood/checkins/${payload['entry_date']}',
        data: payload,
        options: _privateOptions,
      );
      _check(generation);
      return MoodCheckin.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      if (_isOffline(error)) {
        _check(generation);
        await _enqueue(queueKey, payload,
            replaceDate: payload['entry_date'] as String);
        return MoodCheckin(
          id: payload['client_request_id'] as String,
          entryDate: date,
          moodRating: moodRating,
          energyLevel: energyLevel,
          sleepQuality: sleepQuality,
          socialSupport: socialSupport,
          compositeScore: _compositeScore(
              moodRating, energyLevel, sleepQuality, socialSupport),
          isSynced: false,
        );
      }
      throw _error(error);
    }
  }

  Future<List<MoodCheckin>> getHistory({int limit = 30}) async {
    try {
      final response = await _api.client.get(
        '/mood/history',
        options: _privateOptions,
        queryParameters: {'limit': limit},
      );
      return (response.data['data'] as List<dynamic>)
          .map((value) => MoodCheckin.fromJson(value as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<MoodSummary> getSummary({
    String period = 'weekly',
    DateTime? anchorDate,
  }) async {
    try {
      final response = await _api.client.get(
        '/mood/summary',
        options: _privateOptions,
        queryParameters: {
          'period': period,
          'anchor_date': dateKey(anchorDate ?? DateTime.now()),
        },
      );
      return MoodSummary.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<JournalEntry> createJournal(String content,
      {String? checkinId}) async {
    final generation = _generation;
    _check(generation);
    final queueKey = _key(_pendingJournalsKey);
    final payload = <String, dynamic>{
      'content': content,
      'checkin_id': checkinId,
      'client_request_id': requestId(),
    };
    try {
      return await _sendJournal(payload);
    } on DioException catch (error) {
      if (_isOffline(error)) {
        _check(generation);
        await _enqueue(queueKey, payload);
        return JournalEntry(
          id: payload['client_request_id'] as String,
          entryType: 'text',
          language: 'en',
          processingStatus: 'pending',
          content: content,
          containsDanger: false,
          createdAt: DateTime.now(),
          isSynced: false,
        );
      }
      throw _error(error);
    }
  }

  Future<JournalEntry> _sendJournal(Map<String, dynamic> payload) async {
    final response = await _api.client
        .post('/mood/journals', data: payload, options: _privateOptions);
    return JournalEntry.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<JournalEntry>> getJournals({int limit = 30}) async {
    try {
      final response = await _api.client.get(
        '/mood/journals',
        options: _privateOptions,
        queryParameters: {'limit': limit},
      );
      return (response.data['data'] as List<dynamic>)
          .map((value) => JournalEntry.fromJson(value as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<List<JournalEntry>> searchJournals(String search) async {
    try {
      final response = await _api.client
          .post('/mood/journals/search', options: _privateOptions, data: {
        'query': search,
        'limit': 50,
      });
      return (response.data['data'] as List<dynamic>)
          .map((value) => JournalEntry.fromJson(value as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> deleteJournal(String id) async {
    try {
      await _api.client.delete('/mood/journals/$id', options: _privateOptions);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<JournalEntry> uploadVoiceJournal({
    required String path,
    required String language,
    String? checkinId,
    String? clientRequestId,
  }) async {
    final generation = _generation;
    _check(generation);
    final file = File(path);
    final size = await file.length();
    if (size < 1 || size > 4 * 1024 * 1024) {
      throw Exception('Voice note must be smaller than 4 MB.');
    }
    final extension = path.toLowerCase();
    final contentType = extension.endsWith('.wav')
        ? 'audio/wav'
        : extension.endsWith('.m4a') || extension.endsWith('.mp4')
            ? 'audio/mp4'
            : extension.endsWith('.mp3')
                ? 'audio/mpeg'
                : null;
    if (contentType == null) {
      throw Exception('Choose a WAV, M4A, or MP3 voice note.');
    }
    try {
      final bytes = await file.readAsBytes();
      _check(generation);
      final response = await _api.client.post<Map<String, dynamic>>(
        '/mood/voice',
        data: bytes,
        options: Options(
          contentType: contentType,
          sendTimeout: const Duration(seconds: 60),
          headers: {
            ...?_privateOptions.headers,
            'x-journal-language': language,
            'x-client-request-id': clientRequestId ?? requestId(),
            if (checkinId != null) 'x-checkin-id': checkinId,
          },
        ),
      );
      _check(generation);
      return JournalEntry.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<Uint8List> getVoiceAudio(String journalId) async {
    final generation = _generation;
    _check(generation);
    try {
      final response = await _api.client.get<List<int>>(
        '/mood/voice/$journalId/audio',
        options: Options(
            responseType: ResponseType.bytes, headers: _privateOptions.headers),
      );
      _check(generation);
      return Uint8List.fromList(response.data!);
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> syncPending() async {
    final generation = _generation;
    _check(generation);
    if (_sync != null && _syncGeneration == generation) return _sync!;
    _syncGeneration = generation;
    final work = _syncPendingFor(generation);
    _sync = work;
    try {
      await work;
    } finally {
      if (_syncGeneration == generation) _sync = null;
    }
  }

  Future<void> _syncPendingFor(int generation) async {
    final checkinKey = _key(_pendingCheckinsKey);
    final journalKey = _key(_pendingJournalsKey);
    final checkins = await _readQueue(checkinKey);
    for (var index = 0; index < checkins.length; index += 1) {
      _check(generation);
      final payload = checkins[index];
      try {
        final date = payload['entry_date'];
        final response = await _api.client.put('/mood/checkins/$date',
            data: payload, options: _privateOptions);
        if (response.data['success'] != true) break;
        _check(generation);
        await _acknowledge(
            checkinKey, payload['client_request_id'] as String, generation);
      } catch (_) {
        break;
      }
    }
    _check(generation);

    final journals = await _readQueue(journalKey);
    for (var index = 0; index < journals.length; index += 1) {
      _check(generation);
      final payload = journals[index];
      try {
        await _sendJournal(payload);
        _check(generation);
        await _acknowledge(
            journalKey, payload['client_request_id'] as String, generation);
      } catch (_) {
        break;
      }
    }
    _check(generation);
  }

  Future<void> _acknowledge(String key, String id, int generation) =>
      _queueOperation(() async {
        _check(generation);
        final queue = await _readQueue(key);
        _check(generation);
        queue.removeWhere((value) => value['client_request_id'] == id);
        await _writeQueue(key, queue);
      });

  Future<void> _enqueue(
    String key,
    Map<String, dynamic> payload, {
    String? replaceDate,
  }) =>
      _queueOperation(() async {
        final queue = await _readQueue(key);
        if (replaceDate != null) {
          queue.removeWhere((item) => item['entry_date'] == replaceDate);
        }
        queue.add(payload);
        if (queue.length > 10) {
          throw Exception(
              'Your offline draft storage is full. Reconnect before adding another entry.');
        }
        await _writeQueue(key, queue);
      });

  Future<List<Map<String, dynamic>>> _readQueue(String key) async {
    final raw = await _storage.getSecureString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(String key, List<Map<String, dynamic>> queue) async {
    if (queue.isEmpty) {
      await _storage.deleteSecureString(key);
    } else {
      await _storage.setSecureString(key, jsonEncode(queue));
    }
  }

  bool _isOffline(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;

  Exception _error(DioException error) {
    if ([401, 403].contains(error.response?.statusCode)) {
      return MoodAccessException();
    }
    if (error.response?.statusCode == 409) return MoodAccountException();
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is String) return Exception(message);
    }
    return Exception(_isOffline(error)
        ? 'Connection unavailable. Retry; this request was not automatically queued.'
        : 'Could not complete this request. Please try again.');
  }
}
