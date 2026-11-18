const { randomUUID } = require('node:crypto');
const db = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const crypto = require('./chatbot.crypto');
const policy = require('./chatbot.policy');
const model = require('./chatbot.client');
const contextBuilder = require('./chatbot.context');
const push = require('../notifications/notification.service');
const m4Text = require('../risk/m4.text');

function scope(motherId, sessionId, suffix) { return `${motherId}:${sessionId}:${suffix}`; }
function publicConsent(row) {
  return { enabled: row?.enabled === true && row.policy_version === policy.POLICY_VERSION,
    policy_version: row?.policy_version || policy.POLICY_VERSION, revision: row?.revision || 0,
    requires_reconsent: row?.enabled === true && row.policy_version !== policy.POLICY_VERSION, granted_at: row?.granted_at || null,
    updated_at: row?.updated_at || null, description: 'Optional own aggregate scores only; no journal, guardian message or audio contents. Not research/training consent. Withdrawal stops future lookups; previous replies remain in history until deleted.' };
}
async function authorize(client, motherId) {
  const { rows } = await client.query(`SELECT u.id FROM users u JOIN onboarding_data o ON o.user_id=u.id
    WHERE u.id=$1 AND u.is_active AND u.role='mother' AND o.consent_tier1`, [motherId]);
  if (!rows.length) throw new AppError('An active mother account and basic consent are required.', 403);
}
async function ownSession(client, motherId, sessionId, lock = false) {
  const { rows } = await client.query(`SELECT * FROM chatbot_sessions WHERE id=$1 AND mother_id=$2 ${lock ? 'FOR UPDATE' : ''}`, [sessionId, motherId]);
  if (!rows[0]) throw new AppError('Conversation not found.', 404);
  return rows[0];
}
function publicSession(row) {
  return { id: row.id, language: row.language, created_at: row.created_at, updated_at: row.updated_at, last_message_at: row.last_message_at };
}
function publicTurn(row, motherId) {
  return { id: row.id, role: row.role, language: row.language, created_at: row.created_at,
    content: crypto.decrypt(row.content_encrypted, scope(motherId, row.session_id, `turn:${row.id}`)),
    ...(row.metadata_encrypted ? { reply_metadata: JSON.parse(crypto.decrypt(row.metadata_encrypted, scope(motherId, row.session_id, `metadata:${row.id}`))) } : {}) };
}
async function status(motherId) {
  await authorize(db, motherId);
  const result = await db.query('SELECT * FROM chatbot_consents WHERE mother_id=$1', [motherId]);
  return { available: true, personalization: publicConsent(result.rows[0]), history_encrypted: true, clinical_validation: false,
    history_policy: 'Your own conversation history is used for continuity. Delete a conversation to remove its server copy. No automatic model training.' };
}
async function setConsent(motherId, body) {
  const data = policy.consent(body);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const result = await client.query(`INSERT INTO chatbot_consents(mother_id,enabled,policy_version,granted_at,revoked_at)
      VALUES($1,$2,$3,CASE WHEN $2 THEN NOW() ELSE NULL END,CASE WHEN $2 THEN NULL ELSE NOW() END)
      ON CONFLICT(mother_id) DO UPDATE SET enabled=EXCLUDED.enabled,policy_version=EXCLUDED.policy_version,
        granted_at=CASE WHEN EXCLUDED.enabled AND (NOT chatbot_consents.enabled OR chatbot_consents.policy_version<>EXCLUDED.policy_version)
          THEN NOW() ELSE chatbot_consents.granted_at END,
        revoked_at=CASE WHEN EXCLUDED.enabled THEN NULL ELSE NOW() END,revision=chatbot_consents.revision+1,updated_at=NOW() RETURNING *`,
    [motherId, data.enabled, policy.POLICY_VERSION]);
    if (!data.enabled) await client.query('UPDATE chatbot_sessions SET state_encrypted=NULL,state_personalized=FALSE WHERE mother_id=$1', [motherId]);
    return publicConsent(result.rows[0]);
  });
}
async function createSession(motherId, body) {
  const data = policy.session(body);
  await authorize(db, motherId);
  const { rows } = await db.query('INSERT INTO chatbot_sessions(mother_id,language) VALUES($1,$2) RETURNING *', [motherId, data.language]);
  return publicSession(rows[0]);
}
async function listSessions(motherId, options) {
  const page = policy.pagination(options);
  await authorize(db, motherId);
  const { rows } = await db.query(`SELECT * FROM chatbot_sessions WHERE mother_id=$1
    AND ($2::timestamptz IS NULL OR (created_at,id)<($2::timestamptz,$3::uuid))
    ORDER BY created_at DESC,id DESC LIMIT $4`, [motherId, page.before?.created_at || null, page.before?.id || null, page.limit + 1]);
  const selected = rows.slice(0, page.limit);
  return { sessions: selected.map(publicSession), has_more: rows.length > page.limit,
    next_cursor: rows.length > page.limit ? policy.cursor(selected.at(-1)) : null };
}
async function listMessages(motherId, sessionId, options) {
  policy.id(sessionId);
  const page = policy.pagination(options, 50);
  await authorize(db, motherId);
  const session = await ownSession(db, motherId, sessionId);
  const { rows } = await db.query(`SELECT * FROM chatbot_turns WHERE session_id=$1
    AND ($2::bigint IS NULL OR ordinal<$2::bigint)
    AND ($3::timestamptz IS NULL OR created_at<$3::timestamptz)
    ORDER BY ordinal DESC LIMIT $4`, [sessionId, page.before?.ordinal || null,
    page.before && !page.before.ordinal ? page.before.created_at : null, page.limit + 1]);
  const selected = rows.slice(0, page.limit);
  return { session: publicSession(session), messages: selected.slice().reverse().map((row) => publicTurn(row, motherId)),
    has_more: rows.length > page.limit, next_cursor: rows.length > page.limit ? policy.cursor(selected.at(-1)) : null };
}
async function deleteSession(motherId, sessionId) {
  policy.id(sessionId);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    await ownSession(client, motherId, sessionId, true);
    await client.query('DELETE FROM chatbot_sessions WHERE id=$1 AND mother_id=$2', [sessionId, motherId]);
    return { deleted: true };
  });
}
async function exchange(client, motherId, request) {
  const turns = await client.query('SELECT * FROM chatbot_turns WHERE request_id=$1 ORDER BY ordinal', [request.id]);
  return { session_id: request.session_id, request_id: request.client_request_id, status: request.status,
    messages: turns.rows.map((row) => publicTurn(row, motherId)),
    reply: request.reply_encrypted ? JSON.parse(crypto.decrypt(request.reply_encrypted, scope(motherId, request.session_id, `reply:${request.id}`))) : null };
}
async function history(client, motherId, sessionId, requestId, personalized) {
  const current = await client.query(`SELECT t.* FROM chatbot_turns t JOIN chatbot_requests r ON r.id=t.request_id
    WHERE t.session_id=$1 AND t.request_id<>$2 AND r.status='complete'
    AND ($3 OR t.role='user' OR NOT r.personalization_used) ORDER BY t.ordinal DESC LIMIT 12`, [sessionId, requestId, personalized]);
  const previous = await client.query(`SELECT t.* FROM chatbot_turns t JOIN chatbot_sessions s ON s.id=t.session_id
    JOIN chatbot_requests r ON r.id=t.request_id WHERE s.mother_id=$1 AND s.id<>$2 AND r.status='complete'
    AND ($3 OR t.role='user' OR NOT r.personalization_used)
    AND t.created_at>NOW()-INTERVAL '30 days' ORDER BY t.ordinal DESC LIMIT 8`, [motherId, sessionId, personalized]);
  return [...previous.rows.reverse(), ...current.rows.reverse()].map((row) => ({ role: row.role,
    content: crypto.decrypt(row.content_encrypted, scope(motherId, row.session_id, `turn:${row.id}`)).slice(0, 4000) }));
}
async function sendMessage(motherId, sessionId, body) {
  policy.id(sessionId);
  const data = policy.message(body);
  const safety = policy.inspectSafety(data.message);
  const hash = crypto.fingerprint(`${sessionId}:${data.language}:${data.message}`);
  const reserved = await db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const session = await ownSession(client, motherId, sessionId, true);
    const existing = await client.query('SELECT * FROM chatbot_requests WHERE session_id=$1 AND client_request_id=$2', [sessionId, data.client_request_id]);
    let request = existing.rows[0];
    if (request && request.content_hash !== hash) throw new AppError('This request identifier was already used for a different message.', 409);
    if (request?.status === 'complete') return { cached: await exchange(client, motherId, request) };
    const processing = await client.query("SELECT * FROM chatbot_requests WHERE session_id=$1 AND status='processing'", [sessionId]);
    if (processing.rows[0] && Date.now() - new Date(processing.rows[0].lease_started_at) < 90000) {
      throw new AppError('A reply is being prepared. Please wait before sending or retrying.', 409);
    }
    if (processing.rows[0]) await client.query("UPDATE chatbot_requests SET status='failed' WHERE id=$1", [processing.rows[0].id]);
    const result = await client.query('SELECT * FROM chatbot_consents WHERE mother_id=$1 FOR SHARE', [motherId]);
    const consent = publicConsent(result.rows[0]);
    const context = await contextBuilder.aggregate(client, motherId, consent.enabled && !safety.requires_help);
    const leaseId = randomUUID();
    const requestId = request?.id || randomUUID();
    if (request) {
      const updated = await client.query(`UPDATE chatbot_requests SET status='processing',lease_id=$2,lease_started_at=NOW(),
        consent_snapshot_encrypted=$3,context_encrypted=$4,personalization_used=$5,completed_at=NULL WHERE id=$1 RETURNING *`,
      [request.id, leaseId, crypto.encrypt(JSON.stringify(consent), scope(motherId, sessionId, `consent:${requestId}`)),
        crypto.encrypt(JSON.stringify(context), scope(motherId, sessionId, `context:${requestId}`)), context.personalization_enabled]);
      request = updated.rows[0];
    } else {
      const inserted = await client.query(`INSERT INTO chatbot_requests(id,session_id,client_request_id,content_hash,language,status,lease_id,consent_snapshot_encrypted,context_encrypted,personalization_used)
        VALUES($1,$2,$3,$4,$5,'processing',$6,$7,$8,$9) RETURNING *`, [requestId, sessionId, data.client_request_id, hash, data.language, leaseId,
        crypto.encrypt(JSON.stringify(consent), scope(motherId, sessionId, `consent:${requestId}`)),
        crypto.encrypt(JSON.stringify(context), scope(motherId, sessionId, `context:${requestId}`)), context.personalization_enabled]);
      request = inserted.rows[0];
      const userId = randomUUID();
      await client.query(`INSERT INTO chatbot_turns(id,session_id,request_id,role,language,content_encrypted)
        VALUES($1,$2,$3,'user',$4,$5)`, [userId, sessionId, requestId, data.language, crypto.encrypt(data.message, scope(motherId, sessionId, `turn:${userId}`))]);
      await m4Text.capture(client, motherId, 'hum_raaz', requestId, data.message, safety.requires_help);
    }
    return { request, consent, context, history: await history(client, motherId, sessionId, requestId, context.personalization_enabled),
      state: session.state_encrypted && (context.personalization_enabled || !session.state_personalized)
        ? JSON.parse(crypto.decrypt(session.state_encrypted, scope(motherId, sessionId, 'state'))) : {} };
  });
  if (reserved.cached) return reserved.cached;
  // Recheck immediately before inference. Withdrawal cannot unsend an already-running
  // local request; finalization below additionally discards its aggregate-based answer.
  const beforeInference = await db.query('SELECT * FROM chatbot_consents WHERE mother_id=$1', [motherId]);
  const currentConsent = publicConsent(beforeInference.rows[0]);
  let privacyChanged = reserved.context.personalization_enabled && (!currentConsent.enabled
    || currentConsent.revision !== reserved.consent.revision);
  let reply = safety.requires_help ? policy.fallback(data.language, safety)
    : privacyChanged ? policy.fallback(data.language)
    : await model.reply({ message: data.message, language: data.language, history: reserved.history, context: reserved.context, state: reserved.state });
  let alertCreated = false;
  const output = await db.withTransaction(async (client) => {
    await authorize(client, motherId);
    await ownSession(client, motherId, sessionId, true);
    const current = await client.query('SELECT * FROM chatbot_requests WHERE id=$1 FOR UPDATE', [reserved.request.id]);
    if (!current.rows[0] || current.rows[0].lease_id !== reserved.request.lease_id || current.rows[0].status !== 'processing') {
      throw new AppError('This reply attempt expired. Retry the original message.', 409);
    }
    const finalConsent = await client.query('SELECT * FROM chatbot_consents WHERE mother_id=$1 FOR SHARE', [motherId]);
    const activeConsent = publicConsent(finalConsent.rows[0]);
    privacyChanged = privacyChanged || (reserved.context.personalization_enabled && (!activeConsent.enabled
      || activeConsent.revision !== reserved.consent.revision));
    if (privacyChanged) {
      reply = policy.privacyFallback(data.language);
      // Erase the unused in-flight aggregate snapshot after withdrawing consent.
      await client.query('UPDATE chatbot_requests SET personalization_used=FALSE,context_encrypted=$2 WHERE id=$1',
        [reserved.request.id, crypto.encrypt(JSON.stringify({ personalization_enabled: false, as_of: new Date().toISOString() }),
          scope(motherId, sessionId, `context:${reserved.request.id}`))]);
    }
    reply.personalization_used = reserved.context.personalization_enabled && !privacyChanged;
    if (safety.requires_help || reply.safety.requires_help) {
      const event = await client.query(`INSERT INTO crisis_events(mother_id,source_type,source_id,severity)
        VALUES($1,'chatbot',$2,$3) ON CONFLICT(source_type,source_id) DO NOTHING RETURNING id`,
      [motherId, reserved.request.id, safety.alert_worthy ? 'severe' : 'high']);
      // M10's database policy requires the mother's separate, current-link-bound
      // safe-recipient confirmation. Tier2 or a model-generated flag alone is not
      // permission to disclose; only explicit personal self-harm cues reach here.
      if (event.rows.length && safety.alert_worthy) {
        const link = await client.query(`SELECT gl.guardian_id FROM guardian_links gl JOIN onboarding_data o ON o.user_id=gl.mother_id
          JOIN users u ON u.id=gl.guardian_id WHERE gl.mother_id=$1 AND gl.status='active' AND gl.guardian_id IS NOT NULL
          AND o.consent_tier2 AND u.is_active AND u.role='guardian' FOR SHARE OF gl,o,u`, [motherId]);
        if (link.rows[0]) {
          const alert = await client.query(`INSERT INTO guardian_alerts(mother_id,guardian_id,crisis_event_id,alert_type,message) VALUES($1,$2,$3,'crisis',
            'A serious safety indicator needs attention. Please check on her promptly and use the crisis plan. No private conversation is shared.') RETURNING id`,
          [motherId, link.rows[0].guardian_id, event.rows[0].id]);
          reply.safety.guardian_alert_allowed = alert.rows.length > 0;
          alertCreated = alert.rows.length > 0;
        }
      }
    }
    const existingAssistant = await client.query("SELECT id FROM chatbot_turns WHERE request_id=$1 AND role='assistant'", [reserved.request.id]);
    const assistantId = existingAssistant.rows[0]?.id || randomUUID();
    await client.query(`INSERT INTO chatbot_turns(id,session_id,request_id,role,language,content_encrypted,metadata_encrypted)
      VALUES($1,$2,$3,'assistant',$4,$5,$6) ON CONFLICT(request_id,role) DO UPDATE SET
      content_encrypted=EXCLUDED.content_encrypted,metadata_encrypted=EXCLUDED.metadata_encrypted,language=EXCLUDED.language`,
    [assistantId, sessionId, reserved.request.id, data.language, crypto.encrypt(reply.reply, scope(motherId, sessionId, `turn:${assistantId}`)),
      crypto.encrypt(JSON.stringify(reply), scope(motherId, sessionId, `metadata:${assistantId}`))]);
    const completed = await client.query(`UPDATE chatbot_requests SET status=$2,reply_encrypted=$3,completed_at=NOW() WHERE id=$1 RETURNING *`,
    [reserved.request.id, reply.mode === 'unavailable' ? 'failed' : 'complete', crypto.encrypt(JSON.stringify(reply), scope(motherId, sessionId, `reply:${reserved.request.id}`))]);
    await client.query('UPDATE chatbot_sessions SET language=$2,state_encrypted=$3,state_personalized=$4,last_message_at=NOW(),updated_at=NOW() WHERE id=$1',
      [sessionId, data.language, crypto.encrypt(JSON.stringify(reply.state), scope(motherId, sessionId, 'state')), reply.personalization_used]);
    return exchange(client, motherId, completed.rows[0]);
  });
  if (alertCreated) await push.processPendingSafely();
  return output;
}
module.exports = { status, setConsent, createSession, listSessions, listMessages, deleteSession, sendMessage,
  _private: { authorize, scope, publicConsent, publicTurn, publicSession, history } };
