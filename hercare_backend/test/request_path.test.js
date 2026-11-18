const test = require('node:test');
const assert = require('node:assert/strict');
const { requestPath } = require('../src/utils/request_path');

test('request logs omit all query and fragment values, including coordinates', () => {
  assert.equal(requestPath({ originalUrl: '/api/v1/crisis/facilities?latitude=31&longitude=74#private' }), '/api/v1/crisis/facilities');
  assert.equal(requestPath({ url: '/api/v1/crisis/plan?contact=secret' }), '/api/v1/crisis/plan');
  assert.equal(requestPath({ url: '/hello\nforged?raw=secret' }), '/helloforged');
  assert.equal(requestPath({}), '/');
  assert.equal(requestPath({ url: '/'.repeat(1000) }).length, 512);
});
