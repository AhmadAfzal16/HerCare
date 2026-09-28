const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('sleep persistence, replacement, account boundary, and guardian averages (rollback fixtures)', {
  skip: process.env.RUN_SLEEP_DB_TEST !== '1',
}, async () => {
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const originalQuery = database.query;
  const originalTransaction = database.withTransaction;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    const router = require('../src/modules/sleep/sleep.routes');
    const id = randomUUID();
    await client.query('INSERT INTO users (id, phone, password_hash) VALUES ($1,$2,$3)', [id, `t${id.replaceAll('-', '').slice(0, 13)}`, 'test-only']);
    await client.query('INSERT INTO onboarding_data (user_id, consent_tier1, consent_tier2) VALUES ($1,TRUE,TRUE)', [id]);
    const wake = new Date(Date.now() - 86400000);
    const request = { user: { userId: id, role: 'mother' }, body: {
      sleep_date: wake.toISOString().slice(0, 10), wake_time: wake.toISOString(),
      bedtime: new Date(wake.getTime() - 8 * 3600000).toISOString(),
      awake_minutes: 30, quality: 3, awakenings: 2, timezone_offset_minutes: 0,
    } };
    const invoke = async (fn, req) => {
      let result;
      await fn(req, { json: (data) => { result = data; } }, (error) => { if (error) throw error; });
      return result;
    };
    const put = router.stack.find((layer) => layer.route?.methods.put).route.stack.at(-1).handle;
    const get = router.stack.find((layer) => layer.route?.methods.get).route.stack.at(-1).handle;
    await invoke(router.stack[1].handle, request);
    await invoke(put, request);
    await invoke(put, request);
    const result = await invoke(get, request);
    assert.equal(result.data.records.length, 1);
    assert.equal(result.data.summary.average_minutes, 450);
    const reports = await client.query('SELECT sleep_avg_h FROM health_reports WHERE mother_id = $1', [id]);
    assert.equal(reports.rows.length, 3);
    assert.ok(reports.rows.every((row) => Number(row.sleep_avg_h) === 7.5));
    request.body.awake_minutes = 60;
    await invoke(put, request);
    assert.equal((await invoke(get, request)).data.summary.average_minutes, 420);
    assert.equal((await invoke(get, { user: { userId: randomUUID() } })).data.records.length, 0);
    await assert.rejects(invoke(router.stack[1].handle, { user: { userId: id, role: 'guardian' } }));
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    client.release();
    await database.pool.end();
  }
});
