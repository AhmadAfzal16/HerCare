const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('community real database isolation, review, idempotency, blocking and pagination', {
  skip: process.env.RUN_COMMUNITY_DB_TEST !== '1',
}, async () => {
  const database = require('../src/config/database');
  const client = await database.pool.connect();
  const originalQuery = database.query;
  const originalTransaction = database.withTransaction;
  const policy = require('../src/modules/community/community.policy');
  const originalModerate = policy.moderate;
  const originalRequired = process.env.COMMUNITY_AI_REQUIRED;
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
    const syntheticModerate = async (text) => ({ ...policy.rules(text), ai: 'available', model_version: 'synthetic-integration-only',
      policy_version: 'synthetic-policy', runtime: 'onnx-cpu', full_text_processed: true, clinical_validation: false,
      scores: { self_harm: 0, bullying: 0, spam: 0, medical_advice: 0, support: 0.8 } });
    policy.moderate = syntheticModerate;
    process.env.COMMUNITY_AI_REQUIRED = 'true';
    const service = require('../src/modules/community/community.service');
    const { RULES_VERSION } = require('../src/modules/community/community.policy');
    const ids = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    for (let i = 0; i < ids.length; i++) {
      await client.query('INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,$3,$4,TRUE)',
        [ids[i], `t${ids[i].replaceAll('-', '').slice(0, 13)}`, 'test-only', i === 2 ? 'admin' : i === 3 ? 'guardian' : 'mother']);
    }
    const [mother, other, admin, guardian] = ids;
    await assert.rejects(service.status(guardian), /mothers/);
    await assert.rejects(service.list(mother), /guidelines/);
    for (const id of ids.slice(0, 3)) await service.join(id, { accepted: true, rules_version: RULES_VERSION });
    const request = { title: 'Recovery together', body: 'Today I felt supported.', topic: 'recovery', client_request_id: randomUUID() };
    const post = await service.create(mother, request);
    assert.equal(post.status, 'pending');
    assert.notEqual(post.author.id, mother);
    assert.equal(JSON.stringify(post).includes(mother), false);
    assert.equal((await service.create(mother, request)).id, post.id);
    await assert.rejects(service.create(mother, { ...request, body: 'A different retry payload.' }), { statusCode: 409 });
    assert.equal((await service.status(mother)).member_id, post.author.id);
    assert.equal((await service.list(other)).items.some((p) => p.id === post.id), false);
    await assert.rejects(service.detail(other, post.id), /unavailable/);
    await assert.rejects(service.queue(other), /Moderator/);
    await service.review(admin, post.id, { decision: 'publish', reason: 'Reviewed safe', version: 1 });
    assert.equal((await service.detail(other, post.id)).body, request.body);
    const stored = await client.query('SELECT body_encrypted FROM community_content WHERE id=$1', [post.id]);
    assert.equal(stored.rows[0].body_encrypted.includes(request.body), false);
    await service.react(other, post.id, { kind: 'solidarity', active: true });
    await service.react(other, post.id, { kind: 'solidarity', active: true });
    assert.equal((await service.detail(other, post.id)).reactions.solidarity, 1);
    await service.report(other, post.id, { reason: 'privacy' });
    await assert.rejects(service.review(admin, post.id, { decision: 'publish', reason: 'Reviewed again', version: 2 }), /changed/);
    assert.ok((await service.queue(admin)).items.some((p) => p.id === post.id));
    await service.review(admin, post.id, { decision: 'publish', reason: 'Reviewed privacy report', version: 3 });
    await service.block(other, post.author.id, true);
    await assert.rejects(service.detail(other, post.id), /unavailable/);
    await service.block(other, post.author.id, false);
    const reply = await service.create(other, { body: 'Wishing you well.', parent_id: post.id, client_request_id: randomUUID() });
    assert.equal((await service.list(mother, { parent_id: post.id })).items.length, 0);
    assert.ok((await service.list(other, { mine: 'true', include_replies: 'true' })).items.some((item) => item.id === reply.id && item.status === 'pending'));
    await service.review(admin, reply.id, { decision: 'publish', reason: 'Supportive reply', version: 1 });
    assert.equal((await service.detail(mother, post.id)).comment_count, 1);
    for (let i = 0; i < 21; i++) await service.create(mother, { ...request, client_request_id: randomUUID() });
    const first = await service.list(mother, { mine: 'true' });
    const second = await service.list(mother, { mine: 'true', cursor: first.next_cursor });
    assert.equal(first.items.length, 20);
    assert.equal(second.items.length, 2);
    assert.equal(new Set([...first.items, ...second.items].map((p) => p.id)).size, 22);
    const pendingQueue = await service.queue(admin);
    assert.equal(pendingQueue.items.length, 20);
    const pendingNext = await service.queue(admin, pendingQueue.next_cursor);
    assert.equal(pendingNext.items.length, 1);
    assert.equal(new Set([...pendingQueue.items, ...pendingNext.items].map((p) => p.id)).size, 21);
    assert.ok(pendingQueue.items.every((p) => p.can_publish));
    const memberPage = await service.members(admin);
    assert.ok(memberPage.items.some((member) => member.id === post.author.id));
    assert.deepEqual(Object.keys(memberPage.items[0]).sort(), ['alias', 'id', 'joined_at', 'suspended']);
    await assert.rejects(service.members(other), { statusCode: 403 });
    await client.query("UPDATE users SET role = 'guardian' WHERE id = $1", [mother]);
    await assert.rejects(service.detail(other, post.id), { statusCode: 404 });
    await client.query("UPDATE users SET role = 'mother' WHERE id = $1", [mother]);
    const orphan = await service.create(other, { body: 'A pending supportive reply.', parent_id: post.id, client_request_id: randomUUID() });
    await service.remove(mother, post.id);
    await service.remove(mother, post.id);
    await assert.rejects(service.create(mother, request), { statusCode: 410 });
    await assert.rejects(service.detail(other, reply.id), /unavailable/);
    await assert.rejects(service.review(admin, orphan.id, { decision: 'publish', reason: 'Parent was deleted', version: 1 }), { statusCode: 409 });
    let orphanItem = (await service.queue(admin)).items.find((item) => item.id === orphan.id);
    if (!orphanItem) orphanItem = (await service.queue(admin, (await service.queue(admin)).next_cursor)).items.find((item) => item.id === orphan.id);
    assert.equal(orphanItem.can_publish, false);
    assert.equal(orphanItem.publication_blocked_reason, 'parent_unavailable');
    await service.review(admin, orphan.id, { decision: 'remove', reason: 'Removed orphaned reply', version: 1 });
    await service.suspend(admin, post.author.id, { suspended: true, reason: 'Test suspension' });
    await assert.rejects(service.status(mother), /suspended/);
    await service.suspend(admin, post.author.id, { suspended: false, reason: 'Test restoration' });
    assert.equal((await service.status(mother)).joined, true);
    const sessionData = { title: 'Recovery questions', description: 'A moderated professional discussion', expert_name: 'Test professional', credentials: 'Verified test fixture',
      starts_at: new Date(Date.now() - 60000).toISOString(), ends_at: new Date(Date.now() + 3600000).toISOString(), client_request_id: randomUUID() };
    await assert.rejects(service.schedule(other, sessionData), /Moderator/);
    await assert.rejects(service.schedule(admin, { ...sessionData, starts_at: '2026-09-26T12:00' }), /timezone/);
    const session = await service.schedule(admin, sessionData);
    assert.equal((await service.schedule(admin, sessionData)).id, session.id);
    await assert.rejects(service.schedule(admin, { ...sessionData, title: 'Another session' }), { statusCode: 409 });
    const question = await service.create(mother, { ...request, session_id: session.id, client_request_id: randomUUID() });
    await service.review(admin, question.id, { decision: 'publish', reason: 'Reviewed question', version: 1 });
    const answer = await service.create(admin, { body: 'Please speak with your care team.', parent_id: question.id, client_request_id: randomUUID() });
    assert.equal(answer.expert_answer, true);
    assert.equal(answer.status, 'pending');
    await service.cancelSession(admin, session.id);
    assert.equal((await service.detail(mother, question.id)).session_closed, true);
    await assert.rejects(service.create(other, { ...request, session_id: session.id, client_request_id: randomUUID() }), /closed/);
    policy.moderate = async (text) => ({ ...policy.rules(text), ai: 'unavailable' });
    const outage = await service.create(other, { ...request, client_request_id: randomUUID() });
    assert.equal(outage.status, 'pending');
    await assert.rejects(service.review(admin, outage.id, { decision: 'publish', reason: 'Must wait for AI triage', version: 1 }), { statusCode: 503 });
    const privateOutage = await client.query('SELECT status,moderation FROM community_content WHERE id=$1', [outage.id]);
    assert.equal(privateOutage.rows[0].status, 'pending');
    policy.moderate = syntheticModerate;
    await service.review(admin, outage.id, { decision: 'publish', reason: 'Reviewed after triage recovered', version: 1 });
    const audited = await client.query('SELECT moderation FROM community_content WHERE id=$1', [outage.id]);
    assert.equal(audited.rows[0].moderation.human_review, true);
    assert.equal(audited.rows[0].moderation.full_text_processed, true);
    assert.equal(audited.rows[0].moderation.clinical_validation, false);
    // Awaited inference must not turn an already-revoked account into a committed writer.
    const revokedRequest = { ...request, client_request_id: randomUUID() };
    policy.moderate = async (text) => {
      await client.query('UPDATE users SET is_active = FALSE WHERE id = $1', [mother]);
      return syntheticModerate(text);
    };
    await assert.rejects(service.create(mother, revokedRequest), { statusCode: 403 });
    const notInserted = await client.query('SELECT id FROM community_content WHERE client_request_id = $1', [revokedRequest.client_request_id]);
    assert.equal(notInserted.rows.length, 0);
    await client.query('UPDATE users SET is_active = TRUE WHERE id = $1', [mother]);
    policy.moderate = syntheticModerate;
    const staleReview = await service.create(other, { ...request, client_request_id: randomUUID() });
    policy.moderate = async (text) => {
      await client.query("UPDATE users SET role = 'mother' WHERE id = $1", [admin]);
      return syntheticModerate(text);
    };
    await assert.rejects(service.review(admin, staleReview.id, { decision: 'publish', reason: 'Role changed during analysis', version: 1 }), { statusCode: 403 });
    await client.query("UPDATE users SET role = 'admin' WHERE id = $1", [admin]);
    policy.moderate = async (text) => {
      await client.query('UPDATE community_members SET suspended = TRUE WHERE user_id = $1', [other]);
      return syntheticModerate(text);
    };
    await assert.rejects(service.review(admin, staleReview.id, { decision: 'publish', reason: 'Author suspended during analysis', version: 1 }), { statusCode: 409 });
    const stillPrivate = await client.query('SELECT status,version FROM community_content WHERE id=$1', [staleReview.id]);
    assert.deepEqual(stillPrivate.rows[0], { status: 'pending', version: 1 });
    await client.query('UPDATE community_members SET suspended = FALSE WHERE user_id = $1', [other]);
    policy.moderate = syntheticModerate;
    const parentRace = await service.create(mother, { ...request, client_request_id: randomUUID() });
    await service.review(admin, parentRace.id, { decision: 'publish', reason: 'Reviewed parent race fixture', version: 1 });
    const childRace = await service.create(other, { body: 'A private pending reply.', parent_id: parentRace.id, client_request_id: randomUUID() });
    policy.moderate = async (text) => {
      await service.remove(mother, parentRace.id);
      return syntheticModerate(text);
    };
    await assert.rejects(service.review(admin, childRace.id, { decision: 'publish', reason: 'Parent deleted during analysis', version: 1 }), { statusCode: 409 });
    const childPrivate = await client.query('SELECT status FROM community_content WHERE id=$1', [childRace.id]);
    assert.equal(childPrivate.rows[0].status, 'pending');
    policy.moderate = syntheticModerate;
    for (let i = 0; i < 60; i++) await service.spendQuota(other);
    await assert.rejects(service.spendQuota(other), /take a moment/);
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    policy.moderate = originalModerate;
    if (originalRequired === undefined) delete process.env.COMMUNITY_AI_REQUIRED;
    else process.env.COMMUNITY_AI_REQUIRED = originalRequired;
    client.release();
    await database.pool.end();
  }
});
