import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/mood_models.dart';
import '../data/services/api_service.dart';
import '../data/services/local_storage_service.dart';

class MoodService {
  MoodService({ApiService? api, LocalStorageService? storage})
      : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  static const _pendingCheckinsKey = 'pending_mood_checkins_v1';
  static const _pendingJournalsKey = 'pending_private_journals_v1';

  final ApiService _api;
  final LocalStorageService _storage;

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
      final response = await _api.get(
        '/mood/today',
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
    required int energyLevel,
    required int sleepQuality,
    required int socialSupport,
    String? clientRequestId,
  }) async {
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
      );
      return MoodCheckin.fromJson(
          response.data['data'] as Map<String, dynamic>);
    } on DioException catch (error) {
      if (_isOffline(error)) {
        await _enqueue(_pendingCheckinsKey, payload,
            replaceDate: payload['entry_date'] as String);
        return MoodCheckin(
          id: payload['client_request_id'] as String,
          entryDate: date,
          moodRating: moodRating,
          energyLevel: energyLevel,
          sleepQuality: sleepQuality,
          socialSupport: socialSupport,
          compositeScore: moodRating * .4 +
              energyLevel * .2 +
              sleepQuality * .2 +
              socialSupport * .2,
          isSynced: false,
        );
      }
      throw _error(error);
    }
  }

  Future<List<MoodCheckin>> getHistory({int limit = 30}) async {
    try {
      final response = await _api.get(
        '/mood/history',
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
      final response = await _api.get(
        '/mood/summary',
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
    final payload = <String, dynamic>{
      'content': content,
      'checkin_id': checkinId,
      'client_request_id': requestId(),
    };
    try {
      return await _sendJournal(payload);
    } on DioException catch (error) {
      if (_isOffline(error)) {
        await _enqueue(_pendingJournalsKey, payload);
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
    final response = await _api.post('/mood/journals', data: payload);
    return JournalEntry.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<List<JournalEntry>> getJournals({int limit = 30}) async {
    try {
      final response = await _api.get(
        '/mood/journals',
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
      final response = await _api.post('/mood/journals/search', data: {
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
      await _api.delete('/mood/journals/$id');
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<JournalEntry> uploadVoiceJournal({
    required String path,
    required String language,
    String? checkinId,
  }) async {
    final file = File(path);
    final size = await file.length();
    try {
      final initialized = await _api.post('/mood/voice/initialize', data: {
        'size_bytes': size,
        'language': language,
        'checkin_id': checkinId,
        'client_request_id': requestId(),
      });
      final data = initialized.data['data'] as Map<String, dynamic>;
      final uploadUrl = data['uploadUrl'] as String;
      final headers = Map<String, dynamic>.from(data['headers'] as Map);
      await Dio().put<void>(
        uploadUrl,
        data: file.openRead(),
        options: Options(
          headers: {...headers, Headers.contentLengthHeader: size},
          contentType: 'audio/wav',
        ),
      );
      final completed = await _api.post('/mood/voice/${data['id']}/complete');
      return JournalEntry.fromJson(
        completed.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw _error(error);
    }
  }

  Future<void> syncPending() async {
    final checkins = await _readQueue(_pendingCheckinsKey);
    final unsyncedCheckins = <Map<String, dynamic>>[];
    for (var index = 0; index < checkins.length; index += 1) {
      final payload = checkins[index];
      try {
        final synced = await saveCheckin(
          date: DateTime.parse(payload['entry_date'] as String),
          moodRating: payload['mood_rating'] as int,
          energyLevel: payload['energy_level'] as int,
          sleepQuality: payload['sleep_quality'] as int,
          socialSupport: payload['social_support'] as int,
          clientRequestId: payload['client_request_id'] as String,
        );
        if (!synced.isSynced) {
          unsyncedCheckins.addAll(checkins.sublist(index));
          break;
        }
      } catch (_) {
        unsyncedCheckins.addAll(checkins.sublist(index));
        break;
      }
    }
    await _writeQueue(_pendingCheckinsKey, unsyncedCheckins);

    final journals = await _readQueue(_pendingJournalsKey);
    final unsyncedJournals = <Map<String, dynamic>>[];
    for (var index = 0; index < journals.length; index += 1) {
      final payload = journals[index];
      try {
        await _sendJournal(payload);
      } catch (_) {
        unsyncedJournals.addAll(journals.sublist(index));
        break;
      }
    }
    await _writeQueue(_pendingJournalsKey, unsyncedJournals);
  }

  Future<void> _enqueue(
    String key,
    Map<String, dynamic> payload, {
    String? replaceDate,
  }) async {
    final queue = await _readQueue(key);
    if (replaceDate != null) {
      queue.removeWhere((item) => item['entry_date'] == replaceDate);
    }
    queue.add(payload);
    if (queue.length > 10) queue.removeAt(0);
    await _writeQueue(key, queue);
  }

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
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final message = body['message'];
      if (message is String) return Exception(message);
    }
    return Exception(_isOffline(error)
        ? 'HerCare is offline. Your private entry is safely queued.'
        : 'Could not complete this request. Please try again.');
  }
}
