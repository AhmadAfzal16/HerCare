const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const path = require('node:path');

test('screening schedule and push delivery (rollback, fake messaging only)', {
  skip: process.env.RUN_SCREENING_DB_TEST !== '1',
}, async () => {
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const originalQuery = database.query;
  const originalTransaction = database.withTransaction;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    const schema = await client.query(`SELECT 1 FROM information_schema.columns
      WHERE table_name = 'notification_outbox' AND column_name = 'screening_reminder_id'`);
    if (!schema.rowCount) {
      await client.query(await readFile(path.join(__dirname, '../migrations/011_screening_reminder_push.sql'), 'utf8'));
    }
    const schedule = require('../src/modules/screening/screening.schedule');
    const screening = require('../src/modules/screening/screening.service');
    const push = require('../src/modules/notifications/notification.service');
    const crypto = require('../src/modules/notifications/push_crypto');
    const mother = randomUUID();
    const guardian = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [guardian, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
        VALUES($1,$2,'test-only',$3,TRUE)`, [id, `t${id.replaceAll('-', '').slice(0, 13)}`, role]);
      await client.query('INSERT INTO onboarding_data(user_id,consent_tier1) VALUES($1,TRUE)', [id]);
    }
    let tests = await schedule.getSchedule(mother);
    assert.equal(tests.length, 2);
    assert.ok(tests.every((item) => item.due));
    assert.equal(tests.find((item) => item.instrument_type === 'phq9').interval_days, 14);
    assert.deepEqual(await schedule.getSchedule(guardian), []);
    await schedule.getSchedule(mother);
    await schedule.queueDueReminders(10000);
    await schedule.queueDueReminders(10000);
    const outboxes = (await client.query('SELECT * FROM notification_outbox WHERE recipient_id=$1', [mother])).rows;
    assert.equal(outboxes.length, 2, 'No duplicate notifications from repeated workers');
    assert.equal((await client.query('SELECT 1 FROM notification_outbox WHERE recipient_id=$1', [guardian])).rowCount, 0);
    const phqBox = (await client.query(`SELECT no.* FROM notification_outbox no
      JOIN screening_reminders sr ON sr.id=no.screening_reminder_id
      WHERE no.recipient_id=$1 AND sr.instrument_type='phq9'`, [mother])).rows[0];
    const token = 'fake-screening-token-not-a-real-firebase-device';
    await client.query(`INSERT INTO push_devices(user_id,token_hash,token_encrypted,platform)
      VALUES($1,$2,$3,'android')`, [mother, crypto.hashToken(token), crypto.encryptToken(token)]);
    let deliveries = 0;
    const messaging = { sendEachForMulticast: async (message) => {
      deliveries += 1;
      assert.deepEqual(message.tokens, [token]);
      assert.deepEqual(message.data, { route: '/tests', type: 'screening_reminder', recipient_id: mother });
      assert.equal(message.android.notification.channelId, 'hercare_screening_reminders');
      assert.equal(message.android.priority, 'normal');
      assert.ok(!/score|depression|phq|epds/i.test(JSON.stringify(message.notification)));
      return { successCount: 1, responses: [{ success: true }] };
    } };
    await push._private.deliver(phqBox, messaging);
    assert.equal(deliveries, 1);
    await client.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [mother]);
    assert.deepEqual(await push._private.loadDelivery(phqBox), []);
    await client.query('UPDATE onboarding_data SET consent_tier1=TRUE WHERE user_id=$1', [mother]);
    for (const [instrument, count, days] of [['phq9', 9, 14], ['epds', 10, 7]]) {
      const draft = await screening.startAssessment(mother, {
        instrument_type: instrument, language: 'en', client_request_id: randomUUID(),
      });
      tests = await schedule.getSchedule(mother);
      assert.equal(tests.find((item) => item.instrument_type === instrument).draft_id, draft.id);
      const result = await screening.submitAssessment(mother, draft.id,
        Array.from({ length: count }, (_, index) => ({ question_number: index + 1, option_index: 0 })));
      tests = await schedule.getSchedule(mother);
      const next = tests.find((item) => item.instrument_type === instrument);
      assert.equal(next.due, false);
      assert.equal(next.draft_id, null);
      assert.equal(new Date(next.due_at) - new Date(result.completed_at), days * 86400000);
      await screening.submitAssessment(mother, draft.id,
        Array.from({ length: count }, (_, index) => ({ question_number: index + 1, option_index: 0 })));
      assert.equal((await schedule.getSchedule(mother)).length, 2);
    }
    await push._private.deliver(phqBox, messaging);
    assert.equal(deliveries, 1, 'Completing a test cancels stale queued reminders');
    const cancelled = await client.query('SELECT status FROM notification_outbox WHERE id=$1', [phqBox.id]);
    assert.equal(cancelled.rows[0].status, 'sent', 'A completed reminder cannot rewrite an already accepted delivery as cancelled');
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    client.release();
    await database.pool.end();
  }
});
