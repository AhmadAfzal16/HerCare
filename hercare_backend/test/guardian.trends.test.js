const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');
if (process.env.RUN_GUARDIAN_TRENDS_DB_TEST === '1') require('dotenv').config();
const { buildTrends, getTrends } = require('../src/modules/guardian/guardian.trends');

const asOf = '2026-11-17';
const mood = (date, mood_rating) => ({ date, mood_rating });
const epds = (date, score, language = 'en') => ({ date, score, version: '1', language });
const report = (moodRows = [], screeningRows = []) =>
  buildTrends({ asOf, moodRows, screeningRows }).periods;

test('each view uses six consecutive windows and enforces mood coverage', () => {
  const moods = Array.from({ length: 5 }, (_, index) => mood(`2026-11-${13 + index}`, 5));
  const periods = report(moods);
  for (const { bars } of Object.values(periods)) assert.equal(bars.length, 6);
  assert.deepEqual(periods.weekly.bars.at(-1), {
    start_date: '2026-11-11', end_date: asOf, score: 100,
    coverage: 60, measures: ['mood'], mood_days: 5,
  });
  assert.equal(periods.weekly.bars.at(-2).end_date, '2026-11-10');
  assert.equal(periods.fortnightly.bars.at(-1).start_date, '2026-11-04');
  assert.equal(periods.fortnightly.bars.at(-1).score, null);
  assert.equal(periods.fortnightly.bars.at(-2).end_date, '2026-11-03');
  const populated = report([...moods, mood('2026-11-11', 2)], [epds(asOf, 15)]);
  assert.equal(populated.fortnightly.bars.at(-1).score, 72.5);
});

test('scores shared mood and recent EPDS without revealing screening details', () => {
  const previous = '2026-11-16';
  const scores = [epds(previous, 10), epds('2026-11-18', 30)];
  const improving = report([mood(previous, 2), mood(asOf, 4)], scores).daily;
  assert.equal(improving.direction, 'improving');
  assert.equal(improving.bars.at(-2).score, 41.7);
  assert.deepEqual(improving.bars.at(-1), {
    start_date: asOf, end_date: asOf, score: 71.7,
    coverage: 100, measures: ['mood', 'epds'], mood_days: 1,
  });
  assert.equal(report([mood(previous, 4), mood(asOf, 2)], scores).daily.direction, 'declining');
  assert.equal(report([mood(previous, 2), mood(asOf, 2)], scores).daily.direction, 'similar');
  assert.equal(report([], [epds('2026-11-09', 0)]).daily.bars.at(-1).score, null);
});

test('skips comparisons with mismatched inputs or a repeated screening alone', () => {
  const previous = '2026-11-16';
  const scores = [epds(previous, 15)];
  const moods = [mood(previous, 1), mood(asOf, 5)];
  assert.equal(report([], scores).daily.direction, 'insufficient_data');
  assert.equal(report([mood(asOf, 5)], scores).daily.direction, 'insufficient_data');
  assert.equal(report(moods, [...scores, epds(asOf, 15, 'ur')]).daily.direction, 'insufficient_data');
  assert.equal(report([], [...scores, epds(asOf, 16)]).daily.direction, 'similar');
  assert.equal(report([], [...scores, epds(asOf, 17)]).daily.direction, 'declining');
});

test('rejects non-guardians before reading records', async () => {
  await assert.rejects(getTrends('a-mother', 'mother'), { statusCode: 403 });
});

test('queries only linked records and stops returning them after consent is withdrawn', {
  skip: process.env.RUN_GUARDIAN_TRENDS_DB_TEST !== '1',
}, async () => {
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const transaction = db.withTransaction;
  try {
    await client.query('BEGIN');
    db.withTransaction = (run) => run(client);
    const [mother, guardian, outsider] = Array.from({ length: 3 }, () => randomUUID());
    for (const [id, role] of [[mother, 'mother'], [guardian, 'guardian'], [outsider, 'guardian']]) {
      await client.query('INSERT INTO users (id, phone, password_hash, role) VALUES ($1, $2, $3, $4)',
        [id, `t${id.slice(0, 13)}`, 'test-only', role]);
    }
    await client.query(`INSERT INTO onboarding_data (user_id, consent_tier1, consent_tier2)
      VALUES ($1, TRUE, TRUE)`, [mother]);
    await client.query(`INSERT INTO guardian_links (mother_id, guardian_id, status, accepted_at)
      VALUES ($1, $2, 'active', NOW())`, [mother, guardian]);
    await client.query(`INSERT INTO mood_checkins
        (mother_id, entry_date, mood_rating, energy_level, sleep_quality, social_support, composite_score, client_request_id)
      VALUES ($1, '2026-11-16', 2, 3, 3, 3, 3, $2), ($1, '2026-11-17', 4, 3, 3, 3, 3, $3)`,
    [mother, randomUUID(), randomUUID()]);
    for (const [instrument, time, score] of [
      ['epds', '2026-11-16T18:00:00Z', 15],
      ['epds', '2026-11-16T19:00:00Z', 12],
      ['epds', '2026-11-16T19:30:00Z', 9],
      ['phq9', '2026-11-16T19:45:00Z', 20],
      ['epds', '2026-11-16T21:00:00Z', 25],
    ]) {
      await client.query(`INSERT INTO screening_assessments (mother_id, instrument_type,
          instrument_version, scoring_version, language, status, total_score, risk_level, client_request_id, completed_at)
        VALUES ($1, $2, $3, 'hercare-4band-v1', 'en', 'completed', $4, 'low', $5, $6)`,
      [mother, instrument, instrument === 'epds' ? 'cope-2023-v1' : 'phq9-v1', score, randomUUID(), time]);
    }

    const now = new Date('2026-11-16T20:00:00Z');
    const result = await getTrends(guardian, 'guardian', now);
    assert.equal(result.as_of, asOf);
    assert.equal(result.periods.daily.direction, 'improving');
    assert.equal(result.periods.daily.bars.at(-2).score, 35);
    assert.equal(result.periods.daily.bars.at(-1).score, 73);
    await assert.rejects(getTrends(outsider, 'guardian', now), { statusCode: 403 });
    await client.query('UPDATE onboarding_data SET consent_tier2 = FALSE WHERE user_id = $1', [mother]);
    await assert.rejects(getTrends(guardian, 'guardian', now), { statusCode: 403 });
    await client.query('UPDATE onboarding_data SET consent_tier2 = TRUE WHERE user_id = $1', [mother]);
    await client.query("UPDATE guardian_links SET status = 'revoked' WHERE mother_id = $1", [mother]);
    await assert.rejects(getTrends(guardian, 'guardian', now), { statusCode: 403 });
  } finally {
    db.withTransaction = transaction;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
  }
});
