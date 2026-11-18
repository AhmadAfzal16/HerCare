const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M7 polling uses its private bounded quota without consuming other care requests', async () => {
  const previous = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const service = require('../src/modules/chat/chat.service');
  const originalStatus = service.getStatus;
  const account = randomUUID();
  const token = require('../src/utils/jwt').signAccessToken({ userId: account, role: 'mother' });
  let server;
  try {
    // Rate-limit integration only; no account, database or clinical record is read.
    service.getStatus = async () => ({ available: false, unread_count: 0 });
    server = require('../src/app').listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const origin = `http://127.0.0.1:${server.address().port}`;
    for (let index = 0; index < 210; index++) {
      const response = await fetch(`${origin}/api/v1/chat/status`, {
        headers: { Authorization: `Bearer ${token}`, 'X-Chat-Account-Id': account },
      });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('ratelimit-limit'), '600');
      assert.equal(response.headers.get('cache-control'), 'no-store');
      await response.arrayBuffer();
    }
    const health = await fetch(`${origin}/health`);
    assert.equal(health.status, 200);
    assert.equal(health.headers.get('ratelimit-limit'), '200');
    assert.equal(health.headers.get('ratelimit-remaining'), '199');
    await health.arrayBuffer();
    const other = await fetch(`${origin}/api/v1/chatbot/__budget_probe`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(other.headers.get('ratelimit-limit'), '200', 'Hum-Raaz is not exempted with M7');
    assert.equal(other.headers.get('ratelimit-remaining'), '198');
    await other.arrayBuffer();
  } finally {
    service.getStatus = originalStatus;
    if (server) {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
    await require('../src/config/database').pool.end();
    for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
    Object.assign(process.env, previous);
  }
});
