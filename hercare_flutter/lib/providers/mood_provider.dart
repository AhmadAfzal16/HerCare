import 'package:flutter/foundation.dart';
import '../data/models/mood_models.dart';
import '../services/mood_service.dart';

class MoodProvider extends ChangeNotifier {
  MoodProvider({MoodService? service}) : _service = service ?? MoodService();
  final MoodService _service;
  String? _accountId;
  bool _bound = false, _disposed = false;
  int _generation = 0, _activeRequests = 0, _searchGeneration = 0;
  String? _error;
  MoodCheckin? _today;
  MoodSummary? _summary;
  List<MoodCheckin> _history = const [];
  List<JournalEntry> _journals = const [];

  bool get isLoading => _activeRequests > 0;
  String? get error => _error;
  MoodCheckin? get today => _today;
  MoodSummary? get summary => _summary;
  List<MoodCheckin> get history => List.unmodifiable(_history);
  List<JournalEntry> get journals => List.unmodifiable(_journals);

  void bindAccount(String? id) {
    if (_bound && _accountId == id) return;
    _bound = true;
    _accountId = id;
    _generation++;
    _searchGeneration++;
    _activeRequests = 0;
    _today = null;
    _summary = null;
    _error = null;
    _history = const [];
    _journals = const [];
    _service.bindAccount(id);
    notifyListeners();
  }

  bool _same(int generation) =>
      !_disposed &&
      generation == _generation &&
      (!_bound || _accountId != null);
  int _start() {
    final generation = _generation;
    if (!_same(generation)) return generation;
    _activeRequests++;
    _error = null;
    notifyListeners();
    return generation;
  }

  void _finish(int generation) {
    if (!_same(generation)) return;
    _activeRequests = (_activeRequests - 1).clamp(0, 1000);
    notifyListeners();
  }

  Future<void> load({bool includeJournals = false}) async {
    final generation = _start();
    if (!_same(generation)) return;
    try {
      await _service.syncPending();
      if (!_same(generation)) return;
      final values = await Future.wait([
        _service.getToday(DateTime.now()),
        _service.getHistory(limit: 30),
        _service.getSummary(),
        if (includeJournals) _service.getJournals()
      ]);
      if (!_same(generation)) return;
      _today = values[0] as MoodCheckin?;
      _history = values[1] as List<MoodCheckin>;
      _summary = values[2] as MoodSummary;
      if (includeJournals) _journals = values[3] as List<JournalEntry>;
    } catch (error) {
      if (_same(generation)) _error = _message(error);
    } finally {
      _finish(generation);
    }
  }

  Future<bool> saveCheckin(
      {required int moodRating,
      int? energyLevel,
      int? sleepQuality,
      int? socialSupport}) async {
    final generation = _start();
    if (!_same(generation)) return false;
    try {
      final entry = await _service.saveCheckin(
          date: DateTime.now(),
          moodRating: moodRating,
          energyLevel: energyLevel,
          sleepQuality: sleepQuality,
          socialSupport: socialSupport);
      if (!_same(generation)) return false;
      _today = entry;
      _history = [
        entry,
        ..._history.where((value) =>
            MoodService.dateKey(value.entryDate) !=
            MoodService.dateKey(entry.entryDate))
      ];
      if (entry.isSynced) {
        try {
          final summary = await _service.getSummary();
          if (_same(generation)) _summary = summary;
        } catch (_) {
          if (_same(generation)) _summary = null;
        }
      }
      return _same(generation);
    } catch (error) {
      if (_same(generation)) _error = _message(error);
      return false;
    } finally {
      _finish(generation);
    }
  }

  Future<JournalEntry?> saveJournal(String content) async {
    final generation = _start();
    if (!_same(generation)) return null;
    try {
      final entry = await _service.createJournal(content,
          checkinId: _today?.isSynced == true ? _today?.id : null);
      if (!_same(generation)) return null;
      _journals = [entry, ..._journals.where((value) => value.id != entry.id)];
      return entry;
    } catch (error) {
      if (_same(generation)) _error = _message(error);
      return null;
    } finally {
      _finish(generation);
    }
  }

  Future<JournalEntry?> saveVoiceJournal(
      {required String path,
      required String language,
      String? clientRequestId}) async {
    final generation = _start();
    if (!_same(generation)) return null;
    try {
      final entry = await _service.uploadVoiceJournal(
          path: path,
          language: language,
          checkinId: _today?.isSynced == true ? _today?.id : null,
          clientRequestId: clientRequestId);
      if (!_same(generation)) return null;
      _journals = [entry, ..._journals.where((value) => value.id != entry.id)];
      return entry;
    } catch (error) {
      if (_same(generation)) _error = _message(error);
      return null;
    } finally {
      _finish(generation);
    }
  }

  Future<Uint8List> loadVoiceAudio(String id) => _service.getVoiceAudio(id);
  Future<void> searchJournals(String query) async {
    final search = ++_searchGeneration;
    final generation = _start();
    if (!_same(generation)) return;
    try {
      final entries = query.trim().isEmpty
          ? await _service.getJournals()
          : await _service.searchJournals(query.trim());
      if (_same(generation) && search == _searchGeneration) _journals = entries;
    } catch (error) {
      if (_same(generation) && search == _searchGeneration) {
        _error = _message(error);
      }
    } finally {
      _finish(generation);
    }
  }

  Future<bool> deleteJournal(String id) async {
    final generation = _start();
    if (!_same(generation)) return false;
    try {
      await _service.deleteJournal(id);
      if (!_same(generation)) return false;
      _journals = _journals.where((entry) => entry.id != id).toList();
      return true;
    } catch (error) {
      if (_same(generation)) _error = _message(error);
      return false;
    } finally {
      _finish(generation);
    }
  }

  void clearError() {
    if (_disposed) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
