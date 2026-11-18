const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

test('Hum-Raaz mother privacy, optional scores, history, retry and safety (PostgreSQL rollback only)', {
  skip: process.env.RUN_CHATBOT_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const env = { ...process.env };
  process.env.NODE_ENV = 'test';
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const originalQuery = db.query;
  const originalTransaction = db.withTransaction;
  const model = require('../src/modules/chatbot/chatbot.client');
  const originalModel = model.reply;
  const push = require('../src/modules/notifications/notification.service');
  const originalPush = push.processPendingSafely;
  const inputs = [];
  let pushCount = 0;
  const response = (language) => ({ reply: 'A test response, not medical advice.', language, mode: 'retrieval_only', sources: [], actions: ['mood'],
    safety: { requires_help: false, guardian_alert_allowed: false, reason: null }, state: { topic: 'sleep' }, model_version: 'synthetic-test', clinical_validation: false });
  try {
    await client.query('BEGIN');
    const installed = await client.query("SELECT to_regclass('chatbot_sessions') AS name");
    if (!installed.rows[0].name) await client.query(await fs.readFile(path.join(__dirname, '../migrations/016_hum_raaz_chatbot.sql'), 'utf8'));
    await client.query(await fs.readFile(path.join(__dirname, '../migrations/018_crisis_support.sql'), 'utf8'));
    db.query = (...args) => client.query(...args);
    db.withTransaction = (fn) => fn(client);
    model.reply = async (input) => { inputs.push(input); return { ...response(input.language),
      reply: input.context.personalization_enabled ? 'Personalized mean mood is 4.' : 'General support, no aggregate scores.',
      state: input.context.personalization_enabled ? { aggregate_mean_mood: 4 } : { topic: 'sleep' } }; };
    push.processPendingSafely = async () => { pushCount++; };
    const service = require('../src/modules/chatbot/chatbot.service');
    const policy = require('../src/modules/chatbot/chatbot.policy');
    const mother = randomUUID();
    const other = randomUUID();
    const guardian = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [other, 'mother'], [guardian, 'guardian']]) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 't' + id.replaceAll('-', '').slice(0, 12), 'synthetic-test-hash', role]);
      if (role === 'mother') await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier1,consent_tier2)
        VALUES($1,'Private test name',28,3,TRUE,FALSE)`, [id]);
    }
    const session = await service.createSession(mother, { language: 'en' });
    assert.equal((await service.status(mother)).personalization.enabled, false);
    await assert.rejects(() => service.status(guardian), { statusCode: 403 });
    const day = new Date().toISOString().slice(0, 10);
    await client.query(`INSERT INTO mood_checkins(mother_id,entry_date,mood_rating,composite_score,client_request_id)
      VALUES($1,$2,4,4,$3)`, [mother, day, randomUUID()]);
    const send = (message, request = randomUUID(), language = 'en') => service.sendMessage(mother, session.id,
      { message, language, client_request_id: request });
    const request = randomUUID();
    const first = await send('I need support with sleep', request);
    assert.equal(first.status, 'complete');
    assert.deepEqual(first.messages.map((turn) => turn.role), ['user', 'assistant']);
    assert.deepEqual(inputs[0].context, { personalization_enabled: false, as_of: inputs[0].context.as_of });
    assert.equal(JSON.stringify(inputs[0]).includes(mother), false);
    assert.equal((await send('I need support with sleep', request)).messages[0].id, first.messages[0].id);
    assert.equal(inputs.length, 1);
    await assert.rejects(() => send('different text', request), { statusCode: 409 });
    await assert.rejects(() => service.listMessages(other, session.id, {}), { statusCode: 404 });
    await assert.rejects(() => service.deleteSession(other, session.id), { statusCode: 404 });
    const stored = await client.query('SELECT content_encrypted,metadata_encrypted FROM chatbot_turns WHERE session_id=$1', [session.id]);
    assert.equal(JSON.stringify(stored.rows).includes('support with sleep'), false);
    assert.equal(JSON.stringify(stored.rows).includes('test response'), false);
    await service.setConsent(mother, { enabled: true, policy_version: policy.POLICY_VERSION });
    await send('Please look at my trends');
    assert.equal(inputs.at(-1).context.mood.mean_rating, 4);
    assert.equal(inputs.at(-1).context.risk, null);
    assert.ok(inputs.at(-1).history.some((turn) => turn.content.includes('support with sleep')));
    const newSession = await service.createSession(mother, { language: 'roman_ur' });
    const sessionPage = await service.listSessions(mother, { limit: '1' });
    assert.equal(sessionPage.has_more, true);
    const nextSessionPage = await service.listSessions(mother, { limit: '1', before: sessionPage.next_cursor });
    assert.equal(nextSessionPage.sessions.length, 1);
    assert.notEqual(nextSessionPage.sessions[0].id, sessionPage.sessions[0].id);
    await service.sendMessage(mother, newSession.id, { message: 'mujhay neend mein mushkil hai', language: 'roman_ur', client_request_id: randomUUID() });
    assert.ok(inputs.at(-1).history.length > 0);
    await service.setConsent(mother, { enabled: false, policy_version: policy.POLICY_VERSION });
    await send('What can I do tonight?');
    assert.equal(inputs.at(-1).context.mood, undefined);
    assert.equal(inputs.at(-1).history.some((turn) => turn.role === 'assistant' && turn.content.includes('Personalized mean mood')), false);
    assert.deepEqual(inputs.at(-1).state, {});
    assert.ok((await service.listMessages(mother, session.id, {})).messages.some((turn) => turn.content.includes('Personalized mean mood')));
    await service.setConsent(mother, { enabled: true, policy_version: policy.POLICY_VERSION });
    model.reply = async (input) => {
      inputs.push(input);
      await service.setConsent(mother, { enabled: false, policy_version: policy.POLICY_VERSION });
      return { ...response(input.language), reply: 'PRIVATE_AGGREGATE_ANSWER_MUST_BE_DISCARDED' };
    };
    const changed = await send('Check current aggregate while consent changes');
    assert.equal(changed.status, 'failed');
    assert.equal(changed.reply.safety.reason, 'personalization_consent_changed');
    assert.equal(JSON.stringify(changed).includes('PRIVATE_AGGREGATE_ANSWER_MUST_BE_DISCARDED'), false);
    await client.query("UPDATE chatbot_consents SET enabled=TRUE,policy_version='older-policy' WHERE mother_id=$1", [mother]);
    const expiredPolicy = (await service.status(mother)).personalization;
    assert.equal(expiredPolicy.enabled, false);
    assert.equal(expiredPolicy.requires_reconsent, true);
    assert.equal(expiredPolicy.policy_version, 'older-policy');
    await service.setConsent(mother, { enabled: false, policy_version: policy.POLICY_VERSION });
    model.reply = async (input) => { inputs.push(input); return policy.fallback(input.language); };
    const retryId = randomUUID();
    const failed = await send('Please help me rest', retryId);
    assert.equal(failed.status, 'failed');
    assert.equal(failed.reply.mode, 'unavailable');
    model.reply = async (input) => { inputs.push(input); return response(input.language); };
    const retried = await send('Please help me rest', retryId);
    assert.equal(retried.status, 'complete');
    assert.deepEqual(retried.messages.map((turn) => turn.id), failed.messages.map((turn) => turn.id));
    const latest = await service.listMessages(mother, session.id, { limit: '3' });
    assert.equal(latest.messages.length, 3);
    assert.equal(latest.has_more, true);
    const older = await service.listMessages(mother, session.id, { before: latest.next_cursor, limit: '3' });
    assert.equal(older.messages.some((turn) => latest.messages.some((recent) => recent.id === turn.id)), false);
    const callsBeforeSafety = inputs.length;
    const privateSafety = await send('I might hurt my baby');
    assert.equal(privateSafety.reply.mode, 'safety');
    assert.equal(privateSafety.reply.safety.guardian_alert_allowed, false);
    assert.equal(inputs.length, callsBeforeSafety);
    const link = await client.query(`INSERT INTO guardian_links(mother_id,guardian_id,status,accepted_at) VALUES($1,$2,'active',NOW()) RETURNING id`, [mother, guardian]);
    const unshared = await send('I want to kill myself');
    assert.equal(unshared.reply.safety.guardian_alert_allowed, false);
    assert.equal(pushCount, 0);
    await client.query('UPDATE onboarding_data SET consent_tier2=TRUE WHERE user_id=$1', [mother]);
    const defaultPrivate = await send('I want to kill myself');
    assert.equal(defaultPrivate.reply.safety.guardian_alert_allowed, false);
    assert.equal(pushCount, 0);
    const crisis = require('../src/modules/crisis/crisis.service');
    await crisis.setGuardianSafety(mother, { guardian_link_id: link.rows[0].id, confirmed: true });
    const crisisId = randomUUID();
    const shared = await send('I want to kill myself', crisisId);
    assert.equal(shared.reply.safety.guardian_alert_allowed, true);
    assert.equal(pushCount, 1);
    await send('I want to kill myself', crisisId);
    assert.equal(pushCount, 1);
    const alerts = await client.query('SELECT message FROM guardian_alerts WHERE mother_id=$1', [mother]);
    assert.equal(alerts.rows.length, 1);
    assert.equal(alerts.rows[0].message.includes('kill myself'), false);
    for (const privateMessage of ['My husband hits me and I want to kill myself', 'I want to kill myself, do not notify my guardian', 'I might hurt my baby']) {
      const privateReply = await send(privateMessage);
      assert.equal(privateReply.reply.safety.guardian_alert_allowed, false, 'Confidential safety help must not become an automatic disclosure');
    }
    assert.equal(pushCount, 1);
    await crisis.setGuardianSafety(mother, { guardian_link_id: link.rows[0].id, confirmed: false });
    assert.equal((await send('I want to kill myself')).reply.safety.guardian_alert_allowed, false);
    assert.equal(pushCount, 1);
    const blockingId = randomUUID();
    await client.query(`INSERT INTO chatbot_requests(session_id,client_request_id,content_hash,language,status,lease_id,consent_snapshot_encrypted,context_encrypted)
      VALUES($1,$2,$3,'en','processing',$4,'synthetic','synthetic')`, [newSession.id, blockingId, 'x'.repeat(64), randomUUID()]);
    await assert.rejects(() => service.sendMessage(mother, newSession.id,
      { message: 'another message', language: 'en', client_request_id: randomUUID() }), { statusCode: 409 });
    await service.deleteSession(mother, session.id);
    assert.equal((await client.query('SELECT * FROM chatbot_turns WHERE session_id=$1', [session.id])).rows.length, 0);
    assert.equal((await client.query('SELECT * FROM chatbot_requests WHERE session_id=$1', [session.id])).rows.length, 0);
    assert.equal((await client.query('SELECT * FROM mood_checkins WHERE mother_id=$1', [mother])).rows.length, 1);
  } finally {
    model.reply = originalModel;
    push.processPendingSafely = originalPush;
    await client.query('ROLLBACK');
    db.query = originalQuery;
    db.withTransaction = originalTransaction;
    process.env = env;
    client.release();
    await db.pool.end();
  }
});
