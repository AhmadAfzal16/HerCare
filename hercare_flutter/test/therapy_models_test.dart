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
    expect(TherapyCatalog.activities.length, 13);
    expect(TherapyCatalog.byId('memory_match').type, 'game');
    expect(TherapyCatalog.byId('breathing_478').type, 'breathing');
  });
}
