const { randomUUID } = require('node:crypto');
const db = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const crypto = require('./crisis.crypto');
const policy = require('./crisis.policy');

const EMPTY_PLAN = { coping_step: '', support_person_name: '', support_phone: '' };
async function authorize(client, motherId) {
  const result = await client.query(`SELECT u.id FROM users u JOIN onboarding_data od ON od.user_id=u.id
    WHERE u.id=$1 AND u.role='mother' AND u.is_active AND od.consent_tier1 FOR SHARE OF u,od`, [motherId]);
  if (!result.rows[0]) throw new AppError('An active mother account and basic consent are required.', 403);
}
async function lockPlan(client, motherId) {
  await client.query('INSERT INTO crisis_safety_plans(mother_id) VALUES($1) ON CONFLICT(mother_id) DO NOTHING', [motherId]);
  const result = await client.query('SELECT * FROM crisis_safety_plans WHERE mother_id=$1 FOR UPDATE', [motherId]);
  return result.rows[0];
}
function publicPlan(row, motherId) {
  let fields = EMPTY_PLAN;
  if (row?.content_encrypted) {
    try {
      const loaded = policy.plan({ ...crypto.decrypt(row.content_encrypted, motherId), version: row.version });
      fields = { coping_step: loaded.coping_step, support_person_name: loaded.support_person_name, support_phone: loaded.support_phone };
    } catch { throw new AppError('Your private safety plan could not be opened. Basic emergency help remains available.', 503); }
  }
  return { ...fields, version: row?.version || 0, updated_at: row?.updated_at || null };
}
async function currentGuardian(client, motherId, plan, lock = false) {
  const result = await client.query(`SELECT gl.id AS link_id,gl.guardian_id,gl.guardian_name AS name,guardian.phone
    FROM guardian_links gl JOIN users guardian ON guardian.id=gl.guardian_id AND guardian.role='guardian' AND guardian.is_active
    JOIN onboarding_data od ON od.user_id=gl.mother_id AND od.consent_tier2
    WHERE gl.mother_id=$1 AND gl.status='active' ORDER BY gl.accepted_at DESC,gl.id DESC LIMIT 1
    ${lock ? 'FOR SHARE OF gl,guardian' : ''}`, [motherId]);
  const row = result.rows[0];
  if (!row) return null;
  return { link_id: row.link_id, name: row.name || 'Guardian', phone: row.phone,
    safe_to_contact_confirmed: plan?.guardian_contact_confirmed === true && plan.safe_guardian_link_id === row.link_id,
    guardian_id: row.guardian_id };
}
function publicGuardian(row) {
  if (!row) return null;
  return { link_id: row.link_id, name: row.name, phone: row.phone, safe_to_contact_confirmed: row.safe_to_contact_confirmed };
}
function publicEvent(row) {
  return { id: row.id, source_type: row.source_type, severity: row.severity, status: row.status,
    triggered_at: row.triggered_at, acknowledged_at: row.acknowledged_at || null, resolved_at: row.resolved_at || null,
    outcome: row.resolution_outcome || null,
    guardian_notification: row.guardian_notification || (row.guardian_alert_id ? 'queued' : 'not_requested'),
    notification_delivery: row.notification_delivery || null,
    closure_is_clinical_recovery: false };
}
// pg's default JS Date parser loses microseconds. Retain exact PostgreSQL time
// for keyset pagination so tied and sub-millisecond events cannot be skipped.
const EVENT_SELECT = `SELECT ce.*,to_char(ce.triggered_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS cursor_at,
  request.guardian_notification,alert.id AS guardian_alert_id,outbox.status AS notification_delivery FROM crisis_events ce
  LEFT JOIN crisis_support_requests request ON request.event_id=ce.id
  LEFT JOIN guardian_alerts alert ON alert.crisis_event_id=ce.id
  LEFT JOIN notification_outbox outbox ON outbox.alert_id=alert.id`;
async function support(motherId) {
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const result = await client.query('SELECT * FROM crisis_safety_plans WHERE mother_id=$1', [motherId]);
    const plan = result.rows[0];
    const guardian = await currentGuardian(client, motherId, plan);
    const events = await client.query(`${EVENT_SELECT} WHERE ce.mother_id=$1 AND ce.status<>'resolved'
      ORDER BY ce.triggered_at DESC,ce.id DESC LIMIT 1`, [motherId]);
    return { plan: publicPlan(plan, motherId), guardian: publicGuardian(guardian), open_event: events.rows[0] ? publicEvent(events.rows[0]) : null,
      notification_policy: 'Urgent guardian alerts require sharing consent and a separate confirmation that the current guardian is safe to contact. A queued alert is not guaranteed delivery.' };
  });
}
async function savePlan(motherId, body) {
  const data = policy.plan(body);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const existing = await lockPlan(client, motherId);
    if (existing.version !== data.version) throw new AppError('Your safety plan changed on another device. Refresh before saving.', 409);
    const fields = { coping_step: data.coping_step, support_person_name: data.support_person_name, support_phone: data.support_phone };
    const encrypted = Object.values(fields).some(Boolean) ? crypto.encrypt(fields, motherId) : null;
    const result = await client.query(`UPDATE crisis_safety_plans SET content_encrypted=$2,version=version+1,updated_at=NOW()
      WHERE mother_id=$1 RETURNING *`, [motherId, encrypted]);
    return publicPlan(result.rows[0], motherId);
  });
}
async function deletePlan(motherId, expectedVersion) {
  policy.version(expectedVersion);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const plan = await lockPlan(client, motherId);
    if (plan.version !== expectedVersion) throw new AppError('Your safety plan changed on another device. Refresh before deleting.', 409);
    const result = await client.query(`UPDATE crisis_safety_plans SET content_encrypted=NULL,version=version+1,updated_at=NOW()
      WHERE mother_id=$1 RETURNING *`, [motherId]);
    return publicPlan(result.rows[0], motherId);
  });
}
async function setGuardianSafety(motherId, body) {
  const data = policy.guardian(body);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const plan = await lockPlan(client, motherId);
    const guardian = await currentGuardian(client, motherId, plan, true);
    if (data.confirmed && guardian?.link_id !== data.guardian_link_id) throw new AppError('Your guardian link or sharing consent changed. Refresh before confirming.', 409);
    if (!data.confirmed && data.guardian_link_id !== plan.safe_guardian_link_id && data.guardian_link_id !== guardian?.link_id) {
      throw new AppError('Guardian confirmation not found.', 404);
    }
    await client.query(`UPDATE crisis_safety_plans SET safe_guardian_link_id=$2,guardian_contact_confirmed=$3,
      guardian_confirmed_at=CASE WHEN $3 THEN NOW() ELSE NULL END,updated_at=NOW() WHERE mother_id=$1`,
    [motherId, data.confirmed ? data.guardian_link_id : null, data.confirmed]);
    // Withdraw pending M10/other urgent deliveries immediately. The worker also
    // rechecks current link/consent/safe-recipient state immediately before send.
    if (!data.confirmed) await client.query(`UPDATE notification_outbox no SET status='cancelled',updated_at=NOW(),last_error='Urgent recipient confirmation withdrawn.'
      FROM guardian_alerts ga WHERE no.alert_id=ga.id AND ga.mother_id=$1 AND ga.alert_type IN ('crisis','risk_severe')
      AND no.status IN ('pending','retry','no_device','sending')`, [motherId]);
    return { guardian: guardian ? publicGuardian({ ...guardian, safe_to_contact_confirmed: data.confirmed }) : null, plan_version: plan.version };
  });
}
async function requestSupport(motherId, body) {
  const data = policy.request(body);
  const fingerprint = crypto.fingerprint({ notify_guardian: data.notify_guardian, guardian_link_id: data.guardian_link_id });
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    // Serializes a mother's duplicate requests without holding unrelated accounts.
    const plan = await lockPlan(client, motherId);
    const previous = await client.query(`${EVENT_SELECT} WHERE request.mother_id=$1 AND request.client_request_id=$2`, [motherId, data.client_request_id]);
    if (previous.rows[0]) {
      const hash = await client.query('SELECT request_fingerprint FROM crisis_support_requests WHERE mother_id=$1 AND client_request_id=$2', [motherId, data.client_request_id]);
      if (hash.rows[0].request_fingerprint !== fingerprint) throw new AppError('This request identifier was already used for a different action.', 409);
      return publicEvent(previous.rows[0]);
    }
    const event = await client.query(`INSERT INTO crisis_events(mother_id,source_type,source_id,severity)
      VALUES($1,'manual',$2,'high') RETURNING *`, [motherId, randomUUID()]);
    let notification = 'not_requested';
    if (data.notify_guardian) {
      notification = 'unavailable';
      const guardian = await currentGuardian(client, motherId, plan, true);
      if (guardian?.link_id === data.guardian_link_id && guardian.safe_to_contact_confirmed) {
        const alert = await client.query(`INSERT INTO guardian_alerts(mother_id,guardian_id,alert_type,message,crisis_event_id)
          VALUES($1,$2,'crisis','She has requested urgent support in HerCare. Please contact her and help her reach appropriate support. Do not assume that an alert means help has arrived.',$3)
          ON CONFLICT DO NOTHING RETURNING id`, [motherId, guardian.guardian_id, event.rows[0].id]);
        if (alert.rows[0]) notification = 'queued';
      }
    }
    await client.query(`INSERT INTO crisis_support_requests(mother_id,client_request_id,event_id,request_fingerprint,guardian_notification)
      VALUES($1,$2,$3,$4,$5)`, [motherId, data.client_request_id, event.rows[0].id, fingerprint, notification]);
    // The existing transactional outbox owns delivery; no network call inside a
    // transaction, no raw plan/contact data in an alert, no automatic retry-send.
    return publicEvent({ ...event.rows[0], guardian_notification: notification,
      notification_delivery: notification === 'queued' ? 'pending' : null });
  });
}
async function updateEvent(motherId, eventId, body) {
  policy.id(eventId);
  const data = policy.transition(body);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const current = await client.query('SELECT * FROM crisis_events WHERE id=$1 AND mother_id=$2 FOR UPDATE', [eventId, motherId]);
    const row = current.rows[0];
    if (!row) throw new AppError('Support request not found.', 404);
    if (row.status === 'resolved') {
      if (data.status !== 'resolved' || row.resolution_outcome !== data.outcome) throw new AppError('This support request has already been closed.', 409);
    } else {
      await client.query(`UPDATE crisis_events SET status=$3::varchar,acknowledged_at=COALESCE(acknowledged_at,NOW()),
        resolved_at=CASE WHEN $3::varchar='resolved' THEN NOW() ELSE NULL END,resolution_outcome=$4 WHERE id=$1 AND mother_id=$2`,
      [eventId, motherId, data.status, data.outcome]);
      if (data.status === 'resolved') await client.query(`UPDATE notification_outbox no SET status='cancelled',updated_at=NOW(),last_error='Support request closed by mother.'
        FROM guardian_alerts ga WHERE no.alert_id=ga.id AND ga.crisis_event_id=$1 AND no.status IN ('pending','retry','no_device','sending')`, [eventId]);
    }
    const result = await client.query(`${EVENT_SELECT} WHERE ce.id=$1 AND ce.mother_id=$2`, [eventId, motherId]);
    return publicEvent(result.rows[0]);
  });
}
async function history(motherId, query) {
  const page = policy.page(query);
  return db.withTransaction(async (client) => {
    await authorize(client, motherId);
    const result = await client.query(`${EVENT_SELECT} WHERE ce.mother_id=$1
      AND ($2::timestamptz IS NULL OR (ce.triggered_at,ce.id)<($2::timestamptz,$3::uuid))
      ORDER BY ce.triggered_at DESC,ce.id DESC LIMIT $4`, [motherId, page.before?.at || null, page.before?.id || null, page.limit + 1]);
    const selected = result.rows.slice(0, page.limit);
    return { events: selected.map(publicEvent), has_more: result.rows.length > page.limit,
      next_cursor: result.rows.length > page.limit ? policy.cursor(selected.at(-1)) : null };
  });
}
module.exports = { support, savePlan, deletePlan, setGuardianSafety, requestSupport, updateEvent, history };
