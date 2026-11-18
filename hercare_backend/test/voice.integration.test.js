const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('private voice storage, playback, ownership, and idempotency (rollback)', {
  skip: process.env.RUN_VOICE_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const originalQuery = database.query;
  const originalTransaction = database.withTransaction;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    const mood = require('../src/modules/mood/mood.service');
    const mother = randomUUID();
    const outsider = randomUUID();
    for (const id of [mother, outsider]) {
      await client.query(
        `INSERT INTO users(id, phone, password_hash, role, onboarding_complete)
         VALUES($1, $2, 'test-only', 'mother', TRUE)`,
        [id, `t${id.replaceAll('-', '').slice(0, 13)}`],
      );
    }
    const audio = Buffer.from('RIFF1234WAVEprivate test audio');
    const data = {
      contentType: 'audio/wav', language: 'en', clientRequestId: randomUUID(),
    };
    const saved = await mood.savePrivateVoiceJournal(mother, audio, data);
    assert.equal(saved.has_audio, true);
    assert.equal(saved.content, null);
    const repeated = await mood.savePrivateVoiceJournal(mother, audio, data);
    assert.equal(repeated.id, saved.id);
    const privateAudio = await mood.getPrivateVoiceAudio(mother, saved.id);
    assert.deepEqual(privateAudio.audio, audio);
    await assert.rejects(mood.getPrivateVoiceAudio(outsider, saved.id), /not found/);
    const listed = await mood.listJournals(mother, 10);
    assert.equal(listed.length, 1);
    assert.equal(listed[0].has_audio, true);
    assert.equal(Object.hasOwn(listed[0], 'voice_audio_encrypted'), false);
    await mood.deleteJournal(mother, saved.id);
    await assert.rejects(mood.getPrivateVoiceAudio(mother, saved.id), /not found/);
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    client.release();
    await database.pool.end();
  }
});
