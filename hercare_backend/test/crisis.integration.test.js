const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

test('M10 encrypted plans, secure guardian support, event ownership and closure (PostgreSQL rollback only)', {
  skip: process.env.RUN_CRISIS_DB_TEST !== '1',
}, async () => {
  require('dotenv').config();
  const previousEnv = process.env.NODE_ENV;
  const previousPush = process.env.FIREBASE_PUSH_ENABLED;
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const originalQuery = db.query;
  const originalTransaction = db.withTransaction;
  try {
    await client.query('BEGIN');
    // New migration is exercised transactionally; no schema/data are committed.
    await client.query(await fs.readFile(path.join(__dirname, '../migrations/018_crisis_support.sql'), 'utf8'));
    db.query = (...args) => client.query(...args);
    db.withTransaction = (fn) => fn(client);
    const service = require('../src/modules/crisis/crisis.service');
    const mother = randomUUID();
    const other = randomUUID();
    const guardian = randomUUID();
    const otherGuardian = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [other, 'mother'], [guardian, 'guardian'], [otherGuardian, 'guardian']]) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [id, 't' + id.replaceAll('-', '').slice(0, 12), 'synthetic-test-hash', role]);
      if (role === 'mother') await client.query(`INSERT INTO onboarding_data(user_id,full_name,age,months_since_birth,consent_tier1,consent_tier2)
        VALUES($1,'Synthetic M10 account',28,3,TRUE,FALSE)`, [id]);
    }
    const initial = await service.support(mother);
    assert.equal(initial.plan.version, 0);
    assert.equal(initial.guardian, null);
    assert.equal(initial.open_event, null);
    await assert.rejects(() => service.support(guardian), { statusCode: 403 });
    const saved = await service.savePlan(mother, { version: 0, coping_step: 'PRIVATE_COPE', support_person_name: 'PRIVATE_FRIEND', support_phone: '+923001234567' });
    assert.equal(saved.version, 1);
    const encrypted = await client.query('SELECT content_encrypted FROM crisis_safety_plans WHERE mother_id=$1', [mother]);
    assert.equal(JSON.stringify(encrypted.rows).includes('PRIVATE_'), false);
    assert.equal(JSON.stringify(encrypted.rows).includes('923001234567'), false);
    assert.equal((await service.support(other)).plan.coping_step, '');
    await assert.rejects(() => service.savePlan(mother, { version: 0, coping_step: 'stale write' }), { statusCode: 409 });
    await assert.rejects(() => service.deletePlan(mother, 0), { statusCode: 409 });
    const link = randomUUID();
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Synthetic guardian','husband','active',NOW())`, [link, mother, guardian]);
    assert.equal((await service.support(mother)).guardian, null);
    await client.query('UPDATE onboarding_data SET consent_tier2=TRUE WHERE user_id=$1', [mother]);
    assert.equal((await service.support(mother)).guardian.safe_to_contact_confirmed, false);
    const refused = await service.requestSupport(mother, { client_request_id: randomUUID(), notify_guardian: true, guardian_link_id: link });
    assert.equal(refused.guardian_notification, 'unavailable');
    assert.equal((await client.query('SELECT id FROM guardian_alerts WHERE mother_id=$1', [mother])).rowCount, 0);
    // Legacy automatic crisis sources also cannot notify an unconfirmed spouse.
    const suppressed = await client.query(`INSERT INTO guardian_alerts(mother_id,guardian_id,alert_type,message)
      VALUES($1,$2,'crisis','Synthetic aggregate-only signal') RETURNING id`, [mother, guardian]);
    assert.equal(suppressed.rowCount, 0);
    await assert.rejects(() => service.setGuardianSafety(mother, { guardian_link_id: randomUUID(), confirmed: true }), { statusCode: 409 });
    await service.setGuardianSafety(mother, { guardian_link_id: link, confirmed: true });
    assert.equal((await service.support(mother)).guardian.safe_to_contact_confirmed, true);
    const request = randomUUID();
    const action = { client_request_id: request, notify_guardian: true, guardian_link_id: link };
    const queued = await service.requestSupport(mother, action);
    assert.equal(queued.guardian_notification, 'queued');
    assert.equal(queued.notification_delivery, 'pending');
    assert.equal(queued.source_type, 'manual');
    assert.equal(queued.status, 'open');
    assert.equal((await service.requestSupport(mother, action)).id, queued.id);
    await assert.rejects(() => service.requestSupport(mother, { client_request_id: request, notify_guardian: false }), { statusCode: 409 });
    const alert = await client.query('SELECT * FROM guardian_alerts WHERE crisis_event_id=$1', [queued.id]);
    assert.equal(alert.rowCount, 1);
    assert.equal(JSON.stringify(alert.rows).includes('PRIVATE_'), false);
    assert.equal(JSON.stringify(alert.rows).includes('923001234567'), false);
    assert.equal((await client.query('SELECT * FROM notification_outbox WHERE alert_id=$1', [alert.rows[0].id])).rowCount, 1);
    await assert.rejects(() => service.updateEvent(other, queued.id, { status: 'acknowledged' }), { statusCode: 404 });
    await assert.rejects(() => service.updateEvent(guardian, queued.id, { status: 'resolved', outcome: 'other' }), { statusCode: 403 });
    const ack = await service.updateEvent(mother, queued.id, { status: 'acknowledged' });
    assert.equal(ack.status, 'acknowledged');
    assert.equal(ack.resolved_at, null);
    const closed = await service.updateEvent(mother, queued.id, { status: 'resolved', outcome: 'support_contacted' });
    assert.equal(closed.closure_is_clinical_recovery, false);
    assert.equal(closed.notification_delivery, 'cancelled');
    assert.ok(closed.resolved_at);
    assert.equal((await service.updateEvent(mother, queued.id, { status: 'resolved', outcome: 'support_contacted' })).resolved_at.getTime(), closed.resolved_at.getTime());
    await assert.rejects(() => service.updateEvent(mother, queued.id, { status: 'acknowledged' }), { statusCode: 409 });
    await assert.rejects(() => service.updateEvent(mother, queued.id, { status: 'resolved', outcome: 'other' }), { statusCode: 409 });
    assert.equal((await client.query('SELECT status FROM notification_outbox WHERE alert_id=$1', [alert.rows[0].id])).rows[0].status, 'cancelled');
    const next = await service.requestSupport(mother, { client_request_id: randomUUID(), notify_guardian: true, guardian_link_id: link });
    await service.setGuardianSafety(mother, { guardian_link_id: link, confirmed: false });
    assert.equal((await client.query(`SELECT no.status FROM notification_outbox no JOIN guardian_alerts ga ON ga.id=no.alert_id WHERE ga.crisis_event_id=$1`, [next.id])).rows[0].status, 'cancelled');
    assert.equal((await service.support(mother)).guardian.safe_to_contact_confirmed, false);
    await service.setGuardianSafety(mother, { guardian_link_id: link, confirmed: true });
    await client.query("UPDATE guardian_links SET status='revoked',revoked_at=NOW() WHERE id=$1", [link]);
    const newLink = randomUUID();
    await client.query(`INSERT INTO guardian_links(id,mother_id,guardian_id,guardian_name,relationship,status,accepted_at)
      VALUES($1,$2,$3,'Different guardian','other','active',NOW())`, [newLink, mother, otherGuardian]);
    assert.equal((await service.support(mother)).guardian.safe_to_contact_confirmed, false);
    assert.equal((await service.requestSupport(mother, { client_request_id: randomUUID(), notify_guardian: true, guardian_link_id: link })).guardian_notification, 'unavailable');
    // Every row has the same transaction timestamp. The UUID tie-breaker must
    // prevent duplicate/skipped records when paging this real database history.
    const seen = new Set();
    let before;
    do {
      const page = await service.history(mother, { limit: '1', ...(before ? { before } : {}) });
      assert.equal(page.events.length, 1);
      assert.equal(seen.has(page.events[0].id), false);
      seen.add(page.events[0].id);
      before = page.next_cursor;
    } while (before);
    assert.equal(seen.size, (await client.query('SELECT COUNT(*)::int AS n FROM crisis_events WHERE mother_id=$1', [mother])).rows[0].n);
    assert.equal((await service.history(other, {})).events.length, 0);
    const erased = await service.deletePlan(mother, 1);
    assert.equal(erased.version, 2);
    assert.equal(erased.support_phone, '');
    assert.equal((await client.query('SELECT content_encrypted FROM crisis_safety_plans WHERE mother_id=$1', [mother])).rows[0].content_encrypted, null);
    await client.query('UPDATE users SET is_active=FALSE WHERE id=$1', [mother]);
    await assert.rejects(() => service.requestSupport(mother, { client_request_id: randomUUID(), notify_guardian: false }), { statusCode: 403 });
  } finally {
    db.query = originalQuery;
    db.withTransaction = originalTransaction;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
    if (previousEnv === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = previousEnv;
    if (previousPush === undefined) delete process.env.FIREBASE_PUSH_ENABLED; else process.env.FIREBASE_PUSH_ENABLED = previousPush;
  }
});
