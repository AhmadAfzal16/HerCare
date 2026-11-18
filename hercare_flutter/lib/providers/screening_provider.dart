import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/screening_models.dart';
import '../services/screening_service.dart';

class ScreeningProvider extends ChangeNotifier {
  ScreeningProvider({ScreeningService? service})
      : _service = service ?? ScreeningService();

  final ScreeningService _service;
  ScreeningInstrument? _instrument;
  ScreeningAssessment? _current;
  ScreeningAssessment? _latest;
  ScreeningReminder? _reminder;
  List<ScreeningAssessment> _history = const [];
  String _historyType = 'epds';
  int _historyRequest = 0;
  final Map<int, int> _answers = {};
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _overviewLoaded = false;
  bool _overviewLoading = false;
  Future<void> _draftSync = Future<void>.value();
  Future<void> _localSync = Future<void>.value();
  DateTime? _overviewAt;
  int _generation = 0;
  bool _disposed = false;
  bool _bound = false;
  String? _accountId;
  String? _error;

  ScreeningInstrument? get instrument => _instrument;
  ScreeningAssessment? get current => _current;
  ScreeningAssessment? get latest => _latest;
  ScreeningReminder? get reminder => _reminder;
  List<ScreeningAssessment> get history => List.unmodifiable(_history);
  Map<int, int> get answers => Map.unmodifiable(_answers);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get overviewLoaded => _overviewLoaded;
  bool get overviewLoading => _overviewLoading;
  String? get error => _error;
  bool get isComplete =>
      _instrument != null && _answers.length == _instrument!.questions.length;

  bool _valid(int generation) => !_disposed && generation == _generation;
  bool get _available => !_disposed && (!_bound || _accountId != null);

  void bindAccount(String? accountId) {
    if (_bound && _accountId == accountId) return;
    _bound = true;
    _accountId = accountId;
    _generation++;
    _service.bindAccount(accountId);
    _instrument = null;
    _current = null;
    _latest = null;
    _reminder = null;
    _history = const [];
    _historyType = 'epds';
    _historyRequest++;
    _answers.clear();
    _error = null;
    _overviewAt = null;
    _overviewLoaded = _overviewLoading = _isLoading = _isSubmitting = false;
    notifyListeners();
  }

  Future<void> loadOverview({bool force = false}) async {
    if (!_available ||
        _overviewLoading ||
        (!force &&
            _overviewAt != null &&
            DateTime.now().difference(_overviewAt!) <
                const Duration(minutes: 2))) {
      return;
    }
    final generation = _generation;
    _overviewLoading = true;
    final historyRequest = _historyRequest;
    try {
      final values = await Future.wait([
        _service.getLatest(),
        _service.getHistory(limit: 12),
        _service.getReminder(),
      ]);
      if (!_valid(generation)) return;
      _latest = values[0] as ScreeningAssessment?;
      if (_historyType == 'epds' && historyRequest == _historyRequest) {
        _history = values[1] as List<ScreeningAssessment>;
      }
      _reminder = values[2] as ScreeningReminder;
      _overviewLoaded = true;
      _overviewAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Home remains usable when the screening summary cannot be refreshed.
    } finally {
      if (_valid(generation)) _overviewLoading = false;
    }
  }

  Future<bool> initialize({
    required String language,
    String instrumentType = 'epds',
    String? assessmentId,
  }) async {
    if (!_available || _isLoading || _isSubmitting) return false;
    final generation = _generation;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _draftSync;
      await _localSync;
      if (!_valid(generation)) return false;
      _current = null;
      _answers.clear();
      // Revalidate a server draft from the hub, including ownership and status.
      if (assessmentId != null) {
        final draft = await _service.getAssessment(assessmentId);
        if (!_valid(generation)) return false;
        if (draft.status != 'draft' || draft.instrumentType != instrumentType) {
          throw Exception('This draft is no longer available. Refresh Tests.');
        }
        _current = draft;
        _answers
          ..clear()
          ..addAll(draft.answers);
      }
      final local = await _service.readLocalDraft();
      if (!_valid(generation)) return false;
      if (local != null) {
        try {
          final restored = await _service.getAssessment(local.id);
          if (!_valid(generation)) return false;
          if (restored.status == 'draft' &&
              restored.instrumentType == instrumentType &&
              (assessmentId == null || assessmentId == restored.id)) {
            _current = restored;
            _answers
              ..clear()
              ..addAll(local.answers);
          } else if (restored.status != 'draft') {
            await _service.clearLocalDraft();
          }
        } catch (_) {
          // A transport failure must not erase saved answers.
          rethrow;
        }
      }
      if (!_valid(generation)) return false;
      if (_current == null) {
        final started = await _service.start(
            instrumentType: instrumentType, language: language);
        if (!_valid(generation)) return false;
        _current = started;
      }
      if (_instrument?.type != instrumentType ||
          _instrument?.version != _current!.instrumentVersion) {
        final instrument = await _service.getInstrument(instrumentType,
            version: _current!.instrumentVersion);
        if (!_valid(generation)) return false;
        _instrument = instrument;
      }
      if (instrumentType == 'epds') {
        await loadOverview();
      } else {
        await loadHistory(type: instrumentType);
      }
      return _valid(generation);
    } catch (error) {
      if (_valid(generation)) _error = _message(error);
      return false;
    } finally {
      if (_valid(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> chooseAnswer(int questionNumber, int optionIndex) async {
    if (!_available || _current == null || _isSubmitting) return;
    final generation = _generation;
    _answers[questionNumber] = optionIndex;
    final id = _current!.id;
    final answers = Map<int, int>.of(_answers);
    notifyListeners();
    _localSync = _localSync.then((_) async {
      if (!_valid(generation)) return;
      try {
        await _service.saveLocalDraft(id, answers);
      } catch (_) {
        if (_valid(generation)) {
          _error =
              'Device storage is unavailable. Keep this test open and retry.';
          notifyListeners();
        }
      }
    });
    // Immutable snapshots prevent a queued save from reading another test's
    // answers after navigation. Each save is serialized before submission.
    final localWrite = _localSync;
    _draftSync = _draftSync.then((_) async {
      await localWrite;
      if (!_valid(generation)) return;
      try {
        await _service.saveDraft(id, answers);
      } catch (_) {
        // Keep the encrypted local draft for a later retry.
      }
    });
    await localWrite;
  }

  Future<ScreeningAssessment?> submit() async {
    if (!_available || _current == null || !isComplete || _isSubmitting) {
      return null;
    }
    final generation = _generation;
    final id = _current!.id;
    final answers = Map<int, int>.of(_answers);
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      await _draftSync;
      if (!_valid(generation)) return null;
      final result = await _service.submit(id, answers);
      if (!_valid(generation)) return null;
      _current = result;
      if (result.instrumentType == _historyType) {
        _history = [result, ..._history.where((item) => item.id != result.id)];
      }
      if (result.instrumentType == 'epds') {
        _latest = result;
        _reminder = ScreeningReminder(
          instrumentType: result.instrumentType,
          due: false,
          dueAt: DateTime.now().add(const Duration(days: 7)),
        );
      }
      return result;
    } catch (error) {
      if (_valid(generation)) _error = _message(error);
      return null;
    } finally {
      if (_valid(generation)) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadHistory({String type = 'epds'}) async {
    if (!_available) return;
    final generation = _generation;
    final request = ++_historyRequest;
    if (_historyType != type) {
      _historyType = type;
      _history = const [];
      notifyListeners();
    }
    try {
      final history = await _service.getHistory(type: type, limit: 20);
      if (!_valid(generation) || request != _historyRequest) return;
      _history = history;
      notifyListeners();
    } catch (error) {
      if (!_valid(generation) || request != _historyRequest) return;
      _error = _message(error);
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
