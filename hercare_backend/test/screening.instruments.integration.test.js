const test = require('node:test');
const assert = require('node:assert/strict');
require('dotenv').config();

test('published EPDS and PHQ-9 definitions come from PostgreSQL', {
  skip: process.env.RUN_SCREENING_DB_TEST !== '1',
}, async () => {
  const { pool } = require('../src/config/database');
  const { getInstrument } = require('../src/modules/screening/screening.instruments');
  const { scoreAnswers } = require('../src/modules/screening/screening.scoring');
  try {
    for (const [type, count, version] of [
      ['epds', 10, 'cope-2023-v1'], ['phq9', 9, 'phq9-v1'],
    ]) {
      const instrument = await getInstrument(type);
      assert.equal(instrument.version, version);
      assert.strictEqual(await getInstrument(type), instrument);
      assert.equal(Object.isFrozen(instrument.questions[0].options[0]), true);
      assert.equal(instrument.questions.length, count);
      assert.deepEqual(await getInstrument(type, version), instrument);
      assert.ok(instrument.questions.every((question) => question.options.length === 4));
      const responses = instrument.questions.map((question) => ({
        question_number: question.number, option_index: 0,
      }));
      const scored = scoreAnswers(instrument, responses);
      assert.equal(scored.total_score,
        instrument.questions.reduce((sum, question) => sum + question.options[0].score, 0));
    }
    const epds = await getInstrument('epds');
    assert.equal(epds.questions[9].options[2].score, 1);
    const phq9 = await getInstrument('phq9');
    assert.equal(phq9.questions[8].options[3].score, 3);
  } finally {
    await pool.end();
  }
});
