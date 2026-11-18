const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

test('M5 voice queue, encrypted draft, review, safe alerts, retry/cancel and withdrawal (rollback only)', {
  skip: process.env.RUN_TRANSCRIPTION_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  process.env.NLP_ENABLED = 'false';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  const db = require('../src/config/database');
  const connection = await db.pool.connect();
  const previous = { query: db.query, transaction: db.withTransaction };
  let asr, originalTranscribe, push, originalPush;
  try {
    await connection.query('BEGIN');
    if (!(await connection.query("SELECT to_regclass('journal_voice_transcriptions') AS table_name")).rows[0].table_name) {
      await connection.query(readFileSync(join(__dirname, '../migrations/020_voice_transcription_review.sql'), 'utf8'));
    }
    let queued = Promise.resolve();
    db.query = (...args) => {
      const operation = queued.then(() => connection.query(...args));
      queued = operation.catch(() => {});
      return operation;
    };
    db.withTransaction = (fn) => fn(connection);
    const mood = require('../src/modules/mood/mood.service');
    const service = require('../src/modules/mood/transcription.service');
    asr = require('../src/modules/mood/transcription.client');
    push = require('../src/modules/notifications/notification.service');
    originalTranscribe = asr.transcribe; originalPush = push.processPendingSafely;
    push.processPendingSafely = async () => ({ processed: 0 });
    const mother = randomUUID(), other = randomUUID(), guardian = randomUUID(), link = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [other, 'mother'], [guardian, 'guardian']]) {
      await connection.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 't' + id.replaceAll('-', '').slice(0, 13), 'test-only', role]);
      if (role === 'mother') await connection.query('INSERT INTO onboarding_data(user_id,consent_tier1,consent_tier2) VALUES($1,TRUE,TRUE)', [id]);
    }
    const audio = Buffer.from('RIFF1234WAVEsynthetic-audio-only');
    const save = () => mood.savePrivateVoiceJournal(mother, audio, { contentType: 'audio/wav', language: 'en', clientRequestId: randomUUID() });
    const first = await save();
    assert.equal((await connection.query('SELECT COUNT(*)::int AS n FROM journal_voice_transcriptions')).rows[0].n, 0, 'saving does not silently opt into ASR');
    assert.equal((await service.request(mother, first.id)).status, 'queued');
    assert.equal((await service.request(mother, first.id)).revision, 1, 'request retries do not duplicate or reset a live job');
    await assert.rejects(service.get(other, first.id), { statusCode: 404 });
    await assert.rejects(service.get(guardian, first.id), { statusCode: 403 });
    asr.transcribe = async (bytes) => {
      assert.deepEqual(bytes, audio);
      return { status: 'draft', text: 'I want to kill myself', language: 'en', model_version: 'synthetic-asr', review_required: true };
    };
    assert.equal(await service.processOne(), true);
    const draft = await service.get(mother, first.id);
    assert.equal(draft.status, 'review');
    assert.equal(draft.safety_hint, true);
    assert.ok(draft.draft.includes('kill myself'));
    const stored = (await connection.query('SELECT * FROM journal_voice_transcriptions WHERE journal_id=$1', [first.id])).rows[0];
    assert.equal(stored.draft_encrypted.includes('kill myself'), false);
    assert.equal((await mood.listJournals(mother, 10))[0].content, null, 'unconfirmed draft is not a searchable confirmed journal');
    assert.equal(Number((await connection.query('SELECT COUNT(*) FROM crisis_events WHERE mother_id=$1', [mother])).rows[0].count), 0);
    const safeConfirmation = { content: 'I feel calm and supported', revision: draft.revision, client_request_id: randomUUID() };
    assert.equal((await service.confirm(mother, first.id, safeConfirmation)).contains_danger, false);
    assert.equal((await service.confirm(mother, first.id, safeConfirmation)).confirmed, true);
    await assert.rejects(service.confirm(mother, first.id, { ...safeConfirmation, content: 'different' }), { statusCode: 409 });
    assert.equal((await mood.searchJournals(mother, 'calm', 10))[0].id, first.id);
    assert.equal((await mood.listJournals(mother, 10))[0].analysis_metadata.transcript_reviewed, true);
    assert.equal((await service.get(mother, first.id)).draft, null);

    await connection.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,invite_code,status,accepted_at)
      VALUES($1,$2,$3,$4,'active',NOW())`, [link, mother, guardian, randomUUID().replaceAll('-', '').slice(0, 12).toUpperCase()]);
    await connection.query(`INSERT INTO crisis_safety_plans(mother_id,safe_guardian_link_id,guardian_contact_confirmed,guardian_confirmed_at)
      VALUES($1,$2,TRUE,NOW())`, [mother, link]);
    const second = await save();
    await service.request(mother, second.id);
    await service.processOne();
    const harmful = { content: 'I want to kill myself', revision: 1, client_request_id: randomUUID() };
    await service.confirm(mother, second.id, harmful);
    await service.confirm(mother, second.id, harmful);
    const events = await connection.query("SELECT id FROM crisis_events WHERE mother_id=$1 AND source_type='voice_journal'", [mother]);
    assert.equal(events.rowCount, 1);
    const alerts = await connection.query('SELECT message FROM guardian_alerts WHERE crisis_event_id=$1', [events.rows[0].id]);
    assert.equal(alerts.rowCount, 1);
    assert.equal(JSON.stringify(alerts.rows).includes(harmful.content), false);

    const third = await save();
    await service.request(mother, third.id);
    asr.transcribe = async () => {
      await service.cancel(mother, third.id);
      await service.request(mother, third.id);
      return { status: 'draft', text: 'late old draft', language: 'en', model_version: 'synthetic-asr', review_required: true };
    };
    await service.processOne();
    assert.equal((await service.get(mother, third.id)).status, 'queued', 'cancelled/late callback cannot overwrite a new request');
    asr.transcribe = async () => {
      await connection.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [mother]);
      return { status: 'draft', text: 'must not persist after withdrawal', language: 'en', model_version: 'synthetic-asr', review_required: true };
    };
    await service.processOne();
    await assert.rejects(service.get(mother, third.id), { statusCode: 403 });
    const withheld = (await connection.query('SELECT status,draft_encrypted FROM journal_voice_transcriptions WHERE journal_id=$1', [third.id])).rows[0];
    assert.equal(withheld.status, 'failed');
    assert.equal(withheld.draft_encrypted, null);
    await connection.query('UPDATE onboarding_data SET consent_tier1=TRUE WHERE user_id=$1', [mother]);
    await service.request(mother, third.id);
    await connection.query(`UPDATE journal_voice_transcriptions SET status='processing',attempts=3,lease_token=gen_random_uuid(),
      lease_until=NOW()-INTERVAL '1 minute' WHERE journal_id=$1`, [third.id]);
    assert.equal(await service.processOne(), false);
    assert.equal((await service.get(mother, third.id)).status, 'failed', 'exhausted stale leases do not remain stuck forever');
    await mood.deleteJournal(mother, third.id);
    await assert.rejects(service.get(mother, third.id), { statusCode: 404 });
  } finally {
    if (asr) asr.transcribe = originalTranscribe;
    if (push) push.processPendingSafely = originalPush;
    await connection.query('ROLLBACK');
    db.query = previous.query; db.withTransaction = previous.transaction;
    connection.release(); await db.pool.end();
  }
});
