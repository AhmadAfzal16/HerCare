const test = require('node:test');
const assert = require('node:assert/strict');
const { randomBytes, randomUUID } = require('node:crypto');

// Exercise actual delivery message construction with only synthetic rows and a
// fake messaging object. No database connection, Firebase app or worker starts.
async function withDeliveryFixture(run) {
  const previousEnv = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString('hex');
  const db = require('../src/config/database');
  const servicePath = require.resolve('../src/modules/notifications/notification.service');
  const previousService = require.cache[servicePath];
  const previousQuery = db.query;
  const { encryptToken } = require('../src/modules/notifications/push_crypto');
  let rows = [];
  const operations = [];
  db.query = async (sql, values) => {
    operations.push({ sql, values });
    if (/^\s*SELECT/.test(sql)) return { rows: structuredClone(rows), rowCount: rows.length };
    assert.match(sql, /^\s*UPDATE (?:push_devices|notification_outbox)/);
    return { rows: [], rowCount: 1 };
  };
  delete require.cache[servicePath];
  try {
    const service = require(servicePath);
    assert.equal(service.status().enabled, false);
    const capture = async (type, screening = false) => {
      const outbox = { id: randomUUID(), recipient_id: randomUUID(), attempts: 1,
        screening_reminder_id: screening ? randomUUID() : null };
      const token = `synthetic-registration-token-${randomUUID()}`;
      rows = [{ id: outbox.id, attempts: 1, alert_id: randomUUID(), alert_type: type,
        device_id: randomUUID(), token_encrypted: encryptToken(token) }];
      operations.length = 0;
      const messages = [];
      const messaging = { sendEachForMulticast: async (message) => {
        messages.push(message);
        return { successCount: 1, failureCount: 0, responses: [{ success: true }] };
      } };
      await service._private.deliver(outbox, messaging);
      assert.equal(messages.length, 1);
      assert.equal(operations.filter((item) => /^\s*SELECT/.test(item.sql)).length, 2,
        'Delivery eligibility is checked again immediately before fake delivery');
      assert.ok(operations.some((item) => /UPDATE notification_outbox/.test(item.sql) && item.values[1] === 'sent'));
      const message = messages[0];
      assert.deepEqual(message.tokens, [token]);
      assert.equal(message.data.recipient_id, outbox.recipient_id);
      assert.equal(message.android.notification.visibility, 'private');
      assert.equal(message.apns.payload.aps.sound, 'default');
      assert.equal(Object.hasOwn(message.apns.payload.aps, 'critical'), false);
      assert.equal(JSON.stringify(message).includes('token_encrypted'), false);
      return message;
    };
    await run(capture);
  } finally {
    db.query = previousQuery;
    delete require.cache[servicePath];
    if (previousService) require.cache[servicePath] = previousService;
    for (const key of Object.keys(process.env)) if (!(key in previousEnv)) delete process.env[key];
    Object.assign(process.env, previousEnv);
  }
}

test('crisis and severe-risk pushes alone use the urgent flag, Android sound channel and high priority', async () => {
  await withDeliveryFixture(async (capture) => {
    for (const type of ['crisis', 'risk_severe']) {
      const message = await capture(type);
      assert.equal(message.data.urgent, 'true');
      assert.equal(message.data.type, 'guardian_alert');
      assert.equal(message.data.route, '/notifications');
      assert.equal(message.android.priority, 'high');
      assert.equal(message.android.notification.channelId, 'hercare_urgent_v1');
      assert.equal(message.android.notification.sound, 'hercare_urgent');
      assert.equal(message.apns.headers['apns-priority'], '10');
      assert.equal(message.notification.title, 'Urgent HerCare support alert');
      assert.deepEqual(Object.keys(message.data).sort(), ['alert_id', 'recipient_id', 'route', 'type', 'urgent']);
    }
  });
});

test('ordinary guardian updates and screening reminders do not select urgent flags or the alarm sound channel', async () => {
  await withDeliveryFixture(async (capture) => {
    for (const type of ['mood_decline', 'risk_moderate', 'weekly_summary']) {
      const message = await capture(type);
      assert.equal(message.data.urgent, 'false');
      assert.equal(message.android.priority, 'normal');
      assert.equal(message.android.notification.channelId, 'hercare_urgent_alerts');
      assert.equal(Object.hasOwn(message.android.notification, 'sound'), false);
      assert.equal(message.apns.headers['apns-priority'], '5');
      assert.equal(message.notification.title, 'HerCare wellbeing update');
    }
    const reminder = await capture('screening_reminder', true);
    assert.equal(Object.hasOwn(reminder.data, 'urgent'), false);
    assert.equal(reminder.data.type, 'screening_reminder');
    assert.equal(reminder.data.route, '/tests');
    assert.equal(reminder.android.priority, 'normal');
    assert.equal(reminder.android.notification.channelId, 'hercare_screening_reminders');
    assert.equal(reminder.android.notification.tag, 'screening_reminder');
    assert.equal(Object.hasOwn(reminder.android.notification, 'sound'), false);
    assert.equal(reminder.apns.headers['apns-priority'], '5');
    assert.equal(reminder.notification.title, 'HerCare check-in reminder');
  });
});
