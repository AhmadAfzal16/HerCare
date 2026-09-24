import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/screening_models.dart';

void main() {
  test('screening assessment safely parses PostgreSQL numeric fields', () {
    final assessment = ScreeningAssessment.fromJson({
      'id': 'assessment-id',
      'instrument_type': 'epds',
      'instrument_version': 'v1',
      'scoring_version': 'v1',
      'language': 'en',
      'status': 'completed',
      'total_score': '13',
      'risk_level': 'high',
      'self_harm_positive': false,
      'started_at': '2026-09-24T00:00:00.000Z',
      'completed_at': '2026-09-24T00:03:00.000Z',
      'updated_at': '2026-09-24T00:03:00.000Z',
      'answers': [
        {'question_number': '1', 'option_index': '2'},
      ],
    });

    expect(assessment.totalScore, 13);
    expect(assessment.answers, {1: 2});
    expect(assessment.riskLevel, 'high');
  });

  test('instrument parsing preserves server scoring options', () {
    final instrument = ScreeningInstrument.fromJson({
      'type': 'epds',
      'name': 'EPDS',
      'version': 'v1',
      'scoring_version': 'v1',
      'timeframe_days': 7,
      'max_score': 30,
      'crisis_question': 10,
      'questions': [
        {
          'number': 1,
          'text_en': 'Question',
          'text_ur': 'سوال',
          'options': [
            {'index': 0, 'text_en': 'Answer', 'text_ur': 'جواب', 'score': 0},
          ],
        },
      ],
    });

    expect(instrument.questions.single.options.single.score, 0);
    expect(instrument.crisisQuestion, 10);
  });
}
