import 'package:flutter/foundation.dart';

import '../data/models/therapy_models.dart';
import '../services/therapy_service.dart';

class TherapyProvider extends ChangeNotifier {
  TherapyProvider({TherapyService? service})
      : _service = service ?? TherapyService();

  final TherapyService _service;
  TherapyRecommendation? _recommendation;
  TherapySummary? _summary;
  List<TherapySession> _history = const [];
  bool _loading = false;
  String? _error;

  TherapyRecommendation? get recommendation => _recommendation;
  TherapySummary? get summary => _summary;
  List<TherapySession> get history => List.unmodifiable(_history);
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.syncPending();
      final values = await Future.wait([
        _service.recommendation(),
        _service.summary(),
        _service.history(limit: 20),
      ]);
      _recommendation = values[0] as TherapyRecommendation?;
      _summary = values[1] as TherapySummary?;
      _history = values[2] as List<TherapySession>;
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<TherapySession?> complete({
    required String type,
    required String activityId,
    required int durationSeconds,
    int? moodBefore,
    int? moodAfter,
  }) async {
    try {
      final session = await _service.record(
        type: type,
        activityId: activityId,
        durationSeconds: durationSeconds,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
      );
      _history = [session, ..._history];
      notifyListeners();
      return session;
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }
}
