process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-at-least-thirty-two-bytes';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-at-least-thirty-two-bytes';

const test = require('node:test');
const assert = require('node:assert/strict');
const { analyzeMessage } = require('../src/modules/chat/chat_analysis');
const { encryptMessage, decryptMessage } = require('../src/modules/chat/chat_crypto');

test('chat encryption round-trips without storing plaintext', () => {
  const source = 'I need support today';
  const encrypted = encryptMessage(source);
  assert.notEqual(encrypted, source);
  assert.equal(encrypted.includes(source), false);
  assert.equal(decryptMessage(encrypted), source);
});

test('chat analysis detects multilingual danger language', () => {
  const result = analyzeMessage('میں خود کو نقصان پہنچانا چاہتی ہوں');
  assert.equal(result.containsDanger, true);
  assert.equal(result.language, 'ur');
  assert.equal(result.distressScore, 1);
});

test('ordinary supportive text does not trigger crisis handling', () => {
  const result = analyzeMessage('I am feeling better and supported today');
  assert.equal(result.containsDanger, false);
  assert.equal(result.sentimentLabel, 'positive');
});
