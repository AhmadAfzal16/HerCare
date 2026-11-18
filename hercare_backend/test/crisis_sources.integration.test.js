const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { rollbackConnection } = require('./helpers/rollback_connection');

test('M10 safe-recipient integration for M5 and M7 (PostgreSQL rollback only, no model or push calls)', {
  skip: process.env.RUN_CRISIS_SOURCES_DB_TEST !== '1',
}, async (t) => {
  require('dotenv').config();
  const previousEnv = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.NLP_ENABLED = 'false';
  process.env.RESEARCH_COLLECTION_ENABLED = 'false';
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const originalQuery = db.query;
  const originalTransaction = db.withTransaction;
  const originalConnect = db.pool.connect;
  const push = require('../src/modules/notifications/notification.service');
  const originalPush = push.processPendingSafely;
  let attemptedWorkerKicks = 0;
  try {
    await client.query('BEGIN');
    assert.ok((await client.query("SELECT to_regclass('crisis_safety_plans') AS name")).rows[0].name,
      'Apply migration 018 normally before this opt-in regression; the test does not edit or apply migrations.');
    db.query = (...args) => client.query(...args);
    db.withTransaction = (fn) => fn(client);
    db.pool.connect = rollbackConnection(client);
    // Existing source modules call the shared worker after saving. This stub
    // verifies that path without Firebase credentials, delivery or a server.
    push.processPendingSafely = async () => { attemptedWorkerKicks++; return { processed: 0, enabled: false }; };
    // Import after replacing the database functions: older modules destructure
    // them at load time, while the new crisis service uses the shared object.
    const mood = require('../src/modules/mood/mood.service');
    const chat = require('../src/modules/chat/chat.service');
    const crisis = require('../src/modules/crisis/crisis.service');
    const mother = randomUUID();
    const guardian = randomUUID();
    const linkId = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [guardian, 'guardian']]) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 't' + id.replaceAll('-', '').slice(0, 12), 'synthetic-test-hash', role]);
    }
    await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier1,consent_tier2)
      VALUES($1,'Synthetic private mother name',28,3,TRUE,TRUE)`, [mother]);
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Synthetic private guardian name','husband','active',NOW())`, [linkId, mother, guardian]);
    const confirmation = (confirmed) => crisis.setGuardianSafety(mother, { guardian_link_id: linkId, confirmed });
    const eventFor = async (source, sourceId) => {
      const result = await client.query('SELECT * FROM crisis_events WHERE mother_id=$1 AND source_type=$2 AND source_id=$3',
        [mother, source, sourceId]);
      assert.equal(result.rowCount, 1, 'A danger source must create exactly one private event even when alerts are disabled.');
      return result.rows[0];
    };
    const alertsFor = (eventId) => client.query('SELECT * FROM guardian_alerts WHERE crisis_event_id=$1', [eventId]);
    const verifyPrivacySafeAlert = async (event, privateContent) => {
      const alerts = await alertsFor(event.id);
      assert.equal(alerts.rowCount, 1);
      const alert = alerts.rows[0];
      assert.equal(alert.mother_id, mother);
      assert.equal(alert.guardian_id, guardian);
      assert.equal(alert.crisis_event_id, event.id);
      assert.equal(alert.alert_type, 'crisis');
      assert.equal(JSON.stringify(alert).includes(privateContent), false);
      assert.equal(JSON.stringify(alert).includes('PRIVATE_'), false);
      assert.equal(JSON.stringify(alert).includes('Synthetic private'), false);
      const outbox = await client.query('SELECT * FROM notification_outbox WHERE alert_id=$1', [alert.id]);
      assert.equal(outbox.rowCount, 1);
      assert.equal(outbox.rows[0].recipient_id, guardian);
      assert.equal(outbox.rows[0].status, 'pending');
      return alert;
    };
    await t.test('M5 danger journal remains private until confirmation; retries never duplicate or retroactively notify', async () => {
      assert.equal((await crisis.support(mother)).guardian.safe_to_contact_confirmed, false);
      const privateRequest = { content: 'PRIVATE_JOURNAL_UNCONFIRMED I might hurt myself.', client_request_id: randomUUID() };
      const privateJournal = await mood.createTextJournal(mother, privateRequest);
      assert.equal(privateJournal.contains_danger, true);
      const privateEvent = await eventFor('journal', privateJournal.id);
      assert.equal(privateEvent.status, 'open');
      assert.equal((await alertsFor(privateEvent.id)).rowCount, 0);
      assert.equal((await mood.createTextJournal(mother, privateRequest)).id, privateJournal.id);
      await confirmation(true);
      // Enabling future alerts is not permission to share old private entries.
      assert.equal((await mood.createTextJournal(mother, privateRequest)).id, privateJournal.id);
      assert.equal((await alertsFor(privateEvent.id)).rowCount, 0);
      const consentedRequest = { content: 'PRIVATE_JOURNAL_CONFIRMED I might hurt myself.', client_request_id: randomUUID() };
      const journal = await mood.createTextJournal(mother, consentedRequest);
      const event = await eventFor('journal', journal.id);
      const alert = await verifyPrivacySafeAlert(event, consentedRequest.content);
      const stored = await client.query('SELECT content_encrypted FROM journal_entries WHERE id=$1', [journal.id]);
      assert.equal(JSON.stringify(stored.rows).includes('PRIVATE_JOURNAL'), false);
      assert.equal((await mood.createTextJournal(mother, consentedRequest)).id, journal.id);
      assert.equal((await eventFor('journal', journal.id)).id, event.id);
      assert.equal((await alertsFor(event.id)).rows[0].id, alert.id);
      assert.equal((await alertsFor(event.id)).rowCount, 1);
    });
    await t.test('M7 mother danger requires confirmation; a guardian message cannot trigger a maternal crisis', async () => {
      await confirmation(false);
      const privateRequest = { content: 'PRIVATE_CHAT_UNCONFIRMED I might hurt myself.', client_request_id: randomUUID() };
      const privateMessage = await chat.sendMessage(mother, 'mother', privateRequest);
      assert.equal(privateMessage.contains_danger, true);
      const privateEvent = await eventFor('chat', privateMessage.id);
      assert.equal((await alertsFor(privateEvent.id)).rowCount, 0);
      assert.equal((await chat.sendMessage(mother, 'mother', privateRequest)).id, privateMessage.id);
      await confirmation(true);
      assert.equal((await chat.sendMessage(mother, 'mother', privateRequest)).id, privateMessage.id);
      assert.equal((await alertsFor(privateEvent.id)).rowCount, 0);
      const consentedRequest = { content: 'PRIVATE_CHAT_CONFIRMED I might hurt myself.', client_request_id: randomUUID() };
      const message = await chat.sendMessage(mother, 'mother', consentedRequest);
      const event = await eventFor('chat', message.id);
      const alert = await verifyPrivacySafeAlert(event, consentedRequest.content);
      const stored = await client.query('SELECT content_encrypted FROM chat_messages WHERE id=$1', [message.id]);
      assert.equal(JSON.stringify(stored.rows).includes('PRIVATE_CHAT'), false);
      assert.equal((await chat.sendMessage(mother, 'mother', consentedRequest)).id, message.id);
      assert.equal((await eventFor('chat', message.id)).id, event.id);
      assert.equal((await alertsFor(event.id)).rows[0].id, alert.id);
      assert.equal((await alertsFor(event.id)).rowCount, 1);
      const maternalCount = (await client.query('SELECT COUNT(*)::int AS n FROM crisis_events WHERE mother_id=$1', [mother])).rows[0].n;
      const alertCount = (await client.query('SELECT COUNT(*)::int AS n FROM guardian_alerts WHERE mother_id=$1', [mother])).rows[0].n;
      const guardianRequest = { content: 'PRIVATE_GUARDIAN_MESSAGE I might hurt myself.', client_request_id: randomUUID() };
      const guardianMessage = await chat.sendMessage(guardian, 'guardian', guardianRequest);
      assert.equal(guardianMessage.contains_danger, true, 'Sentiment metadata may describe a guardian message, not a maternal diagnosis.');
      assert.equal((await chat.sendMessage(guardian, 'guardian', guardianRequest)).id, guardianMessage.id);
      assert.equal((await client.query('SELECT COUNT(*)::int AS n FROM crisis_events WHERE mother_id=$1', [mother])).rows[0].n, maternalCount);
      assert.equal((await client.query('SELECT COUNT(*)::int AS n FROM guardian_alerts WHERE mother_id=$1', [mother])).rows[0].n, alertCount);
      assert.equal((await client.query('SELECT id FROM crisis_events WHERE source_id=$1', [guardianMessage.id])).rowCount, 0);
    });
    assert.ok(attemptedWorkerKicks > 0, 'Existing source modules use the mocked safe worker path.');
  } finally {
    push.processPendingSafely = originalPush;
    db.query = originalQuery;
    db.withTransaction = originalTransaction;
    db.pool.connect = originalConnect;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
    for (const key of Object.keys(process.env)) if (!(key in previousEnv)) delete process.env[key];
    Object.assign(process.env, previousEnv);
  }
});
