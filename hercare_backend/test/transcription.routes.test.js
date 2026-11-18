const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M5 routes enforce private account, role, no-store, bounded confirmation and redacted logs', async () => {
  process.env.NODE_ENV = 'test';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const express = require('express');
  const service = require('../src/modules/mood/transcription.service');
  const worker = require('../src/modules/mood/transcription.worker');
  const logger = require('../src/utils/logger');
  const { AppError, errorHandler } = require('../src/middleware/error_handler');
  const { signAccessToken } = require('../src/utils/jwt');
  const previous = { authorize: service.authorize, request: service.request, get: service.get,
    confirm: service.confirm, cancel: service.cancel, kick: worker.processPendingSafely, error: logger.error };
  const logs = [];
  let allowed = true, reads = 0, writes = 0, kicks = 0, server;
  try {
    logger.error = (...args) => logs.push(args);
    service.authorize = async () => { if (!allowed) throw new AppError('Private access unavailable.', 403); };
    service.request = async () => { writes++; return { status: 'queued' }; };
    service.get = async () => { reads++; return { status: 'review', draft: 'SYNTHETIC_PRIVATE_DRAFT' }; };
    service.confirm = async (_owner, _id, body) => { service.confirmation(body); return { confirmed: true, contains_danger: false }; };
    service.cancel = async () => ({ cancelled: true });
    worker.processPendingSafely = async () => { kicks++; };
    const app = express();
    app.use(express.json({ limit: '32kb' }));
    app.use('/api/v1/mood', require('../src/modules/mood/mood.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const id = randomUUID(), journal = randomUUID();
    const url = 'http://127.0.0.1:' + server.address().port + '/api/v1/mood/voice/' + journal + '/transcription';
    const headers = (role = 'mother', owner = id) => ({ 'Content-Type': 'application/json',
      Authorization: 'Bearer ' + signAccessToken({ userId: id, role }), 'X-Mood-Account-Id': owner });
    for (const [head, code] of [[undefined, 401], [headers('guardian'), 403], [headers('mother', randomUUID()), 409]]) {
      const result = await fetch(url, { headers: head });
      assert.equal(result.status, code); assert.equal(result.headers.get('cache-control'), 'no-store');
    }
    assert.equal(reads, 0);
    assert.equal((await fetch(url, { headers: headers() })).status, 200);
    assert.equal((await fetch(url, { method: 'POST', headers: headers(), body: '{}' })).status, 202);
    assert.equal(writes, 1); assert.equal(kicks, 1);
    const bad = await fetch(url, { method: 'PUT', headers: headers(), body: JSON.stringify({
      content: 'SYNTHETIC_SECRET_CORRECTION', revision: 1, client_request_id: randomUUID(), guardian_id: randomUUID()
    }) });
    assert.equal(bad.status, 422);
    assert.equal(JSON.stringify(logs).includes('SYNTHETIC_SECRET_CORRECTION'), false);
    allowed = false;
    assert.equal((await fetch(url, { headers: headers() })).status, 403);
    assert.equal(reads, 1, 'revoked/suspended access must not reach private reads');
  } finally {
    for (const name of ['authorize','request','get','confirm','cancel']) service[name] = previous[name];
    worker.processPendingSafely = previous.kick; logger.error = previous.error;
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
  }
});
