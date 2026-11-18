const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const express = require('express');
const http = require('node:http');

test('M7 private route boundaries and polling budgets (stub handlers, no database or app launch)', async (t) => {
  process.env.JWT_ACCESS_SECRET = 'synthetic-chat-route-access-secret-not-a-production-key';
  process.env.JWT_REFRESH_SECRET = 'synthetic-chat-route-refresh-secret-not-a-production-key';
  const auth = require('../src/middleware/auth');
  const controllers = require('../src/modules/chat/chat.controller');
  const originalAuth = auth.authenticate; const originals = { ...controllers };
  const mother = randomUUID(); const guardian = randomUUID();
  auth.authenticate = (req, res, next) => {
    if (req.get('Authorization') !== 'synthetic-session') return res.status(401).json({ success: false });
    req.user = { userId: req.get('Synthetic-Account') || mother, role: 'mother' };
    return next();
  };
  for (const key of Object.keys(controllers)) controllers[key] = (_req, res) => res.json({ success: true, data: [] });
  delete require.cache[require.resolve('../src/modules/chat/chat.routes')];
  const app = express();
  app.use(express.json());
  app.use('/chat', require('../src/modules/chat/chat.routes'));
  app.use((error, _req, res, _next) => res.status(error.statusCode || 500).json({ success: false, message: error.message }));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const request = (path, options = {}) => new Promise((resolve, reject) => {
    const body = options.body && JSON.stringify(options.body);
    const req = http.request({ host: '127.0.0.1', port: server.address().port, path: '/chat' + path,
      method: options.method || 'GET', headers: { ...(options.auth === false ? {} : { Authorization: 'synthetic-session' }),
        ...(body ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } : {}), ...options.headers } }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString() }));
    });
    req.on('error', reject); if (body) req.write(body); req.end();
  });
  try {
    await t.test('unauthenticated, stale-account and successful read responses all forbid private caching', async () => {
      const denied = await request('/status', { auth: false });
      const stale = await request('/status', { headers: { 'X-Chat-Account-Id': randomUUID() } });
      const accepted = await request('/status', { headers: { 'X-Chat-Account-Id': mother } });
      assert.equal(denied.status, 401); assert.equal(stale.status, 409); assert.equal(accepted.status, 200);
      for (const response of [denied, stale, accepted]) {
        assert.equal(response.headers['cache-control'], 'no-store');
        assert.equal(response.headers.pragma, 'no-cache');
      }
    });
    await t.test('per-account read budget supports polling but bounds status, page and receipts together', async () => {
      // One accepted mother read above; 599 additional reads reach the common 600 budget.
      for (let i = 0; i < 599; i++) {
        const response = await request(i % 2 ? '/messages/page' : '/read', i % 2 ? {} : { method: 'PATCH', body: {} });
        assert.equal(response.status, 200);
      }
      const rejected = await request('/status');
      assert.equal(rejected.status, 429);
      assert.equal(rejected.headers['cache-control'], 'no-store');
      assert.ok(Number(rejected.headers['retry-after']) > 0);
      assert.equal((await request('/status', { headers: { 'Synthetic-Account': guardian } })).status, 200);
    });
    await t.test('send budget is independent and bounded per account rather than shared IP', async () => {
      for (let i = 0; i < 30; i++) {
        assert.equal((await request('/messages', { method: 'POST', body: { content: 'Synthetic text.', client_request_id: randomUUID() } })).status, 200);
      }
      const rejected = await request('/messages', { method: 'POST', body: { content: 'Synthetic text.', client_request_id: randomUUID() } });
      assert.equal(rejected.status, 429); assert.equal(rejected.headers['cache-control'], 'no-store');
      assert.equal((await request('/messages', { method: 'POST', headers: { 'Synthetic-Account': guardian },
        body: { content: 'Synthetic text.', client_request_id: randomUUID() } })).status, 200);
    });
    await t.test('pre-auth IP limiter also bounds invalid-session traffic', async () => {
      let rejected;
      for (let i = 0; i < 1001; i++) {
        const response = await request('/status', { auth: false });
        if (response.status === 429) { rejected = response; break; }
        assert.equal(response.status, 401);
      }
      assert.ok(rejected);
      assert.equal(rejected.headers['cache-control'], 'no-store');
      assert.ok(Number(rejected.headers['retry-after']) > 0);
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    auth.authenticate = originalAuth; Object.assign(controllers, originals);
    delete require.cache[require.resolve('../src/modules/chat/chat.routes')];
    await require('../src/config/database').pool.end();
  }
});
