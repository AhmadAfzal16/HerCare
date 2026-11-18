const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M10 facilities are public ETag-cacheable, ignore no private input, and never call private support', async () => {
  const previousEnv = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const express = require('express');
  const service = require('../src/modules/crisis/crisis.service');
  const directory = require('../src/modules/crisis/crisis.directory');
  const logger = require('../src/utils/logger');
  const { errorHandler } = require('../src/middleware/error_handler');
  const original = { support: service.support, error: logger.error };
  const logs = [];
  let supportReads = 0;
  let server;
  try {
    logger.error = (...args) => logs.push(args);
    service.support = async () => { supportReads++; throw new Error('Private support must not be read'); };
    const app = express();
    app.use('/api/v1/crisis', require('../src/modules/crisis/crisis.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const origin = `http://127.0.0.1:${server.address().port}/api/v1/crisis`;
    const first = await fetch(`${origin}/facilities`);
    assert.equal(first.status, 200);
    assert.equal(first.headers.get('cache-control'), 'public, max-age=300, must-revalidate');
    const body = await first.json();
    assert.equal(body.success, true);
    assert.deepEqual(body.data, directory.getCatalog());
    // Node fetch otherwise adds Cache-Control: no-cache to conditional default
    // requests. Test a real revalidation without overriding Express's RFC
    // behavior for clients that explicitly require a fresh response.
    const cached = await fetch(`${origin}/facilities`, { cache: 'force-cache', headers: { 'If-None-Match': first.headers.get('etag') } });
    assert.equal(cached.status, 304);
    assert.equal(await cached.text(), '');
    assert.equal(cached.headers.get('cache-control'), 'public, max-age=300, must-revalidate');
    assert.equal(cached.headers.get('etag'), first.headers.get('etag'));
    const forcedFresh = await fetch(`${origin}/facilities`, { headers: { 'If-None-Match': first.headers.get('etag'), 'Cache-Control': 'no-cache' } });
    assert.equal(forcedFresh.status, 200);
    assert.equal((await fetch(`${origin}/facilities`, { headers: { 'If-None-Match': '"stale-client-version"' } })).status, 200);
    for (const query of ['city=PRIVATE_CITY', 'latitude=31.500_PRIVATE&longitude=74_PRIVATE',
      'mother_id=PRIVATE_ACCOUNT', 'search=PRIVATE_JOURNAL', 'latitude[nested]=PRIVATE_GPS', '__proto__[latitude]=PRIVATE_GPS']) {
      const rejected = await fetch(`${origin}/facilities?${query}`);
      assert.equal(rejected.status, 422);
      assert.equal(rejected.headers.get('cache-control'), 'no-store');
      assert.equal((await rejected.json()).message.includes('PRIVATE'), false);
    }
    assert.equal(supportReads, 0);
    assert.equal(JSON.stringify(logs).includes('PRIVATE'), false, 'Rejected personal query strings must not reach logs');
    assert.equal((await fetch(`${origin}/support`)).status, 401);
  } finally {
    service.support = original.support;
    logger.error = original.error;
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
    for (const key of Object.keys(process.env)) if (!(key in previousEnv)) delete process.env[key];
    Object.assign(process.env, previousEnv);
  }
});
