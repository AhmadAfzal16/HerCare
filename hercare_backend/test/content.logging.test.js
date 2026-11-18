const test = require('node:test');
const assert = require('node:assert/strict');
const logger = require('../src/utils/logger');
const { errorHandler } = require('../src/middleware/error_handler');

test('M11 errors retain no preference, catalog-body, review, source-query or exception text', () => {
  const previous = logger.error;
  const logs = [];
  logger.error = (...args) => logs.push(args);
  try {
    for (const path of ['/api/v1/content/preferences', '/api/v1/content/admin/items', '/api/v1/content/items/id/feedback']) {
      const error = new Error('secret-parser-text');
      error.stack = 'secret-stack-text';
      error.status = 400;
      const response = { status() { return this; }, json() {} };
      errorHandler(error, { method: 'PUT', originalUrl: `${path}?private-query-value=secret-query`, body: {
        religious_enabled: true, music_enabled: false, body_ur: 'secret-source-body',
        review_note: 'secret-review-note', nested: { source_url: 'secret-url' },
      } }, response, () => {});
    }
    assert.equal(logs.length, 3);
    for (const entry of logs) {
      assert.equal(entry[1].body, '[REDACTED CONTENT REQUEST]');
      assert.equal(entry[1].statusCode, 400);
      assert.equal(Object.hasOwn(entry[1], 'stack'), false);
    }
    assert.equal(JSON.stringify(logs).includes('secret-'), false);
    assert.equal(JSON.stringify(logs).includes('religious_enabled'), false);
    assert.equal(JSON.stringify(logs).includes('music_enabled'), false);
  } finally { logger.error = previous; }
});
