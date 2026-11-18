process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET ||= 'm9-test-access-secret-at-least-thirty-two-bytes';
process.env.JWT_REFRESH_SECRET ||= 'm9-test-refresh-secret-at-least-thirty-two-bytes';

const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const service = require('../src/modules/therapy/therapy.service');
const { normalizeSession } = require('../src/modules/therapy/therapy.validator');

function activity(overrides = {}) {
  return { activity_type: 'game', activity_id: 'domestic_puzzle', duration_seconds: 60,
    client_request_id: randomUUID(), ...overrides };
}

test('M9 validates bounded privacy-minimized records without fabricating optional mood', () => {
  const value = normalizeSession(activity());
  assert.equal(value.mood_before, null);
  assert.equal(value.mood_after, null);
  assert.equal(value.completed, true);
  for (const invalid of [activity({ duration_seconds: '60' }), activity({ duration_seconds: 7201 }),
    activity({ mood_before: 0 }), activity({ mood_after: 1.5 }), activity({ completed: 'false' }),
    activity({ worksheet: 'SYNTHETIC_PRIVATE_THOUGHT' }), activity({ activity_id: 'heavy_download_game' }),
    activity({ activity_type: 'constructor' }), activity({ activity_type: 'toString' }),
    activity({ client_request_id: 'not-an-id' }), null, []]) {
    assert.throws(() => normalizeSession(invalid), { statusCode: 422 });
  }
  assert.equal(service._private.publicSession({ completed: false, mood_before: 1, mood_after: 5 }).mood_change, null);
  assert.equal(service._private.publicSession({ completed: true, mood_before: null, mood_after: 5 }).mood_change, null);
});

test('M9 offline practice time is timezone-aware, calendar-valid and bounded by project policy', () => {
  const asOf = Date.parse('2026-10-12T12:00:00.000Z');
  const parse = (value) => normalizeSession(activity({ client_completed_at: value }), asOf).client_completed_at;
  assert.equal(parse('2026-10-12T16:59:00.123456+05:00'), '2026-10-12T11:59:00.123Z');
  assert.equal(parse('2026-10-12T11:59:00Z'), '2026-10-12T11:59:00.000Z');
  assert.equal(parse(new Date(asOf - 90 * 86400000).toISOString()), new Date(asOf - 90 * 86400000).toISOString());
  assert.equal(parse(new Date(asOf + 300000).toISOString()), new Date(asOf + 300000).toISOString());
  for (const invalid of [null, 42, 'not-a-date', '2026-10-12T12:00:00', '2026-10-12 12:00:00Z',
    '2026-09-31T12:00:00Z', '2026-10-12T24:00:00Z', '2026-10-12T12:60:00Z',
    '2026-10-12T12:00:60Z', '2026-10-12T12:00:00+14:15', '2026-10-12T12:00:00+05:60',
    new Date(asOf - 90 * 86400000 - 1).toISOString(), new Date(asOf + 300001).toISOString()]) {
    assert.throws(() => parse(invalid), { statusCode: 422 });
  }
  assert.equal(Object.hasOwn(normalizeSession(activity(), asOf), 'client_completed_at'), false,
    'legacy callers retain server-recorded timestamps without invented device values');
});

test('M9 fresh access rejects withdrawn consent, inactive users and stale mother roles', async () => {
  for (const rows of [[], [{ is_active: false, consent_tier1: true }],
    [{ is_active: true, consent_tier1: false }]]) {
    await assert.rejects(service._private.assertMother(randomUUID(), 'mother', {
      query: async () => ({ rows }),
    }), { statusCode: 403 });
  }
  await assert.rejects(service._private.assertMother(randomUUID(), 'guardian', {
    query: async () => { throw new Error('Unauthorized role must not query private records.'); },
  }), { statusCode: 403 });
  let locked = false;
  await service._private.assertMother(randomUUID(), 'mother', { query: async (sql) => {
    locked = sql.includes('FOR SHARE OF u, od') && sql.includes("u.role = 'mother'");
    return { rows: [{ is_active: true, consent_tier1: true }] };
  } }, true);
  assert.equal(locked, true, 'authorization and write must share a transaction with consent/owner locks');
});

test('M9 retries retain original identity but reject changed details without duplicate updates', async () => {
  const original = database.withTransaction;
  const request = activity({ mood_before: 2, mood_after: 3,
    client_completed_at: new Date(Date.now() - 60000).toISOString() });
  let row, inserts = 0;
  database.withTransaction = async (fn) => fn({ query: async (sql, args) => {
    if (sql.startsWith('SELECT u.is_active')) return { rows: [{ is_active: true, consent_tier1: true }] };
    if (sql.includes('INSERT INTO therapeutic_sessions')) {
      assert.equal(sql.includes('DO UPDATE'), false);
      if (row) return { rows: [] };
      inserts++;
      row = { id: randomUUID(), mother_id: args[0], activity_type: args[1], activity_id: args[2],
        duration_seconds: args[3], mood_before: args[4], mood_after: args[5], completed: args[6],
        client_request_id: args[7], completed_at: args[8] ?? new Date().toISOString() };
      return { rows: [row] };
    }
    return { rows: [row] };
  } });
  try {
    const owner = randomUUID();
    const first = await service.recordSession(owner, 'mother', request);
    assert.equal((await service.recordSession(owner, 'mother', request)).id, first.id);
    assert.equal(first.mood_change, 1);
    assert.equal(first.completed_at, request.client_completed_at);
    assert.equal(first.practice_verified, false);
    const legacyRequest = { ...request };
    delete legacyRequest.client_completed_at;
    assert.equal((await service.recordSession(owner, 'mother', legacyRequest)).id, first.id);
    await assert.rejects(service.recordSession(owner, 'mother', { ...request, duration_seconds: 61 }), { statusCode: 409 });
    await assert.rejects(service.recordSession(owner, 'mother', { ...request,
      client_completed_at: new Date(Date.parse(request.client_completed_at) + 1).toISOString() }), { statusCode: 409 });
    assert.equal(inserts, 1);
  } finally { database.withTransaction = original; }
});

test('M9 summary uses a bounded window and exposes no inferred recovery percentage', async () => {
  const original = database.query;
  let summarySql;
  database.query = async (sql) => {
    if (sql.startsWith('SELECT u.is_active')) return { rows: [{ is_active: true, consent_tier1: true }] };
    summarySql = sql;
    return { rows: [{ total_sessions: '6', completed_sessions: '4', total_seconds: '300',
      paired_mood_sessions: '0', avg_mood_change: null }] };
  };
  try {
    const summary = await service.getSummary(randomUUID(), 'mother');
    assert.equal(summary.period_days, 30);
    assert.equal(summary.paired_mood_sessions, 0);
    assert.equal(summary.avg_mood_change, null);
    assert.equal(summary.clinical_improvement, false);
    assert.equal(summary.completed_sessions, 4);
    assert.equal(summary.total_seconds, 300);
    assert.match(summarySql, /completed_at >= NOW\(\) - INTERVAL '30 days'/);
    assert.match(summarySql, /WHERE completed = TRUE AND mood_before IS NOT NULL/);
    await assert.rejects(service.getHistory(randomUUID(), 'mother', 101), { statusCode: 422 });
  } finally { database.query = original; }
});

test('M9 routes guard account and role, prevent caching and reject private worksheet uploads', async () => {
  const express = require('express');
  const { errorHandler, AppError } = require('../src/middleware/error_handler');
  const { signAccessToken } = require('../src/utils/jwt');
  const logger = require('../src/utils/logger');
  const previous = { getHistory: service.getHistory, recordSession: service.recordSession, error: logger.error };
  const logs = [];
  let allowed = true, conflict = false, reads = 0, writes = 0, server;
  try {
    logger.error = (...args) => logs.push(args);
    service.getHistory = async () => {
      if (!allowed) throw new AppError('Basic consent is withdrawn.', 403);
      reads++;
      return [];
    };
    service.recordSession = async (_owner, _role, value) => {
      if (conflict) throw new AppError('Activity request already saved.', 409);
      writes++;
      return normalizeSession(value);
    };
    const app = express();
    app.use(express.json({ limit: '32kb' }));
    app.use('/api/v1/therapy', require('../src/modules/therapy/therapy.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const owner = randomUUID();
    const url = 'http://127.0.0.1:' + server.address().port + '/api/v1/therapy/sessions';
    const headers = (role = 'mother', account = owner) => ({ 'Content-Type': 'application/json',
      Authorization: 'Bearer ' + signAccessToken({ userId: owner, role }), 'X-Therapy-Account-Id': account });
    for (const [head, status] of [[undefined, 401], [headers('guardian'), 403],
      [headers('mother', randomUUID()), 409]]) {
      const response = await fetch(url, { headers: head });
      assert.equal(response.status, status);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      if (status === 409) assert.equal((await response.json()).code, 'ACCOUNT_CHANGED');
    }
    assert.equal(reads, 0);
    assert.equal((await fetch(url, { headers: headers() })).status, 200);
    for (const value of [activity({ worksheet: 'SYNTHETIC_PRIVATE_NOTE' }), activity({ duration_seconds: '60' })]) {
      assert.equal((await fetch(url, { method: 'POST', headers: headers(), body: JSON.stringify(value) })).status, 422);
    }
    assert.equal(writes, 0);
    assert.equal((await fetch(url, { method: 'POST', headers: headers(), body: JSON.stringify(activity()) })).status, 201);
    conflict = true;
    assert.equal((await fetch(url, { method: 'POST', headers: headers(),
      body: JSON.stringify(activity({ mood_before: 2, mood_after: 3 })) })).status, 409);
    assert.equal(JSON.stringify(logs).includes('mood_before'), false, 'private rating payload must be redacted from error logs');
    allowed = false;
    assert.equal((await fetch(url, { headers: headers() })).status, 403);
    assert.equal(reads, 1);
  } finally {
    service.getHistory = previous.getHistory;
    service.recordSession = previous.recordSession;
    logger.error = previous.error;
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
  }
});
