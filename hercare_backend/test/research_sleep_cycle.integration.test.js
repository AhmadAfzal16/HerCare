const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

test('future consented sleep snapshots include local clock times (all changes rolled back)', {
  skip: process.env.RUN_SLEEP_RESEARCH_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const { pool } = require('../src/config/database');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const installed = await client.query("SELECT to_regprocedure('enrich_research_sleep_cycle()') AS name");
    if (!installed.rows[0].name) {
      await client.query(await fs.readFile(path.join(__dirname, '../migrations/017_research_sleep_cycle.sql'), 'utf8'));
    }
    const mother = randomUUID();
    const sleep = randomUUID();
    await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
      VALUES($1,$2,'synthetic-test-hash','mother',TRUE)`, [mother, `t${mother.replaceAll('-', '').slice(0, 12)}`]);
    await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier1)
      VALUES($1,'Synthetic sleep test',28,3,TRUE)`, [mother]);
    const insert = `INSERT INTO sleep_records(id,mother_id,sleep_date,bedtime,wake_time,awake_minutes,quality,
        awakenings,timezone_offset_minutes)
      VALUES($1,$2,CURRENT_DATE-1,((CURRENT_DATE-2)+TIME '18:30:00') AT TIME ZONE 'UTC',
        ((CURRENT_DATE-1)+TIME '02:45:00') AT TIME ZONE 'UTC',30,3,2,-300)`;
    await client.query(insert, [sleep, mother]);
    assert.equal((await client.query('SELECT COUNT(*)::int AS n FROM research_observations WHERE mother_id=$1', [mother])).rows[0].n, 0);
    await client.query(`INSERT INTO research_consents(mother_id,enabled,policy_version,study_id,granted_at)
      VALUES($1,TRUE,'research-aggregate-v1','synthetic-rollback-only',NOW()-INTERVAL '7 days')`, [mother]);
    // An actual update creates a new snapshot; consent does not backfill records.
    await client.query("SET LOCAL TIME ZONE 'America/New_York'");
    await client.query('UPDATE sleep_records SET quality=4 WHERE id=$1', [sleep]);
    const captured = (await client.query(`SELECT payload FROM research_observations
      WHERE mother_id=$1 AND source_type='sleep' ORDER BY id`, [mother])).rows;
    assert.equal(captured.length, 1);
    assert.equal(captured[0].payload.bedtime_local_minutes, 1410); // 23:30 Pakistan
    assert.equal(captured[0].payload.wake_local_minutes, 465); // 07:45 Pakistan
    assert.equal(captured[0].payload.sleep_minutes, 465);
    assert.equal(captured[0].payload.sleep_quality, 4);
    assert.equal(captured[0].payload.sleep_clock_source, 'self_reported_client_offset');
    assert.equal(JSON.stringify(captured).includes('Synthetic sleep test'), false);
    await client.query("SET LOCAL TIME ZONE 'Asia/Tokyo'");
    await client.query('UPDATE sleep_records SET timezone_offset_minutes=330 WHERE id=$1', [sleep]);
    const revised = (await client.query(`SELECT payload FROM research_observations
      WHERE mother_id=$1 AND source_type='sleep' ORDER BY id DESC LIMIT 1`, [mother])).rows[0].payload;
    assert.equal(revised.bedtime_local_minutes, 780); // 13:00 local, UTC-5:30
    assert.equal(revised.wake_local_minutes, 1275); // 21:15 local, midnight wrap
    await client.query('UPDATE research_consents SET enabled=FALSE WHERE mother_id=$1', [mother]);
    await client.query('UPDATE sleep_records SET quality=2 WHERE id=$1', [sleep]);
    assert.equal((await client.query('SELECT COUNT(*)::int AS n FROM research_observations WHERE mother_id=$1', [mother])).rows[0].n, 2);
  } finally {
    await client.query('ROLLBACK');
    client.release();
    await pool.end();
  }
});
