const test = require('node:test');
const assert = require('node:assert/strict');
const logger = require('../src/utils/logger');
const { errorHandler, AppError } = require('../src/middleware/error_handler');

function captureError(req, error = new AppError('Invalid request.', 422)) {
  const previous = logger.error;
  const logs = [];
  const response = {};
  const res = {
    status(code) { response.status = code; return this; },
    json(body) { response.body = body; return this; },
  };
  try {
    logger.error = (...args) => logs.push(args);
    errorHandler(error, req, res, () => {});
    return { logs, response };
  } finally {
    logger.error = previous;
  }
}

test('community error logs never retain submitted body, title, or nested moderation/session fields', () => {
  for (const path of ['/api/v1/community/posts', '/api/v1/community/moderation/item',
    '/api/v1/community/sessions', '/api/v1/community?query=private-query-value']) {
    const body = { title: 'private-title-value', body: 'private-post-value', reason: 'private-review-value',
      expert_name: 'private-expert-value', nested: { description: 'private-description-value' } };
    const { logs, response } = captureError({ method: 'POST', originalUrl: path, body });
    assert.equal(logs.length, 1);
    assert.equal(logs[0][1].body, '[REDACTED COMMUNITY REQUEST]');
    const serialized = JSON.stringify(logs);
    for (const secret of ['private-title-value', 'private-post-value', 'private-review-value',
      'private-expert-value', 'private-description-value', 'private-query-value']) {
      assert.equal(serialized.includes(secret), false);
    }
    assert.equal(response.status, 422);
    assert.equal(response.body.message, 'Invalid request.');
  }
});

test('community parser or database errors cannot echo submitted content through messages or stacks', () => {
  const error = new Error('Unexpected token from private-parser-value');
  error.status = 400;
  error.stack = 'Stack containing private-stack-value';
  const { logs, response } = captureError({ method: 'POST', url: '/api/v1/community/posts',
    body: { body: 'private-body-value' } }, error);
  const serialized = JSON.stringify(logs);
  assert.equal(serialized.includes('private-parser-value'), false);
  assert.equal(serialized.includes('private-stack-value'), false);
  assert.equal(serialized.includes('private-body-value'), false);
  assert.equal(logs[0][1].statusCode, 400);
  assert.equal(Object.hasOwn(logs[0][1], 'stack'), false);
  assert.equal(response.status, 400);
});

test('existing private-route redactions and unrelated field-level diagnostics are preserved', () => {
  for (const module of ['crisis', 'sleep', 'mood', 'therapy', 'chat']) {
    const { logs } = captureError({ method: 'POST', originalUrl: `/api/v1/${module}/item`,
      body: { body: 'private-existing-route-value' } });
    assert.equal(logs[0][1].body, '[REDACTED CRISIS REQUEST]');
    assert.equal(JSON.stringify(logs).includes('private-existing-route-value'), false);
  }
  const { logs } = captureError({ method: 'POST', originalUrl: '/api/v1/auth/login',
    body: { password: 'private-password-value', nested: { refresh_token: 'private-token-value' },
      ordinary_field: 'visible-diagnostic-value' } });
  assert.equal(logs[0][1].body.password, '[REDACTED]');
  assert.equal(logs[0][1].body.nested.refresh_token, '[REDACTED]');
  assert.equal(logs[0][1].body.ordinary_field, 'visible-diagnostic-value');
  assert.match(logs[0][0], /Invalid request/);
});
