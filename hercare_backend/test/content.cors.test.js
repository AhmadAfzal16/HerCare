const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('installed CORS middleware supports live content account headers without exposing arbitrary origins', async () => {
  const previous = { ...process.env };
  process.env.NODE_ENV = 'test';
  process.env.CORS_ORIGINS = 'https://web.example';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  process.env.FIREBASE_PUSH_ENABLED = 'false';
  try {
    const middleware = require('../src/app')._router.stack.find((layer) => layer.name === 'corsMiddleware');
    const headers = new Map();
    const response = { setHeader: (name, value) => headers.set(name.toLowerCase(), value),
      getHeader: (name) => headers.get(name.toLowerCase()), end() {} };
    const request = { method: 'OPTIONS', headers: { origin: 'https://web.example',
      'access-control-request-method': 'GET',
      'access-control-request-headers': 'authorization,x-content-account-id' } };
    middleware.handle(request, response, () => assert.fail('Valid preflight should finish without auth/data access'));
    assert.equal(response.statusCode, 204);
    assert.match(headers.get('access-control-allow-headers'), /X-Content-Account-Id/);
    let rejected;
    middleware.handle({ ...request, headers: { ...request.headers, origin: 'https://untrusted.example' } }, response,
      (error) => { rejected = error; });
    assert.match(rejected.message, /origin not allowed/);
  } finally {
    await require('../src/config/database').pool.end();
    for (const key of Object.keys(process.env)) if (!(key in previous)) delete process.env[key];
    Object.assign(process.env, previous);
  }
});
