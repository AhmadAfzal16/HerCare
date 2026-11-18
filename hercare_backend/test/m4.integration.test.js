const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { capture, hasDistress } = require('../src/modules/risk/m4.text');
const service = require('../src/modules/risk/m4.service');

test('M4 text flags clear personal statements across supported languages', () => {
  for (const phrase of ['I feel hopeless.', 'I’m very sad.', 'Mujhe bohat udaas', 'مجھے بہت اداس۔',
    'I got some rest. Today, I feel overwhelmed.', 'آج میں بہت پریشان ہوں۔']) {
    assert.equal(hasDistress(phrase), true, phrase);
  }
  for (const phrase of ['She said I feel hopeless', 'I feel sad no longer', 'I feel sad?', 'I feel tired',
    'Mujhe bohat udaas nahi', 'میں اداس نہیں ہوں', 'Someone said “I feel hopeless.”', 'مجھے بہت اداس؟']) {
    assert.equal(hasDistress(phrase), false, phrase);
  }
});

test('M4 questionnaire accepts skipped answers and rejects malformed or unknown fields', () => {
  const answers = { financial_strain: 0, relationship_strain: 1, support_gap: null, recovery_difficulty: 3 };
  assert.deepEqual(service.validateCheckin(answers), [0, 1, null, 3]);
  for (const invalid of [null, {}, { ...answers, support_gap: '2' },
    { ...answers, relationship_strain: 4 }, { ...answers, guardian_id: 'unexpected' }]) {
    assert.throws(() => service.validateCheckin(invalid), { statusCode: 422 });
  }
});

test('M4 PostgreSQL sources, safety, dated context, account isolation and prospective text consent', {
  skip: process.env.RUN_M4_DB_TEST !== '1',
}, async () => {
  const db = require('../src/config/database');
  const { rollbackConnection } = require('./helpers/rollback_connection');
  const client = await db.pool.connect();
  const originalConnect = db.pool.connect;
  let server;
  try {
    await client.query('BEGIN');
    db.pool.connect = rollbackConnection(client);
    const mother = randomUUID();
    const other = randomUUID();
    const guardian = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [other, 'mother'], [guardian, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
        VALUES($1,$2,'fixture',$3,TRUE)`, [id, 'm' + id.replaceAll('-', '').slice(0, 13), role]);
      await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier3)
        VALUES($1,'Fixture name',28,2,FALSE)`, [id]);
    }
    await assert.rejects(() => service.summary(guardian), { statusCode: 403 });

    const now = new Date();
    const ago = (days) => new Date(now.getTime() - days * 86400000);
    const initial = await service.summary(mother, now);
    assert.equal(initial.reports.every((report) => report.score === null), true);
    assert.equal(initial.text_enabled, false);
    assert.equal(initial.safety_priority, false);
    assert.equal(JSON.stringify(initial).includes('Fixture name'), false);

    const context = { financial_strain: 3, relationship_strain: 0, support_gap: 1, recovery_difficulty: null };
    await assert.rejects(() => service.saveCheckin(mother, { ...context, date: '2000-01-01' }, now), { statusCode: 409 });
    assert.deepEqual(await service.saveCheckin(mother, context, now), { date: initial.as_of, ...context });
    await service.saveCheckin(mother, { ...context, support_gap: null }, now);
    for (const [id, days, score, harm] of [[mother, 7, 5, false], [mother, 0, 8, false], [other, 0, 20, true]]) {
      await client.query(`INSERT INTO screening_assessments
        (mother_id,instrument_type,instrument_version,scoring_version,language,status,total_score,
          risk_level,self_harm_positive,client_request_id,completed_at)
        VALUES($1,'epds','cope-2023-v1','hercare-4band-v1','en','completed',$2,'low',$3,$4,$5)`,
      [id, score, harm, randomUUID(), ago(days)]);
    }
    await client.query(`INSERT INTO mood_checkins
      (mother_id,entry_date,mood_rating,composite_score,client_request_id) VALUES($1,$2,2,2,$3)`,
    [mother, initial.as_of, randomUUID()]);
    await client.query(`INSERT INTO sleep_records
      (mother_id,sleep_date,bedtime,wake_time,awake_minutes,quality,awakenings,timezone_offset_minutes)
      VALUES($1,$2,$3::timestamptz-INTERVAL '5 hours',$3,0,2,3,300)`, [mother, initial.as_of, now]);
    await client.query(`INSERT INTO device_telemetry_daily
      (mother_id,local_date,timezone_offset_minutes,usage_access,screen_time_minutes,analysis_version,client_request_id)
      VALUES($1,$2,300,TRUE,200,'fixture',$3)`, [mother, initial.as_of, randomUUID()]);

    const monitored = await service.summary(mother, now);
    assert.deepEqual(monitored.reports.map((report) => report.period), ['daily', 'weekly', 'fortnightly', 'overall']);
    assert.equal(typeof monitored.reports[0].score, 'number');
    assert.equal(monitored.reports[0].screenings.epds.latest_score, 8);
    assert.equal(monitored.reports[0].groups.find((group) => group.key === 'phone').coverage, 0);
    assert.equal(monitored.checkin.support_gap, null);
    assert.equal(monitored.safety_priority, false);
    assert.equal((await service.summary(other, now)).checkin, null);
    assert.equal((await service.summary(other, now)).safety_priority, true);

    async function addEntry(beforeConsent = false) {
      const id = randomUUID();
      await client.query(`INSERT INTO journal_entries
        (id,mother_id,entry_type,language,content_encrypted,client_request_id,created_at)
        VALUES($1,$2,'text','en','fixture',$3,
          CASE WHEN $4 THEN clock_timestamp()-INTERVAL '1 day' ELSE clock_timestamp() END)`,
      [id, mother, randomUUID(), beforeConsent]);
      return id;
    }
    const oldEntry = await addEntry(true);
    await capture(client, mother, 'journal', oldEntry, 'I feel sad.', false);
    await service.saveTextConsent(mother, { enabled: true });
    await capture(client, mother, 'journal', oldEntry, 'I feel sad.', false);
    const newEntry = await addEntry();
    await capture(client, other, 'journal', newEntry, 'I feel sad.', false);
    await capture(client, mother, 'journal', newEntry, 'I feel sad.', true);
    const count = async () => Number((await client.query(
      'SELECT COUNT(*) FROM m4_text_signals WHERE mother_id=$1', [mother],
    )).rows[0].count);
    assert.equal(await count(), 0);
    await capture(client, mother, 'journal', newEntry, 'I feel sad.', false);
    await capture(client, mother, 'journal', newEntry, 'I feel sad.', false);
    assert.equal(await count(), 1);
    const audio = randomUUID();
    await client.query(`INSERT INTO journal_entries
      (id,mother_id,entry_type,language,voice_object_key,client_request_id) VALUES($1,$2,'voice','en','fixture',$3)`,
    [audio, mother, randomUUID()]);
    await capture(client, mother, 'journal', audio, 'I feel sad.', false);
    assert.equal(await count(), 1);
    await client.query(`INSERT INTO journal_voice_transcriptions(journal_id,status,confirmed_request_id,confirmed_at)
      VALUES($1,'confirmed',$2,clock_timestamp())`, [audio, randomUUID()]);
    await capture(client, mother, 'journal', audio, 'I feel sad.', false);
    assert.equal(await count(), 2);

    const session = (await client.query("INSERT INTO chatbot_sessions(mother_id,language) VALUES($1,'en') RETURNING id",
      [mother])).rows[0].id;
    const request = (await client.query(`INSERT INTO chatbot_requests
      (session_id,client_request_id,content_hash,language,status,lease_id,consent_snapshot_encrypted,context_encrypted)
      VALUES($1,$2,'fixture','en','complete',$3,'fixture','fixture') RETURNING id`, [session, randomUUID(), randomUUID()])).rows[0].id;
    await client.query(`INSERT INTO chatbot_turns(session_id,request_id,role,language,content_encrypted,created_at)
      VALUES($1,$2,'user','en','fixture',clock_timestamp())`, [session, request]);
    await capture(client, mother, 'hum_raaz', request, 'I feel alone.', false);
    assert.equal(await count(), 3);
    await client.query('DELETE FROM chatbot_sessions WHERE id=$1', [session]);
    assert.equal(await count(), 2);
    assert.equal((await service.summary(mother)).text_enabled, true);
    await service.saveTextConsent(mother, { enabled: false });
    assert.equal(await count(), 0);
    assert.equal((await service.summary(mother)).text_enabled, false);

    process.env.JWT_ACCESS_SECRET ||= randomUUID();
    process.env.JWT_REFRESH_SECRET ||= randomUUID();
    const express = require('express');
    const { signAccessToken } = require('../src/utils/jwt');
    const { errorHandler } = require('../src/middleware/error_handler');
    const app = express();
    app.use(express.json());
    app.use('/api/v1/risk', require('../src/modules/risk/risk.routes'));
    app.use(errorHandler);
    server = await new Promise((resolve, reject) => {
      const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
      listener.once('error', reject);
    });
    const url = `http://127.0.0.1:${server.address().port}/api/v1/risk/m4`;
    const headers = {
      Authorization: `Bearer ${signAccessToken({ userId: mother, role: 'mother' })}`,
      'X-Risk-Account-Id': mother,
      'Content-Type': 'application/json',
    };
    for (const [supplied, status] of [[undefined, 401], [{ ...headers, 'X-Risk-Account-Id': other }, 409], [headers, 200]]) {
      const response = await fetch(url, { headers: supplied });
      assert.equal(response.status, status);
      assert.equal(response.headers.get('cache-control'), 'private, no-store');
      if (status === 200) assert.equal((await response.json()).data.reports.length, 4);
    }
    const saved = await fetch(url + '/context-checkin', {
      method: 'PUT', headers, body: JSON.stringify({ ...context, support_gap: 2 }),
    });
    assert.equal(saved.status, 200);
    assert.equal((await saved.json()).data.support_gap, 2);
  } finally {
    if (server) {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
    db.pool.connect = originalConnect;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
  }
});
