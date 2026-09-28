const { applicationDefault, cert, getApps, initializeApp } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');
const { query, withTransaction } = require('../../config/database');
const logger = require('../../utils/logger');
const { encryptToken, decryptToken, hashToken } = require('./push_crypto');

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
  const { rows } = await query(
    `SELECT no.id, no.attempts, ga.id AS alert_id, ga.alert_type,
            pd.id AS device_id, pd.token_encrypted
     FROM notification_outbox no
     JOIN guardian_alerts ga ON ga.id = no.alert_id
     JOIN guardian_links gl ON gl.mother_id = ga.mother_id
       AND gl.guardian_id = ga.guardian_id AND gl.status = 'active'
     JOIN onboarding_data od ON od.user_id = ga.mother_id AND od.consent_tier2 = TRUE
     LEFT JOIN push_devices pd ON pd.user_id = no.recipient_id AND pd.enabled = TRUE
     WHERE no.id = $1`,
    [outbox.id],
  );
  return rows;
}

async function finish(id, status, error = null, delayMinutes = 0) {
  await query(
    `UPDATE notification_outbox SET status = $2, last_error = $3,
       sent_at = CASE WHEN $2 = 'sent' THEN NOW() ELSE sent_at END,
       next_attempt_at = NOW() + ($4 * INTERVAL '1 minute'), updated_at = NOW()
     WHERE id = $1`,
    [id, status, error?.slice(0, 300) || null, delayMinutes],
  );
}

async function deliver(outbox, messaging) {
  const rows = await loadDelivery(outbox);
  if (!rows.length) return finish(outbox.id, 'cancelled', 'Link inactive or consent unavailable.');
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

  const payload = publicPayload(rows[0].alert_type);
  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data: { route: '/notifications', alert_id: String(rows[0].alert_id), type: 'guardian_alert' },
    android: {
      priority: payload.priority,
      notification: { channelId: 'hercare_urgent_alerts', visibility: 'private' },
    },
    apns: {
      headers: { 'apns-priority': payload.priority === 'high' ? '10' : '5' },
      payload: { aps: { sound: 'default', 'thread-id': 'guardian-alerts' } },
    },
  });

  for (let index = 0; index < response.responses.length; index += 1) {
    const item = response.responses[index];
    if (item.success) {
      await query(
        'UPDATE push_devices SET failure_count = 0, last_error_code = NULL, updated_at = NOW() WHERE id = $1',
        [deviceIds[index]],
      );
    } else {
      const code = item.error?.code || 'unknown';
      await query(
        `UPDATE push_devices SET failure_count = failure_count + 1,
           last_error_code = $2, enabled = CASE WHEN $3 THEN FALSE ELSE enabled END,
           updated_at = NOW() WHERE id = $1`,
        [deviceIds[index], code, INVALID_TOKEN_CODES.has(code)],
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
};
