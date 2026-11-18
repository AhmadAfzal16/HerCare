const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { rollbackConnection } = require('./helpers/rollback_connection');

test('M2/M3/M5/M7/M9 database workflow and privacy audit (rollback only, no push delivery)', {
  skip: process.env.RUN_MODULE_DB_TEST !== '1',
}, async (t) => {
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const originalQuery = database.query;
  const originalTransaction = database.withTransaction;
  const originalConnect = database.pool.connect;
  const push = require('../src/modules/notifications/notification.service');
  const originalPush = push.processPendingSafely;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    database.pool.connect = rollbackConnection(client);
    push.processPendingSafely = async () => {};
    const guardian = require('../src/modules/guardian/guardian.service');
    const screening = require('../src/modules/screening/screening.service');
    const mood = require('../src/modules/mood/mood.service');
    const chat = require('../src/modules/chat/chat.service');
    const therapy = require('../src/modules/therapy/therapy.service');
    const ids = [randomUUID(), randomUUID(), randomUUID()];
    for (let i = 0; i < ids.length; i++) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [ids[i], `t${ids[i].replaceAll('-', '').slice(0, 13)}`, 'test-only', i === 1 ? 'guardian' : 'mother']);
    }
    const [mother, partner, outsider] = ids;
    await client.query('INSERT INTO onboarding_data(user_id,consent_tier1,consent_tier2) VALUES($1,TRUE,TRUE)', [mother]);
    const invite = await guardian.generateInvite(mother);
    await guardian.acceptInvite(partner, invite.invite_code, 'Test guardian', 'husband');
    assert.ok(await guardian.getLink(partner, 'guardian'));
    const safeLink = await guardian.getLink(partner, 'guardian');
    const crisis = require('../src/modules/crisis/crisis.service');
    await crisis.setGuardianSafety(mother, { guardian_link_id: safeLink.id, confirmed: true });
    const start = await screening.startAssessment(mother, { instrument_type: 'phq9', language: 'en', client_request_id: randomUUID() });
    const answers = Array.from({ length: 9 }, (_, i) => ({ question_number: i + 1, option_index: i === 8 ? 1 : 0 }));
    const assessed = await screening.submitAssessment(mother, start.id, answers);
    assert.equal(assessed.total_score, 1);
    assert.equal(assessed.self_harm_positive, true);
    await assert.rejects(screening.getAssessment(outsider, start.id), /not found/);
    const count = async () => (await client.query('SELECT COUNT(*)::int AS count FROM guardian_alerts WHERE mother_id=$1', [mother])).rows[0].count;
    const alertsBeforeRetry = await count();
    assert.equal(alertsBeforeRetry, 1, 'A safety-positive screen creates one event-linked alert for the explicitly safe guardian');
    await screening.submitAssessment(mother, start.id, answers);
    t.diagnostic(`Screening retry alert-count audit: before=${alertsBeforeRetry}, after=${await count()}`);
    assert.equal(await count(), alertsBeforeRetry);
    const day = new Date().toISOString().slice(0, 10);
    const checkin = await mood.saveCheckin(mother, day, { mood_rating: 4, energy_level: 3, sleep_quality: 3, social_support: 5, client_request_id: randomUUID() });
    assert.equal(checkin.composite_score, 3.8);
    assert.equal(await mood.getCheckin(outsider, day), null);
    const journal = await mood.createTextJournal(mother, { content: 'Private audit text: feeling supported.', client_request_id: randomUUID() });
    assert.ok(journal.id);
    assert.equal((await mood.listJournals(outsider, 20)).length, 0);
    const reports = await guardian.getReports(partner, 'guardian', 'daily', 7);
    assert.equal(JSON.stringify(reports).includes('Private audit text'), false);
    const request = { content: 'A private supportive conversation.', client_request_id: randomUUID() };
    const message = await chat.sendMessage(mother, 'mother', request);
    assert.equal((await chat.sendMessage(mother, 'mother', request)).id, message.id);
    assert.equal((await chat.listMessages(partner, 'guardian', {}))[0].content, request.content);
    await assert.rejects(chat.listMessages(outsider, 'mother', {}), /active guardian link/);
    const activity = { activity_type: 'breathing', activity_id: 'breathing_478', duration_seconds: 60, mood_before: 2, mood_after: 3, completed: true, client_request_id: randomUUID() };
    const recorded = await therapy.recordSession(mother, 'mother', activity);
    assert.equal((await therapy.recordSession(mother, 'mother', activity)).id, recorded.id);
    assert.equal(recorded.mood_change, 1);
    await assert.rejects(therapy.getHistory(partner, 'guardian'), /mother accounts/);
    await guardian.revokeLink(mother);
    await assert.rejects(chat.listMessages(partner, 'guardian', {}), /active guardian link/);
    await assert.rejects(guardian.getReports(partner, 'guardian'), /linked|active/i);
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    database.pool.connect = originalConnect;
    push.processPendingSafely = originalPush;
    client.release();
    await database.pool.end();
  }
});
