const test = require('node:test');
const assert = require('node:assert/strict');

const { riskForScore, scoreAnswers } = require('../src/modules/screening/screening.scoring');

function fixture(type) {
  const optionScores = type === 'epds'
    ? [[0, 1, 2, 3], [0, 1, 2, 3], [3, 2, 1, 0], [0, 1, 2, 3],
      ...Array.from({ length: 6 }, () => [3, 2, 1, 0])]
    : Array.from({ length: 9 }, () => [0, 1, 2, 3]);
  return {
    type,
    crisis_question: type === 'epds' ? 10 : 9,
    questions: optionScores.map((scores, index) => ({
      number: index + 1,
      options: scores.map((score, optionIndex) => ({ index: optionIndex, score })),
    })),
  };
}

test('EPDS derives all answer scores on the server', () => {
  const instrument = fixture('epds');
  const result = scoreAnswers(instrument, instrument.questions.map((question) => ({
    question_number: question.number,
    option_index: 0,
  })));
  assert.equal(result.total_score, 21);
  assert.equal(result.risk_level, 'severe');
  assert.equal(result.self_harm_positive, true);
});

test('EPDS Q10 positive activates safety independently of total band', () => {
  const instrument = fixture('epds');
  const answers = instrument.questions.map((question) => ({
    question_number: question.number,
    option_index: question.options.findIndex((option) => option.score === 0),
  }));
  answers[9].option_index = 2;
  const result = scoreAnswers(instrument, answers);
  assert.equal(result.total_score, 1);
  assert.equal(result.risk_level, 'low');
  assert.equal(result.self_harm_positive, true);
});

test('EPDS uses the four configured screening bands', () => {
  assert.equal(riskForScore('epds', 8), 'low');
  assert.equal(riskForScore('epds', 9), 'moderate');
  assert.equal(riskForScore('epds', 13), 'high');
  assert.equal(riskForScore('epds', 19), 'severe');
});

test('PHQ-9 instrument is versioned and safety-aware', () => {
  const instrument = fixture('phq9');
  assert.equal(instrument.questions.length, 9);
  const result = scoreAnswers(instrument, instrument.questions.map((question) => ({
    question_number: question.number,
    option_index: 3,
  })));
  assert.equal(result.total_score, 27);
  assert.equal(result.risk_level, 'severe');
  assert.equal(result.self_harm_positive, true);
});

test('screening rejects incomplete or duplicate answer payloads', () => {
  const instrument = fixture('epds');
  assert.throws(() => scoreAnswers(instrument, []), /All 10 questions/);
  const duplicate = instrument.questions.map((question) => ({
    question_number: question.number,
    option_index: 0,
  }));
  duplicate[9].question_number = 1;
  assert.throws(() => scoreAnswers(instrument, duplicate), /only once/);
});
