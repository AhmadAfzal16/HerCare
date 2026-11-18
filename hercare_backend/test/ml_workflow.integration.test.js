const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

test('ML research capture, consent withdrawal and protected pseudonymous export (rollback only)', {
  skip: process.env.RUN_ML_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const query = db.query;
  const transaction = db.withTransaction;
  const env = { ...process.env };
  let server;
  const originalFetch = global.fetch;
  try {
    await client.query('BEGIN');
    // Export request dates are UTC; keep the rollback fixture independent of
    // the workstation/database session's local timezone near midnight.
    // The export's from/to dates are UTC, independent of DB session timezone.
    await client.query("SET LOCAL TIME ZONE 'Pacific/Auckland'");
    const installed = await client.query("SELECT to_regclass('research_consents') AS name");
    if (!installed.rows[0].name) await client.query(await fs.readFile(path.join(__dirname, '../migrations/015_ml_research.sql'), 'utf8'));
    db.query = (...args) => client.query(...args);
    db.withTransaction = (fn) => fn(client);
    const research = require('../src/modules/research/research.service');
    const context = require('../src/modules/risk/risk.context');
    process.env.RESEARCH_COLLECTION_ENABLED = 'true';
    process.env.RESEARCH_STUDY_ID = 'synthetic-rollback-test-not-a-real-study';
    process.env.RESEARCH_EXPORT_ENABLED = 'true';
    process.env.RESEARCH_PSEUDONYM_KEY = 'test-only-key-not-for-deployment-0123456789';
    process.env.NODE_ENV = 'test';
    const mother = randomUUID();
    const admin = randomUUID();
    const day = new Date().toISOString().slice(0, 10);
    for (const [id, role] of [[mother, 'mother'], [admin, 'admin']]) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 't' + id.replaceAll('-', '').slice(0, 12), 'synthetic-test-hash', role]);
    }
    await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier1,consent_tier2)
      VALUES($1,'Private fixture name',28,3,TRUE,FALSE)`, [mother]);
    const moodId = randomUUID();
    await client.query(`INSERT INTO mood_checkins(id,mother_id,entry_date,mood_rating,composite_score,client_request_id)
      VALUES($1,$2,$3,3,3,$4)`, [moodId, mother, day, randomUUID()]);
    const priorDay = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    await client.query(`INSERT INTO sleep_records(mother_id,sleep_date,bedtime,wake_time,awake_minutes,
      quality,awakenings,timezone_offset_minutes) VALUES($1,$2,$3,$4,30,3,2,-300)`,
    [mother, priorDay, `${priorDay}T04:00:00Z`, `${priorDay}T12:00:00Z`]);
    const instrument = (await client.query(`SELECT version,definition->>'scoring_version' AS scoring_version
      FROM screening_instruments WHERE instrument_type='epds' AND is_active`)).rows[0];
    for (const [score, positive, minute] of [[18, true, '00'], [8, false, '01']]) {
      await client.query(`INSERT INTO screening_assessments(mother_id,instrument_type,instrument_version,
        scoring_version,language,status,total_score,risk_level,self_harm_positive,client_request_id,completed_at)
        VALUES($1,'epds',$6,$7,'en','completed',$2,'moderate',$3,$4,$5)`,
      [mother, score, positive, randomUUID(), `${priorDay}T12:${minute}:00Z`, instrument.version, instrument.scoring_version]);
    }
    assert.equal((await client.query('SELECT * FROM research_observations WHERE mother_id=$1', [mother])).rows.length, 0);
    await research.setConsent(mother, { enabled: true, policy_version: research.POLICY_VERSION, timezone: 'UTC' });
    const snapshots = (await client.query('SELECT COUNT(*)::int AS count FROM research_observations WHERE mother_id=$1', [mother])).rows[0].count;
    await research.setConsent(mother, { enabled: true, policy_version: research.POLICY_VERSION, timezone: 'UTC' });
    assert.equal((await client.query('SELECT COUNT(*)::int AS count FROM research_observations WHERE mother_id=$1', [mother])).rows[0].count, snapshots);
    process.env.RESEARCH_STUDY_ID = 'another-synthetic-study';
    await assert.rejects(() => research.setConsent(mother, { enabled: true, policy_version: research.POLICY_VERSION, timezone: 'UTC' }), { statusCode: 409 });
    process.env.RESEARCH_STUDY_ID = 'synthetic-rollback-test-not-a-real-study';
    await context.saveContext(mother, { number_of_children: 2, basic_needs_affordable: false, mother_in_law_relationship: 'good' });
    await client.query('UPDATE mood_checkins SET mood_rating=4 WHERE id=$1', [moodId]);
    const app = require('../src/app');
    const jwt = require('../src/utils/jwt');
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.on('listening', resolve));
    const api = `http://127.0.0.1:${server.address().port}/api/v1`;
    const motherToken = jwt.signAccessToken({ userId: mother, role: 'mother' });
    global.fetch = async (url, options) => {
      if (String(url).endsWith('/v1/recovery')) {
        const body = JSON.parse(options.body);
        assert.equal(body.observations[0].mood_rating, 4);
        assert.equal(body.sleep_observations[0].sleep_minutes, 450);
        assert.equal(body.sleep_observations[0].bedtime_minute, 540);
        assert.equal(body.sleep_observations[0].wake_minute, 1020);
        assert.equal(body.screenings.length, 1);
        assert.equal(body.screenings[0].score, 8);
        assert.equal(body.screenings[0].safety_positive, false);
        assert.equal(body.screenings[0].safety_positive_in_day, true);
        assert.equal(body.screening_safety_history.recorded_positive_count, 1);
        assert.equal(typeof body.screening_safety_history.latest_positive_date, 'string');
        assert.equal(JSON.stringify(body).includes(mother), false);
        return { ok: true, json: async () => ({ periods: [], validation_status: 'descriptive_not_clinically_validated' }) };
      }
      return originalFetch(url, options);
    };
    const response = await originalFetch(`${api}/risk/recovery`, { headers: { Authorization: `Bearer ${motherToken}` } });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).data.validation_status, 'descriptive_not_clinically_validated');
    const refused = await originalFetch(`${api}/research/export`, { method: 'POST', headers: {
      Authorization: `Bearer ${motherToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: day, to: day, purpose: 'external_validation' }) });
    assert.equal(refused.status, 403);
    const data = await research.exportData(admin, { from: day, to: day, purpose: 'external_validation' });
    assert.equal(data.participants.length, 1);
    assert.ok(data.events.some((event) => event.type === 'mood'));
    assert.equal(JSON.stringify(data).includes(mother), false);
    assert.equal(JSON.stringify(data).includes('Private fixture name'), false);
    assert.equal(data.events.find((event) => event.type === 'mood').date, day);
    await client.query("SET LOCAL TIME ZONE 'America/Los_Angeles'");
    const otherZone = await research.exportData(admin, { from: day, to: day, purpose: 'external_validation' });
    assert.equal(otherZone.participants.length, data.participants.length);
    assert.equal(otherZone.events.length, data.events.length);
    assert.deepEqual(otherZone.events.map((event) => event.source_record_id), data.events.map((event) => event.source_record_id));
    await assert.rejects(() => research.exportData(mother, { from: day, to: day, purpose: 'external_validation' }));
    await research.setConsent(mother, { enabled: false, policy_version: research.POLICY_VERSION });
    assert.equal((await client.query('SELECT * FROM research_observations WHERE mother_id=$1', [mother])).rows.length, 0);
    assert.equal((await client.query('SELECT * FROM mood_checkins WHERE mother_id=$1', [mother])).rows.length, 1);
  } finally {
    global.fetch = originalFetch;
    if (server) await new Promise((resolve) => server.close(resolve));
    await client.query('ROLLBACK');
    db.query = query;
    db.withTransaction = transaction;
    process.env = env;
    client.release();
    await db.pool.end();
  }
});
