const { randomUUID: uuidv4 } = require('node:crypto');
const { withTransaction, pool } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { encryptMessage, decryptMessage } = require('./chat_crypto');
const { analyzeText } = require('../mood/text_analysis.service');
const pushNotifications = require('../notifications/notification.service');
const policy = require('./chat.policy');

// Preserve PostgreSQL microseconds: pg's default Date decoder loses the final three digits.
const MESSAGE_COLUMNS = `cm.*, to_char(cm.created_at AT TIME ZONE 'UTC',
  'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created_at_exact`;

function changed() { throw new AppError('The conversation has changed. Reload chat.', 409); }

async function resolveConversation(db, userId, role, expectedId = null) {
  if (!['mother', 'guardian'].includes(role)) throw new AppError('Chat is not available for this account.', 403);
  const idColumn = role === 'mother' ? 'gl.mother_id' : 'gl.guardian_id';
  const { rows } = await db.query(
    `SELECT gl.id AS link_id, gl.mother_id, gl.guardian_id, gl.guardian_name,
            od.full_name AS mother_name, cc.id AS conversation_id, cc.last_message_at
     FROM guardian_links gl
     JOIN users mother ON mother.id = gl.mother_id AND mother.is_active AND mother.onboarding_complete AND mother.role = 'mother'
     JOIN users guardian ON guardian.id = gl.guardian_id AND guardian.is_active AND guardian.onboarding_complete AND guardian.role = 'guardian'
     JOIN onboarding_data od ON od.user_id = gl.mother_id AND od.consent_tier1 AND od.consent_tier2
     LEFT JOIN chat_conversations cc ON cc.guardian_link_id = gl.id
     WHERE ${idColumn} = $1 AND gl.status = 'active'
       AND (cc.id IS NULL OR (cc.mother_id = gl.mother_id AND cc.guardian_id = gl.guardian_id))
     ORDER BY gl.accepted_at DESC NULLS LAST, gl.id DESC LIMIT 1
     FOR SHARE OF gl, mother, guardian, od`,
    [userId],
  );
  const link = rows[0];
  if (!link) throw new AppError('An active guardian link and sharing consent are required for chat.', 403);
  if (expectedId && expectedId !== link.conversation_id) changed();
  if (link.conversation_id) return link;
  const created = await db.query(
    `INSERT INTO chat_conversations (guardian_link_id, mother_id, guardian_id)
     VALUES ($1, $2, $3)
     ON CONFLICT (guardian_link_id) DO UPDATE SET guardian_link_id = EXCLUDED.guardian_link_id
     RETURNING id`,
    [link.link_id, link.mother_id, link.guardian_id],
  );
  return { ...link, conversation_id: created.rows[0].id };
}

function publicMessage(row, userId) {
  return {
    analysis_metadata: row.analysis_metadata || { sentiment_source: 'rules', clinical_validation: false },
    id: row.id,
    conversation_id: row.conversation_id,
    client_request_id: row.client_request_id,
    cursor: policy.encodeCursor(row.conversation_id, row),
    sender_id: row.sender_id,
    is_mine: row.sender_id === userId,
    content: decryptMessage(row.content_encrypted),
    language: row.language,
    sentiment_label: row.sentiment_label,
    sentiment_score: Number(row.sentiment_score),
    distress_score: Number(row.distress_score),
    contains_danger: row.contains_danger,
    created_at: row.created_at_exact,
    read_at: row.read_at,
  };
}

async function getStatus(userId, role) {
  try {
    return await withTransaction(async (client) => {
      const conversation = await resolveConversation(client, userId, role);
      const unread = await client.query(
        `SELECT COUNT(*)::int AS count FROM chat_messages
         WHERE conversation_id = $1 AND sender_id <> $2 AND read_at IS NULL`,
        [conversation.conversation_id, userId],
      );
      return {
        available: true,
        conversation_id: conversation.conversation_id,
        partner_name: role === 'mother' ? (conversation.guardian_name || 'Guardian') : (conversation.mother_name || 'Mother'),
        last_message_at: conversation.last_message_at,
        unread_count: unread.rows[0].count,
        privacy: 'Messages are encrypted at rest and never included in health reports.',
      };
    });
  } catch (error) {
    if (error.statusCode === 403) return { available: false, unread_count: 0 };
    throw error;
  }
}

// The legacy array API remains supported. New clients use tuple cursors below.
async function listMessages(userId, role, { before, after, limit = 30 }) {
  return withTransaction(async (client) => {
    const conversation = await resolveConversation(client, userId, role);
    const values = [conversation.conversation_id];
    const filters = [];
    if (before) { values.push(before); filters.push(`cm.created_at < $${values.length}`); }
    if (after) { values.push(after); filters.push(`cm.created_at > $${values.length}`); }
    values.push(limit);
    const { rows } = await client.query(
      `SELECT ${MESSAGE_COLUMNS} FROM chat_messages cm WHERE cm.conversation_id = $1
         ${filters.length ? `AND ${filters.join(' AND ')}` : ''}
       ORDER BY cm.created_at DESC, cm.id DESC LIMIT $${values.length}`,
      values,
    );
    return rows.reverse().map((row) => publicMessage(row, userId));
  });
}

async function listMessagePage(userId, role, data) {
  return withTransaction(async (client) => {
    const conversation = await resolveConversation(client, userId, role, data.conversation_id);
    const values = [conversation.conversation_id];
    const cursor = data.before || data.after;
    let filter = '';
    if (cursor) {
      values.push(cursor.created_at, cursor.id);
      filter = `AND (cm.created_at, cm.id) ${data.after ? '>' : '<'} ($2::timestamptz, $3::uuid)`;
    }
    values.push(data.limit + 1);
    const direction = data.after ? 'ASC' : 'DESC';
    const result = await client.query(
      `SELECT ${MESSAGE_COLUMNS} FROM chat_messages cm WHERE cm.conversation_id = $1
       ${filter} ORDER BY cm.created_at ${direction}, cm.id ${direction} LIMIT $${values.length}`,
      values,
    );
    const hasMore = result.rows.length > data.limit;
    const selected = result.rows.slice(0, data.limit);
    if (!data.after) selected.reverse();
    return {
      conversation_id: conversation.conversation_id,
      messages: selected.map((row) => publicMessage(row, userId)),
      older_cursor: selected.length ? policy.encodeCursor(conversation.conversation_id, selected[0]) : null,
      newer_cursor: selected.length ? policy.encodeCursor(conversation.conversation_id, selected[selected.length - 1])
        : !cursor ? policy.encodeCursor(conversation.conversation_id, {
          id: '00000000-0000-4000-8000-000000000000', created_at_exact: '0001-01-01T00:00:00.000000Z',
        }) : null,
      has_more: hasMore,
    };
  });
}

function replay(row, conversation, userId, content) {
  if (row.conversation_id !== conversation.conversation_id || decryptMessage(row.content_encrypted) !== content) changed();
  return publicMessage(row, userId);
}

async function existingRequest(client, userId, requestId) {
  const { rows } = await client.query(
    `SELECT ${MESSAGE_COLUMNS} FROM chat_messages cm
     WHERE cm.sender_id = $1 AND cm.client_request_id = $2`, [userId, requestId],
  );
  return rows[0];
}

async function transaction(client, operation) {
  await client.query('BEGIN');
  try {
    const result = await operation();
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
}

async function sendMessage(userId, role, input) {
  const data = policy.sendBody(input);
  const client = await pool.connect();
  const lockKey = `chat-request:${userId}:${data.client_request_id}`;
  let locked = false;
  let destroy = false;
  let pushNeeded = false;
  let committed = false;
  try {
    // Session lock spans NLP, but no transaction does. Concurrent replay never reruns analysis.
    const lock = await client.query('SELECT pg_try_advisory_lock(hashtextextended($1, 0)) AS acquired', [lockKey]);
    locked = lock.rows[0].acquired;
    if (!locked) throw new AppError('Message processing is busy. Retry with the same request ID.', 503);
    const checked = await transaction(client, async () => {
      const conversation = await resolveConversation(client, userId, role, data.conversation_id);
      const existing = await existingRequest(client, userId, data.client_request_id);
      return { conversation_id: conversation.conversation_id,
        saved: existing ? replay(existing, conversation, userId, data.content) : null };
    });
    if (checked.saved) return checked.saved;
    const analysis = await analyzeText(data.content);
    const message = await transaction(client, async () => {
      const conversation = await resolveConversation(client, userId, role, checked.conversation_id);
      // All writes in a conversation commit in timestamp order, including across server instances.
      await client.query('SELECT id FROM chat_conversations WHERE id = $1 FOR UPDATE', [conversation.conversation_id]);
      const existing = await existingRequest(client, userId, data.client_request_id);
      if (existing) return replay(existing, conversation, userId, data.content);
      const inserted = await client.query(
        `INSERT INTO chat_messages AS cm
           (id, conversation_id, sender_id, content_encrypted, language,
            sentiment_label, sentiment_score, distress_score, contains_danger,
            analysis_version, client_request_id, analysis_metadata, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,
           (SELECT GREATEST(clock_timestamp(), COALESCE(MAX(created_at) + INTERVAL '1 microsecond',
             '-infinity'::timestamptz)) FROM chat_messages WHERE conversation_id = $2))
         ON CONFLICT (sender_id, client_request_id) DO NOTHING
         RETURNING ${MESSAGE_COLUMNS}`,
        [uuidv4(), conversation.conversation_id, userId, encryptMessage(data.content),
          analysis.language, analysis.sentimentLabel, analysis.sentimentScore,
          analysis.distressScore, analysis.containsDanger, analysis.analysisVersion,
          data.client_request_id, JSON.stringify(analysis.metadata)],
      );
      if (!inserted.rows[0]) return replay(await existingRequest(client, userId, data.client_request_id), conversation, userId, data.content);
      const row = inserted.rows[0];
      await client.query('UPDATE chat_conversations SET last_message_at = $1::timestamptz WHERE id = $2',
        [row.created_at_exact, conversation.conversation_id]);
      if (role === 'mother' && analysis.containsDanger) {
        const event = await client.query(
          `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
           VALUES ($1, 'chat', $2, 'severe')
           ON CONFLICT (source_type, source_id) DO NOTHING RETURNING id`,
          [userId, row.id],
        );
        if (event.rows[0]) {
          // Migration 018 still suppresses insertion unless this exact active link was confirmed safe.
          const alert = await client.query(
            `INSERT INTO guardian_alerts (mother_id, guardian_id, crisis_event_id, alert_type, message)
             VALUES ($1, $2, $3, 'crisis',
               'URGENT: A serious safety indicator was detected. Please check on her immediately and use the crisis plan.')
             RETURNING id`, [conversation.mother_id, conversation.guardian_id, event.rows[0].id],
          );
          pushNeeded = alert.rows.length > 0;
        }
      }
      return publicMessage(row, userId);
    });
    committed = true;
    return message;
  } finally {
    if (locked) {
      try {
        const released = await client.query('SELECT pg_advisory_unlock(hashtextextended($1, 0)) AS released', [lockKey]);
        destroy = released.rows[0].released !== true;
      } catch { destroy = true; }
    }
    client.release(destroy);
    // Delivery is an independent durable-outbox job, never a dependency of the chat reply.
    if (committed && pushNeeded) {
      void Promise.resolve().then(() => pushNotifications.processPendingSafely()).catch(() => {});
    }
  }
}

async function markRead(userId, role, input = {}) {
  const data = policy.readBody(input);
  return withTransaction(async (client) => {
    const conversation = await resolveConversation(client, userId, role, data.conversation_id);
    const values = [conversation.conversation_id, userId];
    let bound = '';
    if (data.through) {
      values.push(data.through.created_at, data.through.id);
      bound = 'AND (created_at, id) <= ($3::timestamptz, $4::uuid)';
    }
    if (data.from) {
      values.push(data.from.created_at, data.from.id);
      bound += ' AND (created_at, id) >= ($5::timestamptz, $6::uuid)';
    }
    const result = await client.query(
      `UPDATE chat_messages SET read_at = clock_timestamp()
       WHERE conversation_id = $1 AND sender_id <> $2 AND read_at IS NULL ${bound}`, values,
    );
    return { updated: result.rowCount };
  });
}

module.exports = { getStatus, listMessages, listMessagePage, sendMessage, markRead,
  _private: { publicMessage, resolveConversation, MESSAGE_COLUMNS } };

