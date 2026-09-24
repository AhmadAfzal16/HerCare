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
  final Map<int, int> _answers = {};
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _overviewLoaded = false;
  bool _overviewLoading = false;
  Future<void> _draftSync = Future<void>.value();
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
  String? get error => _error;
  bool get isComplete =>
      _instrument != null && _answers.length == _instrument!.questions.length;

  Future<void> loadOverview() async {
    if (_overviewLoaded || _overviewLoading) return;
    _overviewLoading = true;
    try {
      final values = await Future.wait([
        _service.getLatest(),
        _service.getHistory(limit: 12),
        _service.getReminder(),
      ]);
      _latest = values[0] as ScreeningAssessment?;
      _history = values[1] as List<ScreeningAssessment>;
      _reminder = values[2] as ScreeningReminder;
      _overviewLoaded = true;
      notifyListeners();
    } catch (_) {
      // Home remains usable when the screening summary cannot be refreshed.
    } finally {
      _overviewLoading = false;
    }
  }

  Future<bool> initialize({
    required String language,
    String instrumentType = 'epds',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (_current?.status != 'draft' ||
          _current?.instrumentType != instrumentType) {
        _current = null;
        _answers.clear();
      }
      if (_instrument?.type != instrumentType) {
        _instrument = await _service.getInstrument(instrumentType);
      }
      final local = await _service.readLocalDraft();
      if (local != null) {
        try {
          final restored = await _service.getAssessment(local.id);
          if (restored.status == 'draft' &&
              restored.instrumentType == instrumentType) {
            _current = restored;
            _answers
              ..clear()
              ..addAll(local.answers);
          } else {
            await _service.clearLocalDraft();
          }
        } catch (_) {
          await _service.clearLocalDraft();
        }
      }
      _current ??= await _service.start(
        instrumentType: instrumentType,
        language: language,
      );
      if (instrumentType == 'epds') {
        await loadOverview();
      } else {
        await loadHistory(type: instrumentType);
      }
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> chooseAnswer(int questionNumber, int optionIndex) async {
    if (_current == null) return;
    _answers[questionNumber] = optionIndex;
    notifyListeners();
    await _service.saveLocalDraft(_current!.id, _answers);
    _draftSync = _draftSync.then((_) => _syncDraft());
    unawaited(_draftSync);
  }

  Future<void> _syncDraft() async {
    try {
      if (_current != null) await _service.saveDraft(_current!.id, _answers);
    } catch (_) {
      // The encrypted local draft remains available for a later retry.
    }
  }

  Future<ScreeningAssessment?> submit() async {
    if (_current == null || !isComplete || _isSubmitting) return null;
    _isSubmitting = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.submit(_current!.id, _answers);
      _current = result;
      _history = [result, ..._history.where((item) => item.id != result.id)];
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
      _error = _message(error);
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory({String type = 'epds'}) async {
    try {
      _history = await _service.getHistory(type: type, limit: 20);
      notifyListeners();
    } catch (error) {
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
}
