const { applicationDefault, cert, getApps, initializeApp } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const { query, withTransaction } = require('../../config/database');
const logger = require('../../utils/logger');
const { encryptToken, decryptToken, hashToken } = require('./push_crypto');
const { queueDueReminders } = require('../screening/screening.schedule');

const INVALID_TOKEN_CODES = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  'messaging/mismatched-credential',
]);
let workerTimer;
let processing = false;

function firebaseEnabled() {
  return process.env.FIREBASE_PUSH_ENABLED === 'true';
}

function firebaseApp() {
  if (!firebaseEnabled()) return null;
  if (getApps().length) return getApps()[0];
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (raw) {
    const decoded = raw.trim().startsWith('{')
      ? raw
      : Buffer.from(raw, 'base64').toString('utf8');
    return initializeApp({ credential: cert(JSON.parse(decoded)) });
  }
  return initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
  });
}

async function registerDevice(userId, { token, platform }) {
  const tokenHash = hashToken(token);
  const encrypted = encryptToken(token);
  const { rows } = await query(
    `INSERT INTO push_devices
       (user_id, token_hash, token_encrypted, platform, enabled, failure_count,
        last_error_code, last_seen_at)
     VALUES ($1, $2, $3, $4, TRUE, 0, NULL, NOW())
     ON CONFLICT (token_hash) DO UPDATE SET
       user_id = EXCLUDED.user_id, token_encrypted = EXCLUDED.token_encrypted,
       platform = EXCLUDED.platform, enabled = TRUE, failure_count = 0,
       last_error_code = NULL, last_seen_at = NOW(), updated_at = NOW()
     RETURNING id, platform, enabled, last_seen_at`,
    [userId, tokenHash, encrypted, platform],
  );
  await query(
    `UPDATE notification_outbox SET status = 'pending', next_attempt_at = NOW(), updated_at = NOW()
     WHERE recipient_id = $1 AND status = 'no_device'
       AND created_at >= NOW() - INTERVAL '24 hours'`,
    [userId],
  );
  void processPending().catch((error) => logger.error(`Push processing failed: ${error.message}`));
  return rows[0];
}

async function unregisterDevice(userId, token) {
  const result = await query(
    `UPDATE push_devices SET enabled = FALSE, updated_at = NOW()
     WHERE user_id = $1 AND token_hash = $2`,
    [userId, hashToken(token)],
  );
  return { removed: result.rowCount > 0 };
}

function publicPayload(alertType) {
  if (alertType === 'screening_reminder') {
    return {
      title: 'HerCare check-in reminder',
      body: 'A scheduled check-in is ready. Open Tests when convenient.',
      priority: 'normal',
    };
  }
  if (alertType === 'crisis' || alertType === 'risk_severe') {
    return {
      title: 'Urgent HerCare support alert',
      body: 'Please open HerCare and check the support alert now.',
      priority: 'high',
    };
  }
  return {
    title: 'HerCare wellbeing update',
    body: 'A new support update is available. Open HerCare to review it.',
    priority: 'normal',
  };
}

async function claimBatch(limit) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `WITH ready AS (
         SELECT no.id FROM notification_outbox no
         WHERE (
           no.status IN ('pending', 'retry', 'no_device') AND no.next_attempt_at <= NOW()
         ) OR (no.status = 'sending' AND no.updated_at < NOW() - INTERVAL '2 minutes')
         ORDER BY no.created_at ASC
         FOR UPDATE SKIP LOCKED LIMIT $1
       )
       UPDATE notification_outbox no SET status = 'sending', attempts = attempts + 1,
         updated_at = NOW()
       FROM ready WHERE no.id = ready.id
       RETURNING no.*`,
      [limit],
    );
    return rows;
  });
}

async function loadDelivery(outbox) {
  if (outbox.screening_reminder_id) {
    const { rows } = await query(
      `SELECT no.id, no.attempts, 'screening_reminder' AS alert_type,
         pd.id AS device_id, pd.token_encrypted
       FROM notification_outbox no
       JOIN screening_reminders sr ON sr.id = no.screening_reminder_id
         AND sr.mother_id = no.recipient_id AND sr.status = 'scheduled' AND sr.due_at <= NOW()
       JOIN users u ON u.id = sr.mother_id AND u.role = 'mother'
         AND u.is_active = TRUE AND u.onboarding_complete = TRUE
       JOIN onboarding_data od ON od.user_id = u.id AND od.consent_tier1 = TRUE
       LEFT JOIN push_devices pd ON pd.user_id = no.recipient_id AND pd.enabled = TRUE
       WHERE no.id = $1 AND no.status IN ('pending','retry','no_device','sending')
         AND no.created_at >= NOW() - INTERVAL '48 hours'`, [outbox.id],
    );
    return rows;
  }
  const { rows } = await query(
    `SELECT no.id, no.attempts, ga.id AS alert_id, ga.alert_type,
            pd.id AS device_id, pd.token_encrypted
     FROM notification_outbox no
     JOIN guardian_alerts ga ON ga.id = no.alert_id
     JOIN guardian_links gl ON gl.mother_id = ga.mother_id
       AND gl.guardian_id = ga.guardian_id AND gl.status = 'active'
     JOIN onboarding_data od ON od.user_id = ga.mother_id AND od.consent_tier2 = TRUE
       AND od.consent_tier1 = TRUE
     JOIN users mother ON mother.id=ga.mother_id AND mother.is_active AND mother.role='mother'
     JOIN users guardian ON guardian.id=ga.guardian_id AND guardian.is_active AND guardian.role='guardian'
     LEFT JOIN crisis_safety_plans plan ON plan.mother_id=ga.mother_id
     LEFT JOIN crisis_events ce ON ce.id=ga.crisis_event_id AND ce.mother_id=ga.mother_id
     LEFT JOIN push_devices pd ON pd.user_id = no.recipient_id AND pd.enabled = TRUE
     WHERE no.id = $1 AND no.recipient_id=ga.guardian_id
       AND no.status IN ('pending','retry','no_device','sending')
       AND (ga.alert_type NOT IN ('crisis','risk_severe') OR (
         plan.safe_guardian_link_id=gl.id AND plan.guardian_contact_confirmed
         AND ga.crisis_guardian_link_id=gl.id
         AND ce.id IS NOT NULL AND ce.status<>'resolved'
         AND ce.triggered_at >= NOW()-INTERVAL '24 hours'
         AND no.created_at >= NOW()-INTERVAL '24 hours'))
       AND (ga.crisis_event_id IS NULL OR ce.status<>'resolved')`,
    [outbox.id],
  );
  return rows;
}

async function finish(id, status, error = null, delayMinutes = 0) {
  await query(
    `UPDATE notification_outbox SET status = $2::varchar, last_error = $3,
       sent_at = CASE WHEN $2::varchar = 'sent' THEN NOW() ELSE sent_at END,
       next_attempt_at = NOW() + ($4 * INTERVAL '1 minute'), updated_at = NOW()
     WHERE id = $1 AND status IN ('pending','retry','no_device','sending')`,
    [id, status, error?.slice(0, 300) || null, delayMinutes],
  );
}

async function deliver(outbox, messaging) {
  const rows = await loadDelivery(outbox);
  if (!rows.length) return finish(outbox.id, 'cancelled', 'Delivery no longer eligible.');
  const devices = rows.filter((row) => row.device_id);
  if (!devices.length) return finish(outbox.id, 'no_device', 'No active device.', 60);

  const tokens = [];
  const deviceIds = [];
  for (const device of devices) {
    try {
      tokens.push(decryptToken(device.token_encrypted));
      deviceIds.push(device.device_id);
    } catch {
      await query(
        `UPDATE push_devices SET enabled = FALSE, last_error_code = 'decrypt_failed', updated_at = NOW()
         WHERE id = $1`, [device.device_id],
      );
    }
  }
  if (!tokens.length) return finish(outbox.id, 'no_device', 'No valid active device.', 60);

  // Recheck after decryption/device cleanup, immediately before network delivery.
  // This cannot recall an already delivered push or guarantee emergency help.
  const current = await loadDelivery(outbox);
  const allowedDeviceIds = new Set(current.map((row) => row.device_id).filter(Boolean));
  const eligibleTokens = tokens.filter((_, index) => allowedDeviceIds.has(deviceIds[index]));
  const eligibleIds = deviceIds.filter((id) => allowedDeviceIds.has(id));
  if (!current.length) return finish(outbox.id, 'cancelled', 'Delivery no longer eligible.');
  if (!eligibleTokens.length) return finish(outbox.id, 'no_device', 'No active eligible device.', 60);

  const payload = publicPayload(rows[0].alert_type);
  const screening = Boolean(outbox.screening_reminder_id);
  const urgent = !screening && ['crisis', 'risk_severe'].includes(rows[0].alert_type);
  const response = await messaging.sendEachForMulticast({
    tokens: eligibleTokens,
    notification: { title: payload.title, body: payload.body },
    data: screening
      ? { route: '/tests', type: 'screening_reminder', recipient_id: String(outbox.recipient_id) }
      : { route: '/notifications', alert_id: String(rows[0].alert_id), type: 'guardian_alert', recipient_id: String(outbox.recipient_id), urgent: String(urgent) },
    android: {
      priority: payload.priority,
      ...(screening ? { ttl: 6 * 60 * 60 * 1000, collapseKey: 'screening_reminder' }
        : { ttl: 60 * 60 * 1000, collapseKey: 'guardian_support' }),
      notification: {
        channelId: screening ? 'hercare_screening_reminders'
          : urgent ? 'hercare_urgent_v1' : 'hercare_urgent_alerts',
        visibility: 'private',
        ...(urgent ? { sound: 'hercare_urgent' } : {}),
        ...(screening ? { tag: 'screening_reminder' } : {}),
      },
    },
    apns: {
      headers: {
        'apns-priority': payload.priority === 'high' ? '10' : '5',
        ...(screening ? {
          'apns-collapse-id': 'screening_reminder',
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 6 * 60 * 60),
        } : { 'apns-expiration': String(Math.floor(Date.now() / 1000) + 60 * 60) }),
      },
      payload: { aps: { sound: 'default', 'thread-id': screening ? 'screening-reminders' : 'guardian-alerts' } },
    },
  });

  for (let index = 0; index < response.responses.length; index += 1) {
    const item = response.responses[index];
    if (item.success) {
      await query(
        'UPDATE push_devices SET failure_count = 0, last_error_code = NULL, updated_at = NOW() WHERE id = $1',
        [eligibleIds[index]],
      );
    } else {
      const code = item.error?.code || 'unknown';
      await query(
        `UPDATE push_devices SET failure_count = failure_count + 1,
           last_error_code = $2, enabled = CASE WHEN $3 THEN FALSE ELSE enabled END,
           updated_at = NOW() WHERE id = $1`,
        [eligibleIds[index], code, INVALID_TOKEN_CODES.has(code)],
      );
    }
  }
  if (response.successCount > 0) return finish(outbox.id, 'sent');
  const firstError = response.responses.find((item) => !item.success)?.error;
  throw firstError || new Error('Firebase rejected all device tokens.');
}

async function processPending(limit = 20) {
  if (processing || !firebaseEnabled()) return { processed: 0, enabled: firebaseEnabled() };
  processing = true;
  try {
    const app = firebaseApp();
    await queueDueReminders();
    const batch = await claimBatch(Math.min(Math.max(Number(limit) || 20, 1), 100));
    const messaging = getMessaging(app);
    for (const item of batch) {
      try {
        await deliver(item, messaging);
      } catch (error) {
        const terminal = item.attempts >= 5;
        const delay = Math.min(2 ** item.attempts, 60);
        await finish(item.id, terminal ? 'failed' : 'retry', error.message, delay);
        logger.error(`Push delivery ${item.id} failed: ${error.message}`);
      }
    }
    return { processed: batch.length, enabled: true };
  } finally {
    processing = false;
  }
}

async function processPendingSafely(limit = 20) {
  try {
    return await processPending(limit);
  } catch (error) {
    logger.error(`Push processing failed without blocking the primary request: ${error.message}`);
    return { processed: 0, enabled: firebaseEnabled(), error: true };
  }
}

function startWorker() {
  if (!firebaseEnabled() || workerTimer) return;
  void processPending().catch((error) => logger.error(`Push worker startup failed: ${error.message}`));
  workerTimer = setInterval(() => {
    void processPending().catch((error) => logger.error(`Push worker failed: ${error.message}`));
  }, 15_000);
  workerTimer.unref();
}

function stopWorker() {
  if (workerTimer) clearInterval(workerTimer);
  workerTimer = undefined;
}

function status() {
  return { enabled: firebaseEnabled(), provider: 'firebase_cloud_messaging' };
}

module.exports = {
  registerDevice,
  unregisterDevice,
  processPending,
  processPendingSafely,
  startWorker,
  stopWorker,
  status,
  _private: { publicPayload, loadDelivery, deliver },
};
