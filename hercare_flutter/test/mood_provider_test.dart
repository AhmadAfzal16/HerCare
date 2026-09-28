import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/mood_models.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/services/mood_service.dart';

void main() {
  test('a failed summary refresh does not turn a saved check-in into failure',
      () async {
    final provider = MoodProvider(service: _Mood());
    expect(
        await provider.saveCheckin(
            moodRating: 3, energyLevel: 3, sleepQuality: 3, socialSupport: 3),
        isTrue);
    expect(provider.today?.id, 'saved');
    expect(provider.error, isNull);
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });
}

class _Mood extends MoodService {
  @override
  Future<MoodCheckin> saveCheckin(
          {String? clientRequestId,
          required DateTime date,
          required int moodRating,
          required int energyLevel,
          required int sleepQuality,
          required int socialSupport}) async =>
      MoodCheckin(
          id: 'saved',
          entryDate: date,
          moodRating: moodRating,
          energyLevel: energyLevel,
          sleepQuality: sleepQuality,
          socialSupport: socialSupport,
          compositeScore: 3);
  @override
  Future<MoodSummary> getSummary(
          {DateTime? anchorDate, String period = 'weekly'}) async =>
      throw Exception('Offline');
}
