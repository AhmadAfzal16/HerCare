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

  test('a brief mood check-in keeps unanswered details null', () {
    final checkin = MoodCheckin.fromJson({
      'id': 'brief-id',
      'entry_date': '2026-09-24',
      'mood_rating': 4,
      'energy_level': null,
      'sleep_quality': null,
      'social_support': null,
      'composite_score': '4.00',
    });

    expect(checkin.energyLevel, isNull);
    expect(checkin.sleepQuality, isNull);
    expect(checkin.socialSupport, isNull);
    expect(checkin.compositeScore, 4);
  });

  test('private voice journal exposes playback metadata without text', () {
    final entry = JournalEntry.fromJson({
      'id': 'voice-id',
      'entry_type': 'voice',
      'language': 'ur',
      'has_audio': true,
      'voice_content_type': 'audio/wav',
      'contains_danger': false,
      'created_at': '2026-10-05T12:00:00Z',
    });
    expect(entry.hasAudio, isTrue);
    expect(entry.voiceContentType, 'audio/wav');
    expect(entry.content, isNull);
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
