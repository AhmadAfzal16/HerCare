const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('actual app CORS permits account-bound community preflight only for allowed web origins', async () => {
  const previous = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.CORS_ORIGINS = 'https://web.example';
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  try {
    // Exercise the installed middleware directly: no HTTP listener or database
    // access is necessary for a browser's OPTIONS preflight.
    const app = require('../src/app');
    const middleware = app._router.stack.find((layer) => layer.name === 'corsMiddleware');
    assert.ok(middleware);
    const headers = new Map();
    let ended = false;
    const response = {
      setHeader: (name, value) => headers.set(name.toLowerCase(), value),
      getHeader: (name) => headers.get(name.toLowerCase()),
      end: () => { ended = true; },
    };
    const request = { method: 'OPTIONS', headers: {
      origin: 'https://web.example',
      'access-control-request-method': 'POST',
      'access-control-request-headers': 'authorization,content-type,x-community-account-id',
    } };
    middleware.handle(request, response, () => assert.fail('Allowed preflight must finish before authentication'));
    assert.equal(response.statusCode, 204);
    assert.equal(ended, true);
    assert.equal(headers.get('access-control-allow-origin'), 'https://web.example');
    assert.ok(headers.get('access-control-allow-headers').toLowerCase().includes('x-community-account-id'));
    let denied;
    middleware.handle({ ...request, headers: { ...request.headers, origin: 'https://untrusted.example' } }, response,
      (error) => { denied = error; });
    assert.match(denied.message, /origin not allowed/);
  } finally {
    await require('../src/config/database').pool.end();
    for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
    Object.assign(process.env, previous);
  }
});
