const assert = require('node:assert/strict');
const test = require('node:test');

const { decryptToken, encryptToken, hashToken } = require('../src/modules/notifications/push_crypto');

test('push device tokens are encrypted and recoverable', () => {
  const token = 'example-fcm-registration-token-with-sufficient-length';
  const encrypted = encryptToken(token);
  assert.notEqual(encrypted, token);
  assert.equal(encrypted.includes(token), false);
  assert.equal(decryptToken(encrypted), token);
});

test('push token hashes are stable without exposing the token', () => {
  const token = 'another-example-fcm-registration-token';
  const digest = hashToken(token);
  assert.equal(digest, hashToken(token));
  assert.match(digest, /^[a-f0-9]{64}$/);
  assert.equal(digest.includes(token), false);
});
