const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const db = require('../src/config/database');
const nlp = require('../src/modules/mood/text_analysis.service');
const push = require('../src/modules/notifications/notification.service');
const { encryptMessage } = require('../src/modules/chat/chat_crypto');

test('M7 request advisory locks are nonblocking, replay-safe and cleaned up on every path', async (t) => {
  const mother = randomUUID(); const guardian = randomUUID(); const conversation = randomUUID();
  const request = { conversation_id: conversation, content: 'Private synthetic replay.', client_request_id: randomUUID() };
  const row = { id: randomUUID(), conversation_id: conversation, sender_id: mother,
    client_request_id: request.client_request_id, content_encrypted: encryptMessage(request.content),
    created_at_exact: '2026-10-12T08:30:20.123456Z', read_at: null,
    sentiment_score: 0, distress_score: 0, contains_danger: false, language: 'en', sentiment_label: 'neutral' };
  const originalConnect = db.pool.connect; const originalAnalyze = nlp.analyzeText;
  const originalPush = push.processPendingSafely;
  let analyses = 0; let settings = {}; let released = []; let statements = [];
  db.pool.connect = async () => ({
    query: async (sql) => {
      statements.push(sql);
      if (sql.includes('pg_try_advisory_lock')) return { rows: [{ acquired: settings.busy !== true }] };
      if (sql.includes('pg_advisory_unlock')) {
        if (settings.unlockError) throw new Error('synthetic unlock failure');
        return { rows: [{ released: settings.unlockFalse !== true }] };
      }
      if (['BEGIN', 'COMMIT', 'ROLLBACK'].includes(sql)) return { rows: [] };
      if (sql.includes('FROM guardian_links gl')) return { rows: settings.forbidden ? [] : [
        { link_id: randomUUID(), mother_id: mother, guardian_id: guardian, conversation_id: conversation },
      ] };
      if (sql.includes('cm.client_request_id')) return { rows: settings.noExisting || settings.newSend ? [] : [row] };
      if (settings.newSend) {
        if (sql.includes('INSERT INTO chat_messages')) return { rows: [{ ...row, contains_danger: true }] };
        if (sql.includes('INSERT INTO crisis_events') || sql.includes('INSERT INTO guardian_alerts')) return { rows: [{ id: randomUUID() }] };
        if (sql.includes('FROM chat_conversations') || sql.includes('UPDATE chat_conversations')) return { rows: [] };
      }
      throw new Error('Unexpected synthetic SQL');
    },
    release: (destroy) => released.push(destroy),
  });
  nlp.analyzeText = async () => {
    analyses++;
    if (settings.newSend) return { language: 'en', sentimentLabel: 'neutral', sentimentScore: 0,
      distressScore: 1, containsDanger: true, analysisVersion: 'synthetic-test', metadata: {} };
    throw new Error('Replay must not run NLP');
  };
  delete require.cache[require.resolve('../src/modules/chat/chat.service')];
  const service = require('../src/modules/chat/chat.service');
  const reset = (next) => { settings = next; statements = []; released = []; };
  try {
    await t.test('busy same-request retries return recoverable 503 before NLP or a transaction', async () => {
      reset({ busy: true });
      await assert.rejects(service.sendMessage(mother, 'mother', request), { statusCode: 503 });
      assert.deepEqual(released, [false]);
      assert.equal(statements.includes('BEGIN'), false);
      assert.equal(statements.some((sql) => sql.includes('pg_advisory_unlock')), false);
      assert.equal(analyses, 0);
    });
    await t.test('saved replay unlocks and releases normally without analysis', async () => {
      reset({});
      assert.equal((await service.sendMessage(mother, 'mother', request)).created_at, row.created_at_exact);
      assert.deepEqual(released, [false]);
      assert.equal(statements.includes('COMMIT'), true);
      assert.equal(statements.filter((sql) => sql.includes('pg_advisory_unlock')).length, 1);
      assert.equal(analyses, 0);
    });
    await t.test('failed or unsuccessful unlock destroys the lease rather than leaking a session lock', async () => {
      for (const settings of [{ unlockError: true }, { unlockFalse: true }]) {
        reset(settings);
        assert.equal((await service.sendMessage(mother, 'mother', request)).id, row.id);
        assert.deepEqual(released, [true]);
      }
    });
    await t.test('forbidden access rolls back before NLP and releases the lock', async () => {
      reset({ forbidden: true });
      await assert.rejects(service.sendMessage(mother, 'mother', request), { statusCode: 403 });
      assert.equal(statements.includes('ROLLBACK'), true);
      assert.equal(statements.filter((sql) => sql.includes('pg_advisory_unlock')).length, 1);
      assert.deepEqual(released, [false]);
      assert.equal(analyses, 0);
    });
    await t.test('changed content and old conversation retries are rejected before NLP', async () => {
      reset({});
      await assert.rejects(service.sendMessage(mother, 'mother', { ...request, content: 'Different synthetic text.' }), { statusCode: 409 });
      reset({});
      await assert.rejects(service.sendMessage(mother, 'mother', { ...request, conversation_id: randomUUID() }), { statusCode: 409 });
      assert.equal(analyses, 0);
    });
    await t.test('NLP runs only after precheck commits and its failure still releases the request lock', async () => {
      reset({ noExisting: true });
      await assert.rejects(service.sendMessage(mother, 'mother', request), /Replay must not run NLP/);
      assert.equal(analyses, 1);
      assert.equal(statements.filter((sql) => sql === 'BEGIN').length, 1);
      assert.equal(statements.filter((sql) => sql === 'COMMIT').length, 1);
      assert.equal(statements.includes('ROLLBACK'), false);
      assert.deepEqual(released, [false]);
    });
    await t.test('committed urgent messages release their lease and reply without waiting for a pending fake worker', async () => {
      reset({ newSend: true });
      let kicks = 0;
      push.processPendingSafely = () => {
        kicks++;
        assert.deepEqual(released, [false]);
        return new Promise(() => {});
      };
      const message = await service.sendMessage(mother, 'mother', request);
      assert.equal(message.id, row.id);
      assert.deepEqual(released, [false]);
      assert.equal(kicks, 1);
      reset({});
      await service.sendMessage(mother, 'mother', request);
      assert.equal(kicks, 1, 'A saved replay never nudges the worker a second time');
    });
  } finally {
    db.pool.connect = originalConnect; nlp.analyzeText = originalAnalyze;
    push.processPendingSafely = originalPush;
    delete require.cache[require.resolve('../src/modules/chat/chat.service')];
    await db.pool.end();
  }
});
