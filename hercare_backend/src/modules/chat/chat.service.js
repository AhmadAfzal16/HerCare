const { v4: uuidv4 } = require('uuid');
const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { encryptMessage, decryptMessage } = require('./chat_crypto');
const { analyzeMessage } = require('./chat_analysis');

async function resolveConversation(db, userId, role, create = true) {
  if (!['mother', 'guardian'].includes(role)) throw new AppError('Chat is not available for this account.', 403);
  const idColumn = role === 'mother' ? 'gl.mother_id' : 'gl.guardian_id';
  const { rows } = await db.query(
    `SELECT gl.id AS link_id, gl.mother_id, gl.guardian_id,
            gl.guardian_name, od.full_name AS mother_name,
            od.consent_tier2, cc.id AS conversation_id,
            cc.last_message_at
     FROM guardian_links gl
     JOIN onboarding_data od ON od.user_id = gl.mother_id
     LEFT JOIN chat_conversations cc ON cc.guardian_link_id = gl.id
     WHERE ${idColumn} = $1 AND gl.status = 'active'
       AND gl.guardian_id IS NOT NULL AND od.consent_tier2 = TRUE
     ORDER BY gl.accepted_at DESC LIMIT 1`,
    [userId],
  );
  const link = rows[0];
  if (!link) throw new AppError('An active guardian link and sharing consent are required for chat.', 403);
  if (link.conversation_id || !create) return link;
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
    id: row.id,
    sender_id: row.sender_id,
    is_mine: row.sender_id === userId,
    content: decryptMessage(row.content_encrypted),
    language: row.language,
    sentiment_label: row.sentiment_label,
    sentiment_score: Number(row.sentiment_score),
    distress_score: Number(row.distress_score),
    contains_danger: row.contains_danger,
    created_at: row.created_at,
    read_at: row.read_at,
  };
}

async function getStatus(userId, role) {
  try {
    const conversation = await resolveConversation({ query }, userId, role);
    const partnerName = role === 'mother'
      ? (conversation.guardian_name || 'Guardian')
      : (conversation.mother_name || 'Mother');
    const unread = await query(
      `SELECT COUNT(*)::int AS count FROM chat_messages
       WHERE conversation_id = $1 AND sender_id <> $2 AND read_at IS NULL`,
      [conversation.conversation_id, userId],
    );
    return {
      available: true,
      conversation_id: conversation.conversation_id,
      partner_name: partnerName,
      last_message_at: conversation.last_message_at,
      unread_count: unread.rows[0].count,
      privacy: 'Messages are encrypted at rest and never included in health reports.',
    };
  } catch (error) {
    if (error.statusCode === 403) return { available: false, unread_count: 0 };
    throw error;
  }
}

async function listMessages(userId, role, { before, after, limit = 30 }) {
  const conversation = await resolveConversation({ query }, userId, role);
  const values = [conversation.conversation_id];
  const filters = [];
  if (before) { values.push(before); filters.push(`created_at < $${values.length}`); }
  if (after) { values.push(after); filters.push(`created_at > $${values.length}`); }
  values.push(limit);
  const { rows } = await query(
    `SELECT * FROM chat_messages WHERE conversation_id = $1
       ${filters.length ? `AND ${filters.join(' AND ')}` : ''}
     ORDER BY created_at DESC, id DESC LIMIT $${values.length}`,
    values,
  );
  return rows.reverse().map((row) => publicMessage(row, userId));
}

async function sendMessage(userId, role, data) {
  const content = data.content.trim();
  const analysis = analyzeMessage(content);
  return withTransaction(async (client) => {
    const conversation = await resolveConversation(client, userId, role);
    const id = uuidv4();
    const inserted = await client.query(
      `INSERT INTO chat_messages
         (id, conversation_id, sender_id, content_encrypted, language,
          sentiment_label, sentiment_score, distress_score, contains_danger,
          analysis_version, client_request_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       ON CONFLICT (sender_id, client_request_id) DO NOTHING
       RETURNING *`,
      [id, conversation.conversation_id, userId, encryptMessage(content),
        analysis.language, analysis.sentimentLabel, analysis.sentimentScore,
        analysis.distressScore, analysis.containsDanger, analysis.analysisVersion,
        data.client_request_id],
    );
    let row = inserted.rows[0];
    if (!row) {
      const existing = await client.query(
        'SELECT * FROM chat_messages WHERE sender_id = $1 AND client_request_id = $2',
        [userId, data.client_request_id],
      );
      row = existing.rows[0];
    } else {
      await client.query(
        'UPDATE chat_conversations SET last_message_at = $1 WHERE id = $2',
        [row.created_at, conversation.conversation_id],
      );
      if (role === 'mother' && analysis.containsDanger) {
        const event = await client.query(
          `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
           VALUES ($1, 'chat', $2, 'severe')
           ON CONFLICT (source_type, source_id) DO NOTHING RETURNING id`,
          [userId, row.id],
        );
        if (event.rows[0]) {
          await client.query(
            `INSERT INTO guardian_alerts (mother_id, guardian_id, alert_type, message)
             VALUES ($1, $2, 'crisis',
               'URGENT: A serious safety indicator was detected. Please check on her immediately and use the crisis plan.')`,
            [conversation.mother_id, conversation.guardian_id],
          );
        }
      }
    }
    return publicMessage(row, userId);
  });
}

async function markRead(userId, role) {
  const conversation = await resolveConversation({ query }, userId, role);
  const result = await query(
    `UPDATE chat_messages SET read_at = NOW()
     WHERE conversation_id = $1 AND sender_id <> $2 AND read_at IS NULL`,
    [conversation.conversation_id, userId],
  );
  return { updated: result.rowCount };
}

module.exports = { getStatus, listMessages, sendMessage, markRead, _private: { publicMessage } };

