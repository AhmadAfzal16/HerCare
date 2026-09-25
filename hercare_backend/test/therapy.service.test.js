process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-at-least-thirty-two-bytes';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-at-least-thirty-two-bytes';

const test = require('node:test');
const assert = require('node:assert/strict');
const { _private } = require('../src/modules/therapy/therapy.service');
const { isKnownActivity } = require('../src/modules/therapy/therapy.catalog');

test('low mood prioritizes grounding without making a clinical claim', () => {
  const value = _private.chooseRecommendation({
    mood: 2, sleepQuality: 4, screenMinutes: 20, lateNightMinutes: 0, safetyPriority: false,
  });
  assert.equal(value.activity_id, 'grounding_54321');
  assert.equal(value.safety_priority, false);
});

test('safety signal always overrides ordinary activity selection', () => {
  const value = _private.chooseRecommendation({
    mood: 5, sleepQuality: 5, screenMinutes: 0, lateNightMinutes: 0, safetyPriority: true,
  });
  assert.equal(value.safety_priority, true);
  assert.equal(value.activity_id, 'breathing_478');
});

test('catalog rejects arbitrary activity identifiers', () => {
  assert.equal(isKnownActivity('game', 'memory_match'), true);
  assert.equal(isKnownActivity('game', 'downloaded_heavy_game'), false);
});

