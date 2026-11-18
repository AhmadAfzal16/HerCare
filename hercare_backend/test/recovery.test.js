const test = require('node:test');
const assert = require('node:assert/strict');
const { validateRecoveryResponse } = require('../src/modules/risk/recovery.response');

function resultFixture() {
  const signal = { status: 'insufficient_data', direction: 'descriptive_only', latest_date: null,
    age_days: null, stale: false, note: 'Supporting observations only.', windows: [] };
  const trend = (instrument) => ({ instrument, version: null, language: null, current_score: null,
    previous_score: null, current_date: null, previous_date: null, score_change_points: null,
    actual_interval_days: null, direction: 'insufficient_data', stale: false, age_days: null,
    safety_positive: false, reason: 'no_completed_assessment',
    comparison_rule: { scheduled_interval_days: instrument === 'epds' ? 7 : 14, tolerance_days: 3,
      meaning: 'project_comparability_rule_not_clinical_validation' } });
  return { as_of: '2026-10-09', periods: [], screening_changes: [], requires_safety_review: false,
    validation_status: 'descriptive_not_clinically_validated', depression_monitoring: {
      status: 'observed_monitoring_only', requires_safety_review: false,
      screening_trends: [trend('epds'), trend('phq9')],
      supporting_signals: { mood: signal, sleep: { ...signal, source: 'self_reported' } },
      future_outlook: { status: 'not_trained', probability: null, horizon_days: 14,
        target: 'future_screen_positive', reason: 'genuine_dated_followup_model_unavailable', notice: 'Not a future forecast.' },
      safety_history: { recorded_positive_count: 0, latest_positive_date: null, resolution_known: null,
        meaning: 'recorded_safety_history_for_review_not_present_imminent_danger_assessment' },
      interpretation: 'Recorded symptom trends, not diagnosis.',
    } };
}

test('recovery accepts additive monitoring and the legacy descriptive contract', () => {
  const result = resultFixture();
  assert.equal(validateRecoveryResponse(result), result);
  assert.doesNotThrow(() => validateRecoveryResponse({ periods: [], validation_status: 'descriptive_not_clinically_validated' }));
});

test('recovery rejects fabricated future probability, invalid PHQ totals and hidden safety', () => {
  for (const mutate of [
    (r) => { r.depression_monitoring.future_outlook.probability = 0.9; },
    (r) => { r.depression_monitoring.screening_trends[1].current_score = 28; },
    (r) => { r.depression_monitoring.screening_trends[0].current_score = '12'; },
    (r) => { r.depression_monitoring.safety_history.recorded_positive_count = 1; },
    (r) => { r.periods = [{ window_days: 7, index_change_points: NaN }]; },
    (r) => { r.periods = [{ window_days: 7, index_change_points: '5' }]; },
    (r) => { r.periods = [{ window_days: 7, raw_journal: 'private text' }]; },
    (r) => { r.depression_monitoring.screening_trends[0].instrument = 'phq9'; },
  ]) {
    const result = resultFixture(); mutate(result);
    assert.throws(() => validateRecoveryResponse(result), { statusCode: 503 });
  }
});

test('recovery validates delta direction and never accepts stale comparison as improvement', () => {
  const result = resultFixture();
  Object.assign(result.depression_monitoring.screening_trends[0], {
    current_score: 8, previous_score: 16, current_date: '2026-10-09', previous_date: '2026-10-02',
    score_change_points: -8, actual_interval_days: 7, age_days: 0,
    reason: 'comparable_assessments', direction: 'lower_recorded_symptoms',
  });
  assert.doesNotThrow(() => validateRecoveryResponse(result));
  result.depression_monitoring.screening_trends[0].direction = 'higher_recorded_symptoms';
  assert.throws(() => validateRecoveryResponse(result), { statusCode: 503 });
  result.depression_monitoring.screening_trends[0].direction = 'lower_recorded_symptoms';
  result.depression_monitoring.screening_trends[0].stale = true;
  assert.throws(() => validateRecoveryResponse(result), { statusCode: 503 });
});

test('recovery query maps only owned bounded self-reported sleep and local clock timing', async () => {
  const db = require('../src/config/database');
  const client = require('../src/modules/risk/risk.client');
  const originalQuery = db.query; const originalRequest = client.request;
  const servicePath = require.resolve('../src/modules/risk/recovery.service');
  let body; let accountChecks = 0;
  try {
    db.query = async (sql, params) => {
      assert.equal(params[0], 'synthetic-mother');
      if (sql.includes('FROM users')) { accountChecks++; return { rows: [{ id: 'synthetic-mother' }] }; }
      if (sql.includes('FROM mood_checkins')) return { rows: [{ entry_date: '2026-10-09', mood_rating: 3 }] };
      if (sql.includes('FROM screening_assessments')) {
        assert.ok(sql.includes('DISTINCT ON'));
        assert.ok(sql.includes('BOOL_OR'));
        return { rows: [] };
      }
      assert.ok(sql.includes('FROM sleep_records'));
      assert.ok(sql.includes('LIMIT 60') && sql.includes('wake_time<=$3'));
      return { rows: [{ sleep_date: '2026-10-09', bedtime: '2026-10-08T18:30:00Z', wake_time: '2026-10-09T02:00:00Z',
        sleep_minutes: '420', awake_minutes: 30, quality: 3, awakenings: 2, timezone_offset_minutes: -300 }] };
    };
    client.request = async (endpoint, payload) => { assert.equal(endpoint, '/v1/recovery'); body = payload; return resultFixture(); };
    delete require.cache[servicePath];
    const service = require(servicePath);
    const result = await service.summary('synthetic-mother', new Date('2026-10-09T09:00:00Z'));
    assert.equal(result.depression_monitoring.future_outlook.probability, null);
    assert.equal(body.sleep_observations[0].bedtime_minute, 1410);
    assert.equal(body.sleep_observations[0].wake_minute, 420);
    assert.equal(body.sleep_observations[0].sleep_minutes, 420);
    assert.equal(JSON.stringify(body).includes('synthetic-mother'), false);
    assert.equal(accountChecks, 2);
  } finally { db.query = originalQuery; client.request = originalRequest; delete require.cache[servicePath]; }
});

test('withdrawn basic consent is refused again after private inference', async () => {
  const db = require('../src/config/database');
  const client = require('../src/modules/risk/risk.client');
  const originalQuery = db.query; const originalRequest = client.request;
  const servicePath = require.resolve('../src/modules/risk/recovery.service');
  let checks = 0;
  try {
    db.query = async (sql) => ({ rows: sql.includes('FROM users') && ++checks === 1 ? [{ id: 'synthetic-mother' }] : [] });
    client.request = async () => resultFixture();
    delete require.cache[servicePath];
    await assert.rejects(() => require(servicePath).summary('synthetic-mother'), { statusCode: 403 });
  } finally { db.query = originalQuery; client.request = originalRequest; delete require.cache[servicePath]; }
});

module.exports = { resultFixture };
