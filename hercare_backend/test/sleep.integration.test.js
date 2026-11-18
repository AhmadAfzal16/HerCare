const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

test('M8 persistence, optional inputs, calendar trends, private cache and live authorization (rollback fixtures)', {
  skip: process.env.RUN_SLEEP_DB_TEST !== '1',
}, async () => {
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const previous = { query: db.query, withTransaction: db.withTransaction };
  const owners = [randomUUID(), randomUUID(), randomUUID()];
  let service;
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL TIME ZONE 'UTC'");
    await client.query(readFileSync(join(__dirname, '../migrations/019_optional_sleep_details.sql'), 'utf8'));
    let queued = Promise.resolve();
    db.query = (...args) => {
      const operation = queued.then(() => client.query(...args));
      queued = operation.catch(() => {});
      return operation;
    };
    db.withTransaction = (fn) => fn(client);
    service = require('../src/modules/sleep/sleep.service');
    const therapy = require('../src/modules/therapy/therapy.service');
    for (const id of owners) {
      await client.query('INSERT INTO users(id,phone,password_hash) VALUES($1,$2,$3)',
        [id, 't' + id.replaceAll('-', '').slice(0, 13), 'test-only']);
      await client.query('INSERT INTO onboarding_data(user_id,consent_tier1,consent_tier2,consent_tier3) VALUES($1,TRUE,TRUE,TRUE)', [id]);
    }
    const [basic, empty, trend] = owners;
    const wake = new Date(Date.now() - 86400000);
    const query = { as_of: wake.toISOString().slice(0, 10) };
    const body = { sleep_date: query.as_of, wake_time: wake.toISOString(),
      bedtime: new Date(wake.getTime() - 8 * 3600000).toISOString(),
      awake_minutes: 30, quality: 3, awakenings: 2, timezone_offset_minutes: 0 };
    await service.save(basic, body);
    await service.save(basic, body);
    let result = await service.dashboard(basic, query);
    assert.equal(result.records.length, 1, 'same-date writes replace, never duplicate');
    assert.equal(result.summary.average_minutes, 450);
    const reports = await client.query('SELECT sleep_avg_h,report_data FROM health_reports WHERE mother_id=$1', [basic]);
    assert.equal(reports.rows.length, 3);
    assert.ok(reports.rows.every((row) => Number(row.sleep_avg_h) === 7.5));
    assert.equal(JSON.stringify(reports.rows).includes('bedtime'), false, 'guardian reports are aggregate only');
    await service.save(basic, { ...body, awake_minutes: 60, quality: null, awakenings: null });
    result = await service.dashboard(basic, query);
    assert.equal(result.summary.average_minutes, 420, 'own write invalidates read cache');
    assert.equal(result.records[0].quality, null);
    assert.equal(result.records[0].awakenings, null);
    assert.equal(result.insights.windows[0].current.quality_nights, 0);
    assert.equal((await service.dashboard(empty, query)).records.length, 0);
    await assert.rejects(service.dashboard(randomUUID(), query), { statusCode: 403 });

    await client.query(`INSERT INTO sleep_records(mother_id,sleep_date,bedtime,wake_time,awake_minutes,quality,awakenings,timezone_offset_minutes)
      SELECT $1,CURRENT_DATE-n,(CURRENT_DATE-n)+INTERVAL '7 hours'
        -make_interval(mins=>CASE WHEN n<=7 THEN 300 ELSE 480 END),
        (CURRENT_DATE-n)+INTERVAL '7 hours',0,NULL,NULL,0 FROM generate_series(1,28) n`, [trend]);
    await client.query(`INSERT INTO mood_checkins(mother_id,entry_date,mood_rating,energy_level,sleep_quality,social_support,composite_score,client_request_id)
      SELECT $1,CURRENT_DATE-n,CASE WHEN n<=7 THEN 2 ELSE 4 END,3,3,3,3,gen_random_uuid() FROM generate_series(1,28) n`, [trend]);
    await client.query(`INSERT INTO device_telemetry_daily(mother_id,local_date,timezone_offset_minutes,usage_access,
        screen_time_minutes,social_minutes,late_night_minutes,analysis_version,client_request_id)
      VALUES($1,CURRENT_DATE-1,0,TRUE,400,320,40,'test-only',gen_random_uuid())`, [trend]);
    result = await service.dashboard(trend, query);
    assert.equal(result.insights.correlation.paired_days, 28);
    assert.equal(result.insights.correlation.coefficient, 1);
    assert.equal(result.insights.windows[0].change_minutes, -180);
    assert.equal(result.insights.activity, 'body_scan');
    assert.equal(result.insights.digital.recorded_days, 1);
    assert.equal((await therapy.getRecommendation(trend, 'mother')).activity_id, 'grounding_54321');
    await client.query('DELETE FROM mood_checkins WHERE mother_id=$1', [trend]);
    assert.equal((await therapy.getRecommendation(trend, 'mother')).activity_id, 'body_scan',
      'recorded sleep pattern can guide existing M9 without repeating mood inputs');

    // Cache must never grant access, resurrect withdrawn sharing, or mask a new crisis.
    await client.query('UPDATE onboarding_data SET consent_tier3=FALSE WHERE user_id=$1', [trend]);
    assert.equal((await service.dashboard(trend, query)).insights.digital.recorded_days, 0);
    await client.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [trend]);
    await assert.rejects(service.dashboard(trend, query), { statusCode: 403 });
    await assert.rejects(service.save(trend, body), { statusCode: 403 });
    await client.query('UPDATE onboarding_data SET consent_tier1=TRUE WHERE user_id=$1', [trend]);
    await client.query('UPDATE users SET is_active=FALSE WHERE id=$1', [trend]);
    await assert.rejects(service.dashboard(trend, query), { statusCode: 403 });
    await client.query("UPDATE users SET is_active=TRUE,role='guardian' WHERE id=$1", [trend]);
    await assert.rejects(service.dashboard(trend, query), { statusCode: 403 });
    await client.query("UPDATE users SET role='mother' WHERE id=$1", [trend]);
    const event = await client.query(`INSERT INTO crisis_events(mother_id,source_type,source_id,severity)
      VALUES($1,'manual',gen_random_uuid(),'high') RETURNING id`, [trend]);
    result = await service.dashboard(trend, query);
    assert.equal(result.insights.safety_priority, true);
    assert.equal(result.insights.activity, 'crisis');
    assert.equal((await therapy.getRecommendation(trend, 'mother')).safety_priority, true);
    await client.query("UPDATE crisis_events SET status='resolved',resolved_at=NOW() WHERE id=$1", [event.rows[0].id]);
    assert.equal((await service.dashboard(trend, query)).insights.safety_priority, false);

    await client.query(`INSERT INTO screening_assessments(mother_id,instrument_type,instrument_version,scoring_version,language,
        status,total_score,risk_level,self_harm_positive,client_request_id,completed_at)
      SELECT $1,'epds',version,'test-only','en','completed',15,'high',TRUE,gen_random_uuid(),NOW()-INTERVAL '1 day'
        FROM screening_instruments WHERE instrument_type='epds' AND is_active`, [trend]);
    await client.query(`INSERT INTO screening_assessments(mother_id,instrument_type,instrument_version,scoring_version,language,client_request_id)
      SELECT $1,'epds',version,'test-only','en',gen_random_uuid() FROM screening_instruments WHERE instrument_type='epds' AND is_active`, [trend]);
    assert.equal((await therapy.getRecommendation(trend, 'mother')).safety_priority, true,
      'a NULL-timestamp draft cannot hide the completed positive safety screen');
    assert.equal(Number((await client.query('SELECT COUNT(*) FROM guardian_alerts WHERE mother_id=ANY($1::uuid[])', [owners])).rows[0].count), 0,
      'sleep patterns do not trigger guardian alerts or diagnoses');
  } finally {
    for (const owner of owners) service?.invalidate(owner);
    await client.query('ROLLBACK');
    db.query = previous.query;
    db.withTransaction = previous.withTransaction;
    client.release();
    await db.pool.end();
  }
});
