import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/therapy_models.dart';

void main() {
  test('therapy summary safely parses PostgreSQL numeric values', () {
    final summary = TherapySummary.fromJson({
      'total_sessions': 4,
      'completed_sessions': 3,
      'total_seconds': 540,
      'avg_mood_change': '1.25',
    });
    expect(summary.completedSessions, 3);
    expect(summary.totalSeconds, 540);
    expect(summary.averageMoodChange, 1.25);
  });

  test('catalog resolves every supported lightweight activity', () {
    expect(TherapyCatalog.activities.length, 16);
    expect(TherapyCatalog.byId('cyclic_sighing').type, 'breathing');
    expect(TherapyCatalog.byId('resonance_breathing').type, 'breathing');
    expect(TherapyCatalog.byId('memory_match').type, 'game');
    expect(TherapyCatalog.byId('breathing_478').type, 'breathing');
    expect(TherapyCatalog.byId('domestic_puzzle').type, 'game');
  });

  test('partial activities and invalid ratings never imply mood improvement',
      () {
    final partial = TherapySession.fromJson({
      'duration_seconds': '22',
      'mood_before': '1',
      'mood_after': '5',
      'completed': false,
    });
    expect(partial.durationSeconds, 22);
    expect(partial.moodChange, isNull);
    final invalid = TherapySession.fromJson({
      'duration_seconds': 'NaN',
      'mood_before': '1.5',
      'mood_after': '9',
    });
    expect(invalid.durationSeconds, 0);
    expect(invalid.moodBefore, isNull);
    expect(invalid.moodAfter, isNull);
    expect(invalid.completed, isFalse);
    expect(invalid.completedAt.millisecondsSinceEpoch, 0);
    expect(
        TherapySummary.fromJson({'avg_mood_change': 'Infinity'})
            .averageMoodChange,
        isNull);
  });
}
