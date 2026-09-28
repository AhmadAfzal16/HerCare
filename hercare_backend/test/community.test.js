const test = require('node:test');
const assert = require('node:assert/strict');
const policy = require('../src/modules/community/community.policy');

test('community validates text, UUIDs and opaque pagination', () => {
  assert.equal(policy.text('  he\u200bllo  ', 2, 20), 'hello');
  assert.throws(() => policy.text('x', 2, 20));
  assert.throws(() => policy.uuid("' OR 1=1"));
  assert.throws(() => policy.onlyKeys({ role: 'admin' }, ['body']));
  const row = { cursor_time: '2026-09-26 12:00:00.123456+00', id: 'bf8b66ae-8708-4a01-a3bd-987478d239c4' };
  assert.deepEqual(policy.decodeCursor(policy.encodeCursor(row)), [row.cursor_time, row.id]);
  assert.throws(() => policy.decodeCursor('malformed'));
});
test('community multilingual safety triage and privacy flags', () => {
  assert.equal(policy.rules('I want to hurt myself').safety_support, true);
  assert.equal(policy.rules('خود کو نقصان').safety_support, true);
  assert.ok(policy.rules('contact person@example.com').flags.includes('privacy_or_link'));
  assert.equal(policy.rules('I feel supported today').safety_support, false);
  assert.match(policy.alias(), /^Kind (Lotus|Willow|Daisy|Olive) [a-f0-9]{10}$/);
});
test('AI failures and invalid scores never masquerade as successful moderation', async () => {
  const previous = process.env.COMMUNITY_MODERATION_URL;
  process.env.COMMUNITY_MODERATION_URL = 'https://moderation.example/v1/community/moderate';
  try {
    assert.equal((await policy.moderate('hello', async () => { throw new Error('offline'); })).ai, 'unavailable');
    assert.equal((await policy.moderate('hello', async () => ({ ok: true, json: async () => ({ scores: {}, model_version: 'x' }) }))).ai, 'unavailable');
    const result = await policy.moderate('hello', async () => ({ ok: true, json: async () => ({ model_version: 'test', scores: { self_harm: 0.8, bullying: 0, spam: 0, medical_advice: 0, support: 0.2 } }) }));
    assert.equal(result.safety_support, true);
    assert.equal(result.ai, 'available');
  } finally {
    if (previous === undefined) delete process.env.COMMUNITY_MODERATION_URL;
    else process.env.COMMUNITY_MODERATION_URL = previous;
  }
});
