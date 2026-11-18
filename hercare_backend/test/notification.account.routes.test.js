const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('notification requests are no-store and reject previous-account headers before controllers', async () => {
  const previousEnv = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const express = require('express');
  const controller = require('../src/modules/notifications/notification.controller');
  const { signAccessToken } = require('../src/utils/jwt');
  const { errorHandler } = require('../src/middleware/error_handler');
  const original = { getStatus: controller.getStatus, register: controller.register, unregister: controller.unregister };
  const seen = [];
  let server;
  try {
    for (const key of Object.keys(original)) {
      controller[key] = (req, res) => {
        seen.push({ action: key, userId: req.user.userId });
        return res.status(key === 'register' ? 201 : 200).json({ success: true, data: { synthetic: true } });
      };
    }
    const app = express();
    app.use(express.json({ limit: '32kb' }));
    app.use('/api/v1/notifications', require('../src/modules/notifications/notification.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const origin = `http://127.0.0.1:${server.address().port}/api/v1/notifications`;
    const userId = randomUUID();
    const auth = `Bearer ${signAccessToken({ userId, role: 'guardian' })}`;
    const request = (path, method = 'GET', account) => fetch(`${origin}${path}`, {
      method,
      headers: { Authorization: auth, 'Content-Type': 'application/json',
        ...(account ? { 'X-Notification-Account-Id': account } : {}) },
      ...(method === 'GET' ? {} : { body: JSON.stringify({ token: 'synthetic-device-token-never-sent-to-firebase', platform: 'android' }) }),
    });
    for (const account of [undefined, userId]) {
      for (const [path, method, status] of [['/status', 'GET', 200], ['/devices', 'POST', 201], ['/devices', 'DELETE', 200]]) {
        const response = await request(path, method, account);
        assert.equal(response.status, status);
        assert.equal(response.headers.get('cache-control'), 'no-store');
      }
    }
    assert.equal(seen.length, 6);
    assert.ok(seen.every((item) => item.userId === userId));
    for (const [path, method] of [['/status', 'GET'], ['/devices', 'POST'], ['/devices', 'DELETE']]) {
      const rejected = await request(path, method, randomUUID());
      assert.equal(rejected.status, 409);
      assert.equal(rejected.headers.get('cache-control'), 'no-store');
      assert.equal((await rejected.json()).success, false);
    }
    const invalidPreviousAccount = await fetch(`${origin}/devices`, {
      method: 'POST', headers: { Authorization: auth, 'Content-Type': 'application/json', 'X-Notification-Account-Id': randomUUID() },
      body: JSON.stringify({ token: 'bad', platform: 'invalid' }),
    });
    assert.equal(invalidPreviousAccount.status, 409, 'Account guard runs before device-body validation');
    assert.equal(invalidPreviousAccount.headers.get('cache-control'), 'no-store');
    assert.equal(seen.length, 6, 'Previous-account requests cannot reach any controller');
    const unauthenticated = await fetch(`${origin}/status`);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('cache-control'), 'no-store');
    assert.equal(seen.length, 6);
  } finally {
    Object.assign(controller, original);
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
    for (const key of Object.keys(process.env)) if (!(key in previousEnv)) delete process.env[key];
    Object.assign(process.env, previousEnv);
  }
});
