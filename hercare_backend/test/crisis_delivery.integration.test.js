const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

test('M10 delivery checks safe recipients, ownership, withdrawal, expiry and closure (rollback, fake messaging)', {
  skip: process.env.RUN_CRISIS_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const originalQuery = db.query;
  const originalTransaction = db.withTransaction;
  let beforeDeliveryRead = null;
  try {
    await client.query('BEGIN');
    await client.query(await fs.readFile(path.join(__dirname, '../migrations/018_crisis_support.sql'), 'utf8'));
    db.query = async (...args) => {
      if (beforeDeliveryRead && args[0].includes('pd.token_encrypted') && args[0].includes('JOIN guardian_alerts ga')) await beforeDeliveryRead();
      return client.query(...args);
    };
    db.withTransaction = (fn) => fn(client);
    const crisis = require('../src/modules/crisis/crisis.service');
    const push = require('../src/modules/notifications/notification.service');
    const guardianService = require('../src/modules/guardian/guardian.service');
    const tokenCrypto = require('../src/modules/notifications/push_crypto');
    const mother = randomUUID();
    const guardian = randomUUID();
    const link = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [guardian, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
        VALUES($1,$2,'synthetic-test-hash',$3,TRUE)`, [id, `t${id.replaceAll('-', '').slice(0, 12)}`, role]);
    }
    await client.query(`INSERT INTO onboarding_data(user_id,age,months_since_birth,consent_tier1,consent_tier2)
      VALUES($1,28,3,TRUE,TRUE)`, [mother]);
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Synthetic support person','husband','active',NOW())`, [link, mother, guardian]);
    const token = 'fake-m10-token-never-a-real-device';
    await client.query(`INSERT INTO push_devices(user_id,token_hash,token_encrypted,platform)
      VALUES($1,$2,$3,'android')`, [guardian, tokenCrypto.hashToken(token), tokenCrypto.encryptToken(token)]);
    await crisis.savePlan(mother, { version: 0, coping_step: 'PRIVATE_PLAN_NOT_FOR_PUSH', support_phone: '+923001234567' });
    await crisis.setGuardianSafety(mother, { guardian_link_id: link, confirmed: true });
    const create = async () => {
      const event = await crisis.requestSupport(mother, { client_request_id: randomUUID(), notify_guardian: true, guardian_link_id: link });
      const outbox = (await client.query(`SELECT no.* FROM notification_outbox no JOIN guardian_alerts ga ON ga.id=no.alert_id
        WHERE ga.crisis_event_id=$1`, [event.id])).rows[0];
      assert.ok(outbox);
      return { event, outbox };
    };
    let sends = 0;
    const messaging = { sendEachForMulticast: async (payload) => {
      sends += 1;
      assert.deepEqual(payload.tokens, [token]);
      assert.equal(payload.android.ttl, 3600000);
      assert.equal(payload.android.priority, 'high');
      assert.equal(payload.data.recipient_id, guardian);
      assert.equal(payload.data.type, 'guardian_alert');
      assert.equal(payload.data.urgent, 'true');
      assert.equal(payload.android.notification.channelId, 'hercare_urgent_v1');
      assert.equal(payload.android.notification.sound, 'hercare_urgent');
      assert.equal(JSON.stringify(payload).includes('PRIVATE_PLAN_NOT_FOR_PUSH'), false);
      assert.equal(JSON.stringify(payload).includes('923001234567'), false);
      assert.equal(payload.data.mother_id, undefined);
      return { successCount: 1, responses: [{ success: true }] };
    } };
    const sent = await create();
    await push._private.deliver(sent.outbox, messaging);
    await push._private.deliver(sent.outbox, messaging);
    assert.equal(sends, 1, 'A sent row is not delivered twice');
    assert.equal((await client.query('SELECT status FROM notification_outbox WHERE id=$1', [sent.outbox.id])).rows[0].status, 'sent');
    const withdrawalRace = await create();
    let deliveryReads = 0;
    beforeDeliveryRead = async () => {
      deliveryReads++;
      if (deliveryReads === 2) await crisis.setGuardianSafety(mother, { guardian_link_id: link, confirmed: false });
    };
    await push._private.deliver(withdrawalRace.outbox, messaging);
    beforeDeliveryRead = null;
    assert.equal(deliveryReads, 2, 'Eligibility is rechecked immediately before messaging');
    assert.equal(sends, 1, 'Withdrawal between delivery reads prevents the send');
    assert.equal((await client.query('SELECT status FROM notification_outbox WHERE id=$1', [withdrawalRace.outbox.id])).rows[0].status, 'cancelled');
    await crisis.setGuardianSafety(mother, { guardian_link_id: link, confirmed: true });
    const closed = await create();
    await crisis.updateEvent(mother, closed.event.id, { status: 'resolved', outcome: 'support_contacted' });
    assert.deepEqual(await push._private.loadDelivery(closed.outbox), []);
    const expired = await create();
    await client.query("UPDATE crisis_events SET triggered_at=NOW()-INTERVAL '25 hours' WHERE id=$1", [expired.event.id]);
    assert.deepEqual(await push._private.loadDelivery(expired.outbox), []);
    const withdrawn = await create();
    assert.ok((await guardianService.getAlerts(guardian)).some((alert) => alert.id === withdrawn.outbox.alert_id));
    await crisis.setGuardianSafety(mother, { guardian_link_id: link, confirmed: false });
    assert.deepEqual(await push._private.loadDelivery(withdrawn.outbox), []);
    assert.equal((await guardianService.getAlerts(guardian)).length, 0, 'Withdrawal also hides urgent in-app alerts');
    assert.equal((await guardianService.markAlertsRead(guardian, [withdrawn.outbox.alert_id])).updated, 0);
    await crisis.setGuardianSafety(mother, { guardian_link_id: link, confirmed: true });
    const noConsent = await create();
    await client.query('UPDATE onboarding_data SET consent_tier2=FALSE WHERE user_id=$1', [mother]);
    assert.deepEqual(await push._private.loadDelivery(noConsent.outbox), []);
    await client.query('UPDATE onboarding_data SET consent_tier2=TRUE WHERE user_id=$1', [mother]);
    const relinked = await create();
    await client.query("UPDATE guardian_links SET status='revoked' WHERE id=$1", [link]);
    const newLink = randomUUID();
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Same person, new link','husband','active',NOW())`, [newLink, mother, guardian]);
    assert.deepEqual(await push._private.loadDelivery(relinked.outbox), [], 'Confirmation does not carry to a replacement link');
    await crisis.setGuardianSafety(mother, { guardian_link_id: newLink, confirmed: true });
    assert.deepEqual(await push._private.loadDelivery(relinked.outbox), [], 'Renewed confirmation cannot revive an alert bound to the old link');
    assert.equal((await guardianService.getAlerts(guardian)).length, 0);
    assert.equal(sends, 1);
  } finally {
    await client.query('ROLLBACK');
    db.query = originalQuery;
    db.withTransaction = originalTransaction;
    client.release();
    await db.pool.end();
  }
});
