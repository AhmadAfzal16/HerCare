const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
process.env.JWT_ACCESS_SECRET ||= 'synthetic-community-route-access-secret';
process.env.JWT_REFRESH_SECRET ||= 'synthetic-community-route-refresh-secret';
const service = require('../src/modules/community/community.service');
const router = require('../src/modules/community/community.routes');

test('M12 account-bound routes reject stale account before access checks, quota or content actions', async (t) => {
  const userId = randomUUID(); const otherId = randomUUID();
  const original = { actor: service.actor, spendQuota: service.spendQuota };
  let checks = 0; let writes = 0;
  service.actor = async () => { checks++; };
  service.spendQuota = async () => { writes++; };
  const guard = router.stack[2].handle;
  const run = async (header, method = 'POST') => {
    let result = 'not-called';
    await guard({ user: { userId }, method, get: () => header }, {}, (error) => { result = error; });
    return result;
  };
  try {
    await t.test('different account returns recoverable conflict without quota or database work', async () => {
      const error = await run(otherId);
      assert.equal(error.statusCode, 409);
      assert.equal(checks, 0); assert.equal(writes, 0);
    });
    await t.test('malformed account header never bypasses binding', async () => {
      const error = await run('not-an-account');
      assert.equal(error.statusCode, 422);
      assert.equal(checks, 0); assert.equal(writes, 0);
    });
    await t.test('matching account accepts canonical uppercase UUID and write quota', async () => {
      assert.equal(await run(userId.toUpperCase()), undefined);
      assert.equal(checks, 1); assert.equal(writes, 1);
    });
    await t.test('read and HEAD checks do not spend write quota; older clients remain compatible', async () => {
      assert.equal(await run(userId, 'GET'), undefined);
      assert.equal(await run(undefined, 'HEAD'), undefined);
      assert.equal(checks, 3); assert.equal(writes, 1);
    });
    await t.test('community response middleware prohibits shared or disk HTTP caches', () => {
      const headers = {};
      router.stack[1].handle({}, { set: (name, value) => { headers[name] = value; } }, () => {});
      assert.equal(headers['Cache-Control'], 'private, no-store');
    });
    await t.test('admin status and member list are wired to their protected service actions', () => {
      assert.ok(router.stack.some((layer) => layer.route?.path === '/moderation/status' && layer.route.methods.get));
      assert.ok(router.stack.some((layer) => layer.route?.path === '/members' && layer.route.methods.get));
    });
  } finally {
    service.actor = original.actor; service.spendQuota = original.spendQuota;
  }
});
