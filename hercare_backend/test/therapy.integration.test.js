const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M9 authorized writes, idempotency, paired summaries and privacy (synthetic rollback only)', {
  skip: process.env.RUN_THERAPY_DB_TEST !== '1',
}, async () => {
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const previousQuery = database.query, previousTransaction = database.withTransaction;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    const service = require('../src/modules/therapy/therapy.service');
    const [owner, outsider, guardian] = [randomUUID(), randomUUID(), randomUUID()];
    for (const [id, role] of [[owner, 'mother'], [outsider, 'mother'], [guardian, 'guardian']]) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 'm9' + id.replaceAll('-', '').slice(0, 12), 'synthetic-test-only', role]);
      await client.query('INSERT INTO onboarding_data(user_id,consent_tier1) VALUES($1,TRUE)', [id]);
    }
    const request = { activity_type: 'game', activity_id: 'domestic_puzzle', duration_seconds: 60,
      client_request_id: randomUUID(), client_completed_at: new Date(Date.now() - 2 * 86400000).toISOString() };
    const first = await service.recordSession(owner, 'mother', request);
    assert.equal(first.mood_change, null);
    assert.equal(new Date(first.completed_at).toISOString(), request.client_completed_at);
    assert.equal(first.practice_verified, false);
    assert.equal(new Date((await service.getHistory(owner, 'mother'))[0].completed_at).toISOString(), request.client_completed_at);
    assert.equal((await service.recordSession(owner, 'mother', request)).id, first.id);
    const legacyRequest = { ...request };
    delete legacyRequest.client_completed_at;
    assert.equal((await service.recordSession(owner, 'mother', legacyRequest)).id, first.id);
    await assert.rejects(service.recordSession(owner, 'mother', { ...request, duration_seconds: 61 }), { statusCode: 409 });
    await assert.rejects(service.recordSession(owner, 'mother', { ...request,
      client_completed_at: new Date(Date.parse(request.client_completed_at) + 60000).toISOString() }), { statusCode: 409 });
    assert.deepEqual(await service.getHistory(outsider, 'mother'), []);
    await assert.rejects(service.getHistory(guardian, 'guardian'), { statusCode: 403 });
    await service.recordSession(owner, 'mother', { ...request, mood_before: 2, mood_after: 4,
      client_request_id: randomUUID() });
    const incomplete = await service.recordSession(owner, 'mother', { ...request, mood_before: 1,
      mood_after: 5, completed: false, client_request_id: randomUUID() });
    assert.equal(incomplete.mood_change, null);
    const summary = await service.getSummary(owner, 'mother');
    assert.equal(summary.total_sessions, 3);
    assert.equal(summary.completed_sessions, 2);
    assert.equal(summary.total_seconds, 120);
    assert.equal(summary.paired_mood_sessions, 1);
    assert.equal(summary.avg_mood_change, 2);
    assert.equal(summary.clinical_improvement, false);
    await client.query("UPDATE therapeutic_sessions SET completed_at=NOW()-INTERVAL '31 days' WHERE id=$1", [first.id]);
    assert.equal((await service.getSummary(owner, 'mother')).total_sessions, 2);
    await client.query(`INSERT INTO mood_checkins(mother_id,entry_date,mood_rating,energy_level,sleep_quality,
      social_support,composite_score,client_request_id) VALUES($1,CURRENT_DATE,4,4,2,4,3.6,$2)`, [owner, randomUUID()]);
    for (const [activityId, after] of [['body_scan', 3], ['mindfulness', 4]]) {
      for (let index = 0; index < 3; index++) {
        await service.recordSession(owner, 'mother', { ...request, activity_type: 'meditation',
          activity_id: activityId, mood_before: 2, mood_after: after, client_request_id: randomUUID() });
      }
    }
    const preference = await service.getRecommendation(owner, 'mother');
    assert.equal(preference.activity_type, 'meditation');
    assert.equal(preference.activity_id, 'mindfulness');
    assert.equal(preference.selection_source, 'optional_paired_practice_ratings');
    assert.equal(preference.history_observation.paired_mood_sessions, 3);
    assert.equal(preference.history_observation.avg_mood_change, 2);
    assert.equal(preference.clinical_improvement, false);
    await client.query('UPDATE mood_checkins SET mood_rating=2 WHERE mother_id=$1', [owner]);
    assert.equal((await service.getRecommendation(owner, 'mother')).activity_id, 'grounding_54321');
    const breathing = { ...request, activity_type: 'breathing', activity_id: 'box_breathing',
      completed: false, breathing_participation: 'some_cues', client_request_id: randomUUID() };
    const practice = await service.recordSession(owner, 'mother', breathing);
    assert.equal(practice.breathing_participation, 'some_cues');
    assert.equal(practice.practice_verified, false);
    assert.equal((await service.getHistory(owner, 'mother')).find((row) => row.id === practice.id).breathing_participation, 'some_cues');
    assert.equal((await service.recordSession(owner, 'mother', breathing)).id, practice.id);
    await assert.rejects(service.recordSession(owner, 'mother', { ...breathing, breathing_participation: null }), { statusCode: 409 });
    // Monitoring measures round-trip through the real CHECK constraints and keep retries exact.
    const measured = { ...request, activity_type: 'breathing', activity_id: 'cyclic_sighing', client_request_id: randomUUID(),
      measures: { tension_before: 7, tension_after: 3, distress_reported: true, hr_before: 90, hr_after: 78,
        hrv_before: 22, hrv_after: 35, physio_source: 'camera' } };
    const withMeasures = await service.recordSession(owner, 'mother', measured);
    assert.equal(withMeasures.measures.tension_change, -4);
    assert.equal(withMeasures.measures.hrv_change, 13);
    assert.equal((await service.recordSession(owner, 'mother', measured)).id, withMeasures.id);
    await assert.rejects(service.recordSession(owner, 'mother', { ...measured, measures: { ...measured.measures, hr_after: 80 } }),
      { statusCode: 409 });
    const monitored = await service.getSummary(owner, 'mother');
    assert.equal(monitored.monitoring.distress_sessions, 1);
    assert.equal(monitored.monitoring.avg_hrv_change, 13);
    assert.equal((await service.getRecommendation(owner, 'mother')).activity_id, 'grounding_54321');
    await client.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [owner]);
    for (const operation of [() => service.getHistory(owner, 'mother'), () => service.getSummary(owner, 'mother'),
      () => service.getRecommendation(owner, 'mother'), () => service.recordSession(owner, 'mother', request)]) {
      await assert.rejects(operation(), { statusCode: 403 });
    }
    await client.query('UPDATE onboarding_data SET consent_tier1=TRUE WHERE user_id=$1', [owner]);
    await client.query('UPDATE users SET is_active=FALSE WHERE id=$1', [owner]);
    await assert.rejects(service.getHistory(owner, 'mother'), { statusCode: 403 });
    await client.query("UPDATE users SET is_active=TRUE,role='guardian' WHERE id=$1", [owner]);
    await assert.rejects(service.getHistory(owner, 'mother'), { statusCode: 403 });
  } finally {
    await client.query('ROLLBACK');
    database.query = previousQuery;
    database.withTransaction = previousTransaction;
    client.release();
    await database.pool.end();
  }
});
