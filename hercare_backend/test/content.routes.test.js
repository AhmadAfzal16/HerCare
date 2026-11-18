const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
process.env.JWT_ACCESS_SECRET ||= 'synthetic-content-route-access-secret';
process.env.JWT_REFRESH_SECRET ||= 'synthetic-content-route-refresh-secret';
const service = require('../src/modules/content/content.service');
const router = require('../src/modules/content/content.routes');

test('M11 account-bound routes fail before database work on stale/missing account and stale JWT role', async () => {
  const userId = randomUUID(); let checks = 0; let writes = 0;
  const original = { actor: service.actor, quota: service.spendQuota };
  service.actor = async () => { checks++; return { role: 'mother' }; };
  service.spendQuota = async () => { writes++; };
  const guard = router.stack[2].handle;
  const run = async (header, role = 'mother', method = 'POST') => {
    let error;
    await guard({ user: { userId, role }, method, get: () => header }, {}, (value) => { error = value; });
    return error;
  };
  try {
    assert.equal((await run(undefined)).statusCode, 409);
    assert.equal((await run(randomUUID())).statusCode, 409);
    assert.equal((await run('not-a-uuid')).statusCode, 422);
    assert.equal(checks, 0); assert.equal(writes, 0);
    assert.equal((await run(userId, 'admin')).statusCode, 403);
    assert.equal(writes, 0);
    assert.equal(await run(userId.toUpperCase()), undefined);
    assert.equal(writes, 1);
    assert.equal(await run(userId, 'mother', 'GET'), undefined);
    assert.equal(writes, 1);
  } finally { service.actor = original.actor; service.spendQuota = original.quota; }
});
test('M11 all responses forbid HTTP caches and routes expose only protected actions', () => {
  const headers = {};
  router.stack[0].handle({}, { set: (key, value) => { headers[key] = value; } }, () => {});
  assert.equal(headers['Cache-Control'], 'private, no-store');
  assert.match(headers.Vary, /Authorization/);
  for (const route of ['/feed', '/saved', '/preferences', '/items/:id', '/items/:id/feedback', '/items/:id/saved',
    '/admin/items', '/admin/items/:id/review', '/admin/items/:id/publication', '/admin/policy']) {
    assert.ok(router.stack.some((layer) => layer.route?.path === route), route);
  }
});
