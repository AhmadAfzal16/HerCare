const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M10 public contacts, mother-only routes, no-store, redaction and post-commit worker kick', async () => {
  const previousEnv = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const express = require('express');
  const service = require('../src/modules/crisis/crisis.service');
  const policy = require('../src/modules/crisis/crisis.policy');
  const push = require('../src/modules/notifications/notification.service');
  const logger = require('../src/utils/logger');
  const { errorHandler } = require('../src/middleware/error_handler');
  const { signAccessToken } = require('../src/utils/jwt');
  const previous = { support: service.support, requestSupport: service.requestSupport, savePlan: service.savePlan,
    processPendingSafely: push.processPendingSafely, error: logger.error };
  const logs = [];
  let kicks = 0;
  let requests = 0;
  let supportReads = 0;
  let transactionCommitted = false;
  let server;
  try {
    logger.error = (...args) => logs.push(args);
    service.support = async () => { supportReads++; return { plan: { version: 0 }, guardian: null, open_event: null }; };
    service.savePlan = async (_id, body) => policy.plan(body);
    service.requestSupport = async (_id, body) => {
      const request = policy.request(body);
      requests++;
      transactionCommitted = true;
      return { id: randomUUID(), guardian_notification: request.notify_guardian ? 'queued' : 'not_requested',
        notification_delivery: request.notify_guardian ? 'pending' : null };
    };
    push.processPendingSafely = async () => { assert.equal(transactionCommitted, true); kicks++; return { processed: 0 }; };
    const app = express();
    app.use(express.json({ limit: '32kb' }));
    app.use('/api/v1/crisis', require('../src/modules/crisis/crisis.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const origin = `http://127.0.0.1:${server.address().port}/api/v1/crisis`;
    const headers = (role) => ({ 'Content-Type': 'application/json', Authorization: `Bearer ${signAccessToken({ userId: randomUUID(), role })}` });
    const contacts = await fetch(`${origin}/contacts`);
    assert.equal(contacts.status, 200);
    assert.equal(contacts.headers.get('cache-control'), 'no-store');
    assert.ok((await contacts.json()).data.regions.length > 0);
    const unauthenticated = await fetch(`${origin}/support`);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('cache-control'), 'no-store');
    const guardian = await fetch(`${origin}/support`, { headers: headers('guardian') });
    assert.equal(guardian.status, 403);
    assert.equal(guardian.headers.get('cache-control'), 'no-store');
    const support = await fetch(`${origin}/support`, { headers: headers('mother') });
    assert.equal(support.status, 200);
    assert.equal(support.headers.get('cache-control'), 'no-store');
    assert.equal(supportReads, 1);
    const account = randomUUID();
    const mismatchedHeaders = { 'Content-Type': 'application/json',
      Authorization: `Bearer ${signAccessToken({ userId: account, role: 'mother' })}`,
      'X-Crisis-Account-Id': randomUUID() };
    const previousAccount = await fetch(`${origin}/support`, { headers: mismatchedHeaders });
    assert.equal(previousAccount.status, 409);
    assert.equal(previousAccount.headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(`${origin}/plan`, { method: 'PUT', headers: mismatchedHeaders,
      body: JSON.stringify({ version: 0, support_phone: '+923001234567' }) })).status, 409);
    assert.equal(supportReads, 1, 'Previous-account requests cannot reach the private service');
    const post = (body) => fetch(`${origin}/events`, { method: 'POST', headers: headers('mother'), body: JSON.stringify(body) });
    assert.equal((await post({ client_request_id: randomUUID(), notify_guardian: true, guardian_link_id: randomUUID() })).status, 200);
    assert.equal(kicks, 1);
    assert.equal((await post({ client_request_id: randomUUID(), notify_guardian: false })).status, 200);
    assert.equal(kicks, 1);
    assert.equal(requests, 2);
    const invalid = await fetch(`${origin}/plan`, { method: 'PUT', headers: headers('mother'),
      body: JSON.stringify({ version: 0, coping_step: 'SENSITIVE_PRIVATE_PLAN', support_phone: '+923001234567', unexpected: 'PRIVATE_EXTRA' }) });
    assert.equal(invalid.status, 422);
    assert.equal(JSON.stringify(logs).includes('SENSITIVE_PRIVATE_PLAN'), false);
    assert.equal(JSON.stringify(logs).includes('PRIVATE_EXTRA'), false);
    assert.equal(JSON.stringify(logs).includes('923001234567'), false);
    assert.equal((await fetch(`${origin}/plan`, { method: 'DELETE', headers: headers('mother') })).status, 422);
  } finally {
    service.support = previous.support;
    service.requestSupport = previous.requestSupport;
    service.savePlan = previous.savePlan;
    push.processPendingSafely = previous.processPendingSafely;
    logger.error = previous.error;
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
    for (const key of Object.keys(process.env)) if (!(key in previousEnv)) delete process.env[key];
    Object.assign(process.env, previousEnv);
  }
});
