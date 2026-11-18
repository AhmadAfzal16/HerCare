import 'package:flutter/foundation.dart';

import '../data/models/therapy_models.dart';
import '../services/mood_service.dart';
import '../services/therapy_service.dart';

class TherapyProvider extends ChangeNotifier {
  TherapyProvider({TherapyService? service})
      : _service = service ?? TherapyService();

  final TherapyService _service;
  String? _accountId;
  bool _bound = false, _disposed = false, _offline = false;
  int _generation = 0, _activeRequests = 0, _activeSaves = 0;
  TherapyRecommendation? _recommendation;
  TherapySummary? _summary;
  List<TherapySession> _history = const [];
  String? _error;
  String? _syncWarning;
  List<TherapyPendingIssue> _pendingIssues = const [];
  Future<void>? _load;
  int? _loadGeneration;
  final Map<String, Future<TherapySession?>> _saves = {};
  final Map<String, String> _savedSessionIds = {};
  final Map<String, DateTime> _saveTimes = {};

  String? get accountId => _accountId;
  bool get canUseAccount => !_disposed && (!_bound || _accountId != null);
  TherapyRecommendation? get recommendation => _recommendation;
  TherapySummary? get summary => _summary;
  List<TherapySession> get history => List.unmodifiable(_history);
  bool get isLoading => _activeRequests > 0;
  bool get isSaving => _activeSaves > 0;
  bool get isOffline => _offline;
  String? get syncWarning => _syncWarning;
  List<TherapyPendingIssue> get pendingIssues =>
      List.unmodifiable(_pendingIssues);
  String? get error => _error;

  void bindAccount(String? id) {
    if (_disposed || (_bound && _accountId == id)) return;
    _bound = true;
    _accountId = id;
    _generation++;
    _activeRequests = 0;
    _activeSaves = 0;
    _clearPrivateState();
    _error = null;
    _offline = false;
    _saves.clear();
    _savedSessionIds.clear();
    _saveTimes.clear();
    _service.bindAccount(id);
    notifyListeners();
  }

  void _clearPrivateState() {
    _recommendation = null;
    _summary = null;
    _history = const [];
    _pendingIssues = const [];
    _syncWarning = null;
  }

  bool _same(int generation) => canUseAccount && generation == _generation;

  int _start({bool saving = false}) {
    final generation = _generation;
    if (!_same(generation)) return generation;
    _activeRequests++;
    if (saving) _activeSaves++;
    _error = null;
    notifyListeners();
    return generation;
  }

  void _finish(int generation, {bool saving = false}) {
    if (!_same(generation)) return;
    _activeRequests = (_activeRequests - 1).clamp(0, 1000);
    if (saving) _activeSaves = (_activeSaves - 1).clamp(0, 1000);
    notifyListeners();
  }

  Future<void> load() {
    final generation = _generation;
    if (!_same(generation)) return Future.value();
    if (_load != null && _loadGeneration == generation) return _load!;
    _loadGeneration = generation;
    final work = _loadFor(generation);
    _load = work;
    return work.whenComplete(() {
      if (_loadGeneration == generation) _load = null;
    });
  }

  Future<void> _loadFor(int generation) async {
    _start();
    try {
      String? syncFailure;
      try {
        await _service.syncPending();
      } catch (error) {
        if (error is TherapyAccessException ||
            error is TherapyAccountException) {
          rethrow;
        }
        // Corrupt storage or a retryable sync failure must not block fresh reads.
        syncFailure = _message(error);
      }
      if (!_same(generation)) return;
      final values = await Future.wait([
        _read(_service.recommendation()),
        _read(_service.summary()),
        _read(_service.history(limit: 20)),
      ]);
      if (!_same(generation)) return;
      final errors =
          values.map((value) => value.$2).whereType<Object>().toList();
      for (final error in errors) {
        if (error is TherapyAccessException ||
            error is TherapyAccountException) {
          throw error;
        }
      }
      final recommendation = values[0].$1 as TherapyRecommendation?;
      final summary = values[1].$1 as TherapySummary?;
      final history =
          (values[2].$1 as List<TherapySession>?) ?? const <TherapySession>[];
      // Derive freshness from every result, not a shared flag reset by a racing GET.
      _offline = recommendation == null ||
          summary == null ||
          errors.isNotEmpty ||
          history.any((entry) => !entry.isSynced);
      _syncWarning = _service.syncWarning ?? syncFailure;
      _pendingIssues = _service.pendingIssues;
      if (errors.isNotEmpty) _error = _message(errors.first);
      // A network outage never turns unknown data into an empty clinical record.
      if (recommendation != null) _recommendation = recommendation;
      if (summary != null) _summary = summary;
      if (!_offline) {
        _history = history.take(100).toList();
      } else if (history.isNotEmpty) {
        final ids = history.map((entry) => entry.id).toSet();
        _history = [
          ...history,
          ..._history.where((entry) => !ids.contains(entry.id)),
        ].take(100).toList();
      }
    } catch (error) {
      if (_same(generation)) {
        if (error is TherapyAccessException ||
            error is TherapyAccountException) {
          _clearPrivateState();
        }
        _error = _message(error);
      }
    } finally {
      _finish(generation);
    }
  }

  Future<(Object?, Object?)> _read(Future<Object?> work) async {
    try {
      return (await work, null);
    } catch (error) {
      return (null, error);
    }
  }

  Future<bool> retryPending(String requestId,
          {required String expectedAccountId}) =>
      _recoverPending(requestId, expectedAccountId, discard: false);

  Future<bool> discardPending(String requestId,
          {required String expectedAccountId}) =>
      _recoverPending(requestId, expectedAccountId, discard: true);

  Future<bool> _recoverPending(String requestId, String expectedAccountId,
      {required bool discard}) async {
    final generation = _start();
    if (!_same(generation) || expectedAccountId != _accountId) {
      _finish(generation);
      return false;
    }
    try {
      if (discard) {
        await _service.discardPending(requestId,
            expectedAccountId: expectedAccountId);
      } else {
        await _service.retryPending(requestId,
            expectedAccountId: expectedAccountId);
      }
      if (!_same(generation)) return false;
      _pendingIssues = _service.pendingIssues;
      _syncWarning = _service.syncWarning;
      if (discard) {
        _history = _history
            .where((entry) => entry.id != requestId || entry.isSynced)
            .toList();
      }
      await load();
      return _same(generation);
    } catch (error) {
      if (_same(generation)) {
        if (error is TherapyAccessException ||
            error is TherapyAccountException) {
          _clearPrivateState();
        }
        _error = _message(error);
      }
      return false;
    } finally {
      _finish(generation);
    }
  }

  Future<TherapySession?> complete({
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
  }) {
    final generation = _generation;
    if (!_same(generation)) return Future.value();
    final requestId = clientRequestId ?? MoodService.requestId();
    final existing = _saves[requestId];
    if (existing != null) return existing;
    if (_saves.length >= 200) {
      _error =
          'Too many saves are awaiting confirmation. Wait before trying again.';
      notifyListeners();
      return Future.value();
    }
    final completedAt = _saveTimes.putIfAbsent(
        requestId, () => clientCompletedAt ?? DateTime.now());
    while (_saveTimes.length > 200) {
      final removable =
          _saveTimes.keys.firstWhere((id) => !_saves.containsKey(id));
      _saveTimes.remove(removable);
    }
    final work = _completeFor(generation, requestId,
        type: type,
        activityId: activityId,
        durationSeconds: durationSeconds,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        breathingParticipation: breathingParticipation,
        completed: completed,
        clientCompletedAt: completedAt,
        measures: measures);
    _saves[requestId] = work;
    return work.whenComplete(() {
      if (_same(generation) && identical(_saves[requestId], work)) {
        _saves.remove(requestId);
      }
    });
  }

  Future<TherapySession?> _completeFor(
    int generation,
    String requestId, {
    required String type,
    required String activityId,
    required int durationSeconds,
    int? moodBefore,
    int? moodAfter,
    String? breathingParticipation,
    required bool completed,
    required DateTime clientCompletedAt,
    TherapyMeasures? measures,
  }) async {
    _start(saving: true);
    try {
      final session = await _service.record(
        type: type,
        activityId: activityId,
        durationSeconds: durationSeconds,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        breathingParticipation: breathingParticipation,
        completed: completed,
        clientRequestId: requestId,
        clientCompletedAt: clientCompletedAt,
        measures: measures,
      );
      if (!_same(generation)) return null;
      if (!session.isSynced) _offline = true;
      _syncWarning = _service.syncWarning;
      final oldId = _savedSessionIds[requestId];
      _savedSessionIds[requestId] = session.id;
      while (_savedSessionIds.length > 200) {
        _savedSessionIds.remove(_savedSessionIds.keys.first);
      }
      _history = [
        session,
        ..._history
            .where((value) => value.id != session.id && value.id != oldId)
      ].take(100).toList();
      return session;
    } catch (error) {
      if (_same(generation)) {
        if (error is TherapyAccessException ||
            error is TherapyAccountException) {
          _clearPrivateState();
        }
        _error = _message(error);
      }
      return null;
    } finally {
      _finish(generation, saving: true);
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _service.bindAccount(null);
    super.dispose();
  }
}
