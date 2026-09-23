import 'package:flutter/foundation.dart';

import '../data/models/mood_models.dart';
import '../services/mood_service.dart';

class MoodProvider extends ChangeNotifier {
  MoodProvider({MoodService? service}) : _service = service ?? MoodService();

  final MoodService _service;
  bool _isLoading = false;
  String? _error;
  MoodCheckin? _today;
  MoodSummary? _summary;
  List<MoodCheckin> _history = const [];
  List<JournalEntry> _journals = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  MoodCheckin? get today => _today;
  MoodSummary? get summary => _summary;
  List<MoodCheckin> get history => List.unmodifiable(_history);
  List<JournalEntry> get journals => List.unmodifiable(_journals);

  Future<void> load({bool includeJournals = false}) async {
    _start();
    try {
      await _service.syncPending();
      final values = await Future.wait([
        _service.getToday(DateTime.now()),
        _service.getHistory(limit: 30),
        _service.getSummary(),
        if (includeJournals) _service.getJournals(),
      ]);
      _today = values[0] as MoodCheckin?;
      _history = values[1] as List<MoodCheckin>;
      _summary = values[2] as MoodSummary;
      if (includeJournals) _journals = values[3] as List<JournalEntry>;
    } catch (error) {
      _error = _message(error);
    } finally {
      _finish();
    }
  }

  Future<bool> saveCheckin({
    required int moodRating,
    required int energyLevel,
    required int sleepQuality,
    required int socialSupport,
  }) async {
    _start();
    try {
      _today = await _service.saveCheckin(
        date: DateTime.now(),
        moodRating: moodRating,
        energyLevel: energyLevel,
        sleepQuality: sleepQuality,
        socialSupport: socialSupport,
      );
      _history = [
        _today!,
        ..._history.where(
          (entry) =>
              MoodService.dateKey(entry.entryDate) !=
              MoodService.dateKey(DateTime.now()),
        ),
      ];
      if (_today!.isSynced) _summary = await _service.getSummary();
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _finish();
    }
  }

  Future<JournalEntry?> saveJournal(String content) async {
    _start();
    try {
      final entry =
          await _service.createJournal(content, checkinId: _today?.id);
      _journals = [entry, ..._journals];
      return entry;
    } catch (error) {
      _error = _message(error);
      return null;
    } finally {
      _finish();
    }
  }

  Future<JournalEntry?> saveVoiceJournal({
    required String path,
    required String language,
  }) async {
    _start();
    try {
      final entry = await _service.uploadVoiceJournal(
        path: path,
        language: language,
        checkinId: _today?.id,
      );
      _journals = [entry, ..._journals];
      return entry;
    } catch (error) {
      _error = _message(error);
      return null;
    } finally {
      _finish();
    }
  }

  Future<void> searchJournals(String query) async {
    _start();
    try {
      _journals = query.trim().isEmpty
          ? await _service.getJournals()
          : await _service.searchJournals(query.trim());
    } catch (error) {
      _error = _message(error);
    } finally {
      _finish();
    }
  }

  Future<bool> deleteJournal(String id) async {
    _start();
    try {
      await _service.deleteJournal(id);
      _journals = _journals.where((entry) => entry.id != id).toList();
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _finish();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _start() {
    _isLoading = true;
    _error = null;
    notifyListeners();
  }

  void _finish() {
    _isLoading = false;
    notifyListeners();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
