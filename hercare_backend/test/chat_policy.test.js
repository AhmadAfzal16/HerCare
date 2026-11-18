const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const policy = require('../src/modules/chat/chat.policy');

const conversation = randomUUID();
const row = { id: randomUUID(), created_at_exact: '2026-10-12T08:30:20.123456Z' };

test('M7 cursors retain all PostgreSQL microseconds and bind the exact conversation', () => {
  const cursor = policy.encodeCursor(conversation, row);
  assert.deepEqual(policy.decodeCursor(cursor, conversation), {
    conversation_id: conversation, id: row.id, created_at: row.created_at_exact,
  });
  assert.throws(() => policy.decodeCursor(cursor, randomUUID()), { statusCode: 409 });
});

test('M7 cursor rejects malformed, noncanonical, duplicated and oversized payloads', () => {
  const value = { v: 1, c: conversation, t: row.created_at_exact, i: row.id };
  const encode = (text) => Buffer.from(text).toString('base64url');
  for (const cursor of ['not_a_cursor', 'x'.repeat(301), policy.encodeCursor(conversation, row) + '=',
    encode(JSON.stringify({ ...value, v: 2 })), encode(JSON.stringify({ ...value, extra: 1 })),
    encode(JSON.stringify({ c: conversation, v: 1, t: row.created_at_exact, i: row.id })),
    encode(`{"v":1,"v":1,"c":"${conversation}","t":"${row.created_at_exact}","i":"${row.id}"}`),
    encode(JSON.stringify(value, null, 2))]) {
    assert.throws(() => policy.decodeCursor(cursor, conversation), { statusCode: 422 });
  }
});

test('M7 timestamps validate calendar boundaries without Date rounding', () => {
  assert.equal(policy.timestamp('2024-02-29T23:59:59.999999Z'), '2024-02-29T23:59:59.999999Z');
  for (const timestamp of ['2026-02-29T08:00:00.123456Z', '2026-04-31T08:00:00.123456Z',
    '2026-10-12T24:00:00.123456Z', '2026-10-12T08:60:00.123456Z', '2026-10-12T08:00:60.123456Z',
    '0000-01-01T08:00:00.123456Z', '2026-00-12T08:00:00.123456Z', '2026-10-12T08:00:00.123Z',
    '2026-10-12T08:00:00.123456+00:00']) {
    assert.throws(() => policy.timestamp(timestamp), { statusCode: 422 });
  }
});

test('M7 page accepts only bounded single-direction query fields', () => {
  assert.equal(policy.pageQuery({ conversation_id: conversation }).limit, 30);
  assert.equal(policy.pageQuery({ conversation_id: conversation, limit: '50' }).limit, 50);
  const cursor = policy.encodeCursor(conversation, row);
  assert.equal(policy.pageQuery({ conversation_id: conversation, after: cursor }).after.created_at, row.created_at_exact);
  for (const query of [{}, { conversation_id: conversation, before: cursor, after: cursor },
    { conversation_id: conversation, limit: '0' }, { conversation_id: conversation, limit: '51' },
    { conversation_id: conversation, limit: '01' }, { conversation_id: conversation, limit: ['30'] },
    { conversation_id: conversation, limit: 30 }, { conversation_id: [conversation] },
    { conversation_id: conversation, account_id: randomUUID() }]) {
    assert.throws(() => policy.pageQuery(query), { statusCode: 422 });
  }
});

test('M7 send compatibility trims once and rejects unknown fields, malformed IDs and unbounded content', () => {
  const request = { content: '  Private supportive text.  ', client_request_id: randomUUID() };
  assert.deepEqual(policy.sendBody(request), { ...request, content: 'Private supportive text.', conversation_id: null });
  assert.equal(policy.sendBody({ ...request, conversation_id: conversation }).conversation_id, conversation);
  for (const input of [null, [], { ...request, content: '  ' }, { ...request, content: 'x'.repeat(2001) },
    { ...request, content: 5 }, { ...request, client_request_id: 'invalid' }, { ...request, raw_journal: 'private' },
    { ...request, conversation_id: null }]) assert.throws(() => policy.sendBody(input), { statusCode: 422 });
});

test('M7 read supports legacy bodyless calls but modern cursor must have its conversation', () => {
  assert.deepEqual(policy.readBody(), { conversation_id: null, through: null, from: null });
  assert.deepEqual(policy.readBody({ conversation_id: conversation }), { conversation_id: conversation, through: null, from: null });
  const cursor = policy.encodeCursor(conversation, row);
  assert.equal(policy.readBody({ conversation_id: conversation, through_cursor: cursor }).through.id, row.id);
  const earlier = policy.encodeCursor(conversation, { ...row, created_at_exact: '2026-10-12T08:30:20.123455Z' });
  assert.equal(policy.readBody({ conversation_id: conversation, through_cursor: cursor, from_cursor: earlier }).from.created_at,
    '2026-10-12T08:30:20.123455Z');
  for (const data of [{ through_cursor: cursor }, { conversation_id: conversation, all_users: true }, null, []]) {
    assert.throws(() => policy.readBody(data), { statusCode: 422 });
  }
  assert.throws(() => policy.readBody({ conversation_id: conversation, from_cursor: cursor }), { statusCode: 422 });
  assert.throws(() => policy.readBody({ conversation_id: conversation, from_cursor: cursor, through_cursor: earlier }), { statusCode: 422 });
});
