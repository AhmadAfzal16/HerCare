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
  try {
    await client.query('BEGIN');
    database.query = (...args) => client.query(...args);
    database.withTransaction = (fn) => fn(client);
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
    await service.block(other, post.author.id, true);
    await assert.rejects(service.detail(other, post.id), /unavailable/);
    await service.block(other, post.author.id, false);
    const reply = await service.create(other, { body: 'Wishing you well.', parent_id: post.id, client_request_id: randomUUID() });
    assert.equal((await service.list(mother, { parent_id: post.id })).items.length, 0);
    await service.review(admin, reply.id, { decision: 'publish', reason: 'Supportive reply', version: 1 });
    assert.equal((await service.detail(mother, post.id)).comment_count, 1);
    for (let i = 0; i < 21; i++) await service.create(mother, { ...request, client_request_id: randomUUID() });
    const first = await service.list(mother, { mine: 'true' });
    const second = await service.list(mother, { mine: 'true', cursor: first.next_cursor });
    assert.equal(first.items.length, 20);
    assert.equal(second.items.length, 2);
    assert.equal(new Set([...first.items, ...second.items].map((p) => p.id)).size, 22);
    await service.remove(mother, post.id);
    await assert.rejects(service.detail(other, reply.id), /unavailable/);
    await service.suspend(admin, post.author.id, { suspended: true, reason: 'Test suspension' });
    await assert.rejects(service.status(mother), /suspended/);
    await service.suspend(admin, post.author.id, { suspended: false, reason: 'Test restoration' });
    assert.equal((await service.status(mother)).joined, true);
    const sessionData = { title: 'Recovery questions', description: 'A moderated professional discussion', expert_name: 'Test professional', credentials: 'Verified test fixture',
      starts_at: new Date(Date.now() - 60000).toISOString(), ends_at: new Date(Date.now() + 3600000).toISOString() };
    await assert.rejects(service.schedule(other, sessionData), /Moderator/);
    await assert.rejects(service.schedule(admin, { ...sessionData, starts_at: '2026-09-26T12:00' }), /timezone/);
    const session = await service.schedule(admin, sessionData);
    const question = await service.create(mother, { ...request, session_id: session.id, client_request_id: randomUUID() });
    await service.review(admin, question.id, { decision: 'publish', reason: 'Reviewed question', version: 1 });
    const answer = await service.create(admin, { body: 'Please speak with your care team.', parent_id: question.id, client_request_id: randomUUID() });
    assert.equal(answer.expert_answer, true);
    assert.equal(answer.status, 'pending');
    await service.cancelSession(admin, session.id);
    await assert.rejects(service.create(other, { ...request, session_id: session.id, client_request_id: randomUUID() }), /closed/);
    for (let i = 0; i < 60; i++) await service.spendQuota(other);
    await assert.rejects(service.spendQuota(other), /take a moment/);
  } finally {
    await client.query('ROLLBACK');
    database.query = originalQuery;
    database.withTransaction = originalTransaction;
    client.release();
    await database.pool.end();
  }
});
