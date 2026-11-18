const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M7 reliable chat pagination, replay, consent and visible-read checks (synthetic PostgreSQL rollback)', {
  skip: process.env.RUN_CHAT_DB_TEST !== '1',
}, async (t) => {
  require('dotenv').config();
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const originals = { query: db.query, transaction: db.withTransaction, connect: db.pool.connect };
  const text = require('../src/modules/mood/text_analysis.service');
  const push = require('../src/modules/notifications/notification.service');
  const originalAnalyze = text.analyzeText;
  const originalPush = push.processPendingSafely;
  let analyses = 0; let kicks = 0; let onAnalysis = null; let savepoint = 0;
  try {
    await client.query('BEGIN');
    db.query = (...args) => client.query(...args);
    db.withTransaction = (fn) => fn(client);
    // Keep every fixture inside the outer rollback; service transactions use SAVEPOINTs.
    db.pool.connect = async () => {
      const name = `chat_fixture_${++savepoint}`;
      return {
        query: (sql, values) => {
          if (sql === 'BEGIN') return client.query(`SAVEPOINT ${name}`);
          if (sql === 'COMMIT') return client.query(`RELEASE SAVEPOINT ${name}`);
          if (sql === 'ROLLBACK') return client.query(`ROLLBACK TO SAVEPOINT ${name}`);
          return client.query(sql, values);
        },
        release: () => {},
      };
    };
    text.analyzeText = async (content) => {
      analyses++;
      if (onAnalysis) await onAnalysis();
      return { language: 'en', sentimentLabel: 'neutral', sentimentScore: 0, distressScore: 0,
        containsDanger: content.includes('DANGER'), analysisVersion: 'synthetic-reliability-test',
        metadata: { sentiment_source: 'rules', clinical_validation: false } };
    };
    push.processPendingSafely = async () => { kicks++; };
    const chat = require('../src/modules/chat/chat.service');
    const policy = require('../src/modules/chat/chat.policy');
    const { encryptMessage } = require('../src/modules/chat/chat_crypto');
    const mother = randomUUID(); const guardian = randomUUID(); const link = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [guardian, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
        VALUES($1,$2,'synthetic-only',$3,TRUE)`, [id, 't' + id.replaceAll('-', '').slice(0, 12), role]);
    }
    await client.query(`INSERT INTO onboarding_data(user_id,age,months_since_birth,consent_tier1,consent_tier2)
      VALUES($1,28,3,TRUE,TRUE)`, [mother]);
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Synthetic guardian','husband','active',NOW())`, [link, mother, guardian]);
    const status = await chat.getStatus(mother, 'mother');
    const conversation = status.conversation_id;
    const page = (input = {}) => chat.listMessagePage(mother, 'mother', policy.pageQuery({ conversation_id: conversation, ...input }));
    let origin;
    await t.test('empty initial page establishes a forward origin without a fake message', async () => {
      const empty = await page();
      assert.equal(empty.messages.length, 0);
      assert.equal(empty.older_cursor, null);
      assert.equal(empty.has_more, false);
      origin = empty.newer_cursor;
      assert.equal(policy.decodeCursor(origin, conversation).created_at, '0001-01-01T00:00:00.000000Z');
    });
    const ids = Array.from({ length: 73 }, () => randomUUID()).sort();
    for (let i = 0; i < ids.length; i++) {
      await client.query(`INSERT INTO chat_messages(id,conversation_id,sender_id,content_encrypted,language,
        sentiment_label,sentiment_score,distress_score,contains_danger,analysis_version,client_request_id,created_at)
        VALUES($1,$2,$3,$4,'en','neutral',0,0,FALSE,'synthetic-test',$5,$6::timestamptz)`,
      [ids[i], conversation, guardian, encryptMessage('PRIVATE synthetic message ' + i), randomUUID(),
        i < 38 ? '2026-10-12T08:30:20.123456Z' : '2026-10-12T08:30:20.123457Z']);
    }
    await t.test('tuple backward pages cover same-timestamp boundaries without skips or duplicates', async () => {
      const seen = []; let cursor = null;
      do {
        const batch = await page({ limit: '17', ...(cursor ? { before: cursor } : {}) });
        assert.equal(batch.messages.every((message) => /^\d{4}-\d{2}-\d{2}T.*\.\d{6}Z$/.test(message.created_at)), true);
        assert.equal(batch.messages.every((message) => message.conversation_id === conversation && message.cursor), true);
        seen.push(...batch.messages.map((message) => message.id));
        cursor = batch.has_more ? batch.older_cursor : null;
      } while (cursor);
      assert.equal(seen.length, 73);
      assert.equal(new Set(seen).size, 73);
      assert.deepEqual(seen.sort(), ids);
    });
    await t.test('forward drain from empty origin returns oldest unseen pages even over 50 messages', async () => {
      const seen = []; let cursor = origin;
      while (true) {
        const batch = await page({ limit: '50', after: cursor });
        seen.push(...batch.messages.map((message) => message.id));
        if (batch.newer_cursor) cursor = batch.newer_cursor;
        if (!batch.has_more) break;
      }
      assert.deepEqual(seen, ids);
      assert.equal((await page({ after: cursor })).messages.length, 0);
    });
    await t.test('read acknowledgements stop at the visible exact tuple and never mark later arrivals', async () => {
      const visible = await page({ after: origin, limit: '17' });
      assert.equal((await chat.markRead(mother, 'mother', { conversation_id: conversation, through_cursor: visible.newer_cursor })).updated, 17);
      assert.equal((await chat.getStatus(mother, 'mother')).unread_count, 56);
      assert.equal((await chat.markRead(mother, 'mother', { conversation_id: conversation, through_cursor: visible.newer_cursor })).updated, 0);
    });
    await t.test('loaded-range acknowledgements leave older unloaded messages and later arrivals unread', async () => {
      await client.query('UPDATE chat_messages SET read_at=NULL WHERE conversation_id=$1', [conversation]);
      const loaded = await page({ limit: '17' });
      assert.equal((await chat.markRead(mother, 'mother', { conversation_id: conversation,
        from_cursor: loaded.older_cursor, through_cursor: loaded.newer_cursor })).updated, 17);
      assert.equal((await chat.getStatus(mother, 'mother')).unread_count, 56);
      assert.equal((await client.query('SELECT COUNT(*)::int AS count FROM chat_messages WHERE conversation_id=$1 AND read_at IS NULL AND created_at<$2::timestamptz',
        [conversation, loaded.messages[0].created_at])).rows[0].count, 38);
    });
    await t.test('a committed replay returns identical IDs and exact timestamps without NLP or alert repetition', async () => {
      const request = { conversation_id: conversation, content: '  Private replay text.  ', client_request_id: randomUUID() };
      const first = await chat.sendMessage(mother, 'mother', request);
      assert.equal(analyses, 1);
      assert.equal(first.client_request_id, request.client_request_id);
      assert.equal(first.content, 'Private replay text.');
      assert.deepEqual(await chat.sendMessage(mother, 'mother', request), first);
      assert.equal(analyses, 1);
      assert.equal(kicks, 0);
      await assert.rejects(chat.sendMessage(mother, 'mother', { ...request, content: 'Different text.' }), { statusCode: 409 });
      assert.equal(analyses, 1);
    });
    await t.test('a different database session holding the same request lock gets a recoverable busy response', async () => {
      const lease = await originals.connect.call(db.pool);
      const request = { conversation_id: conversation, content: 'Concurrent synthetic request.', client_request_id: randomUUID() };
      const key = `chat-request:${mother}:${request.client_request_id}`;
      const count = analyses;
      try {
        assert.equal((await lease.query('SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS acquired', [key])).rows[0].acquired, true);
        await assert.rejects(chat.sendMessage(mother, 'mother', request), { statusCode: 503 });
        assert.equal(analyses, count);
      } finally {
        await lease.query('SELECT pg_advisory_unlock(hashtextextended($1,0))', [key]);
        lease.release();
      }
    });
    await t.test('monotonic write clocks survive a future last timestamp and use exact microseconds', async () => {
      await client.query(`UPDATE chat_messages SET created_at='2099-01-01T00:00:00.999998Z' WHERE id=$1`, [ids[72]]);
      const first = await chat.sendMessage(guardian, 'guardian', { conversation_id: conversation, content: 'Support first.', client_request_id: randomUUID() });
      const second = await chat.sendMessage(guardian, 'guardian', { conversation_id: conversation, content: 'Support second.', client_request_id: randomUUID() });
      assert.equal(first.created_at, '2099-01-01T00:00:00.999999Z');
      assert.equal(second.created_at, '2099-01-01T00:00:01.000000Z');
      const next = await page({ after: first.cursor });
      assert.deepEqual(next.messages.map((message) => message.id), [second.id]);
    });
    await t.test('danger saves a private event but a replay cannot retroactively alert a newly safe guardian', async () => {
      const request = { conversation_id: conversation, content: 'PRIVATE DANGER synthetic.', client_request_id: randomUUID() };
      const first = await chat.sendMessage(mother, 'mother', request);
      const event = (await client.query("SELECT id FROM crisis_events WHERE source_type='chat' AND source_id=$1", [first.id])).rows[0];
      assert.ok(event);
      assert.equal((await client.query('SELECT id FROM guardian_alerts WHERE crisis_event_id=$1', [event.id])).rows.length, 0);
      await client.query(`INSERT INTO crisis_safety_plans(mother_id,safe_guardian_link_id,guardian_contact_confirmed)
        VALUES($1,$2,TRUE)`, [mother, link]);
      const count = analyses;
      await chat.sendMessage(mother, 'mother', request);
      assert.equal(analyses, count);
      assert.equal(kicks, 0);
      assert.equal((await client.query('SELECT id FROM guardian_alerts WHERE crisis_event_id=$1', [event.id])).rows.length, 0);
    });
    await t.test('consent withdrawn during analysis prevents final message insertion', async () => {
      onAnalysis = () => client.query('UPDATE onboarding_data SET consent_tier2=FALSE WHERE user_id=$1', [mother]);
      const request = { conversation_id: conversation, content: 'Private analysis race.', client_request_id: randomUUID() };
      await assert.rejects(chat.sendMessage(mother, 'mother', request), { statusCode: 403 });
      onAnalysis = null;
      assert.equal((await client.query('SELECT id FROM chat_messages WHERE sender_id=$1 AND client_request_id=$2', [mother, request.client_request_id])).rows.length, 0);
      await client.query('UPDATE onboarding_data SET consent_tier2=TRUE WHERE user_id=$1', [mother]);
    });
    await t.test('legacy sends stay pinned to the initial link if replacement happens during analysis', async () => {
      const replacement = randomUUID();
      onAnalysis = async () => {
        await client.query("UPDATE guardian_links SET status='revoked' WHERE id=$1", [link]);
        await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
          VALUES($1,$2,$3,'Race replacement','husband','active',clock_timestamp())`, [replacement, mother, guardian]);
      };
      const request = { content: 'Legacy private link race.', client_request_id: randomUUID() };
      await assert.rejects(chat.sendMessage(mother, 'mother', request), { statusCode: 409 });
      onAnalysis = null;
      assert.equal((await client.query('SELECT id FROM chat_messages WHERE sender_id=$1 AND client_request_id=$2', [mother, request.client_request_id])).rows.length, 0);
      await client.query('DELETE FROM guardian_links WHERE id=$1', [replacement]);
      await client.query("UPDATE guardian_links SET status='active' WHERE id=$1", [link]);
    });
    await t.test('inactive or changed-role participants and Tier 1 withdrawal stop reads and sends before NLP', async () => {
      const count = analyses;
      const checkBlocked = async () => {
        assert.equal((await chat.getStatus(mother, 'mother')).available, false);
        await assert.rejects(page(), { statusCode: 403 });
        await assert.rejects(chat.markRead(mother, 'mother', { conversation_id: conversation }), { statusCode: 403 });
        await assert.rejects(chat.sendMessage(mother, 'mother', { conversation_id: conversation, content: 'Blocked.', client_request_id: randomUUID() }), { statusCode: 403 });
        assert.equal(analyses, count);
      };
      await client.query('UPDATE users SET is_active=FALSE WHERE id=$1', [guardian]);
      await checkBlocked();
      await client.query("UPDATE users SET is_active=TRUE,role='mother' WHERE id=$1", [guardian]);
      await checkBlocked();
      await client.query("UPDATE users SET role='guardian' WHERE id=$1", [guardian]);
      await client.query('UPDATE users SET onboarding_complete=FALSE WHERE id=$1', [guardian]);
      await checkBlocked();
      await client.query('UPDATE users SET onboarding_complete=TRUE WHERE id=$1', [guardian]);
      await client.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [mother]);
      await checkBlocked();
      await client.query('UPDATE onboarding_data SET consent_tier1=TRUE WHERE user_id=$1', [mother]);
    });
    await t.test('replacement link cannot expose/replay/read prior conversation even to the same guardian', async () => {
      const old = (await chat.listMessages(mother, 'mother', {})).find((message) => message.is_mine);
      await client.query("UPDATE guardian_links SET status='revoked' WHERE id=$1", [link]);
      await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
        VALUES($1,$2,$3,'Replacement synthetic guardian','husband','active',clock_timestamp())`, [randomUUID(), mother, guardian]);
      const current = await chat.getStatus(mother, 'mother');
      assert.notEqual(current.conversation_id, conversation);
      await assert.rejects(page(), { statusCode: 409 });
      await assert.rejects(chat.markRead(mother, 'mother', { conversation_id: conversation, through_cursor: old.cursor }), { statusCode: 409 });
      const count = analyses;
      await assert.rejects(chat.sendMessage(mother, 'mother', { content: old.content, client_request_id: old.client_request_id }), { statusCode: 409 });
      assert.equal(analyses, count);
      assert.deepEqual(await chat.listMessages(mother, 'mother', {}), []);
    });
  } finally {
    await client.query('ROLLBACK');
    db.query = originals.query; db.withTransaction = originals.transaction; db.pool.connect = originals.connect;
    text.analyzeText = originalAnalyze; push.processPendingSafely = originalPush;
    client.release();
    await db.pool.end();
  }
});
