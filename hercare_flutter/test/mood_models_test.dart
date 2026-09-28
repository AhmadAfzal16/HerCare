import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/mood_models.dart';

void main() {
  test('mood check-in accepts PostgreSQL numeric strings', () {
    final checkin = MoodCheckin.fromJson({
      'id': 'checkin-id',
      'entry_date': '2026-09-24',
      'mood_rating': 5,
      'energy_level': 4,
      'sleep_quality': 3,
      'social_support': 2,
      'composite_score': '3.80',
    });

    expect(checkin.compositeScore, 3.8);
    expect(checkin.moodRating, 5);
  });

  test('mood summary accepts numeric strings defensively', () {
    final summary = MoodSummary.fromJson({
      'start': '2026-09-22',
      'end': '2026-09-28',
      'entries': '2',
      'average': '3.75',
      'mood_trend': ['3.5', 4],
    });

    expect(summary.entries, 2);
    expect(summary.average, 3.75);
    expect(summary.trend, [3.5, 4.0]);
  });
}
