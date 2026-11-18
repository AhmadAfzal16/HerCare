const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const policy = require('../src/modules/chatbot/chatbot.policy');
const crypto = require('../src/modules/chatbot/chatbot.crypto');
const client = require('../src/modules/chatbot/chatbot.client');
const { slope, aggregate } = require('../src/modules/chatbot/chatbot.context');

test('chatbot validation bounds messages, language, ids and default-off consent', () => {
  assert.equal(policy.message({ message: ' hello ', language: 'roman_ur', client_request_id: randomUUID() }).message, 'hello');
  for (const body of [{ message: '', language: 'en', client_request_id: randomUUID() },
    { message: 'hello', language: 'mixed', client_request_id: randomUUID() },
    { message: 'hello', language: 'en', client_request_id: randomUUID(), context: { override: true } },
    { message: 'x'.repeat(4001), language: 'en', client_request_id: randomUUID() }]) {
    assert.throws(() => policy.message(body), { statusCode: 422 });
  }
  assert.throws(() => policy.consent({ enabled: 'true', policy_version: policy.POLICY_VERSION }), { statusCode: 422 });
  assert.deepEqual(policy.consent({ enabled: false, policy_version: policy.POLICY_VERSION }), { enabled: false });
});
test('authenticated encryption prevents swapping mothers, sessions and message metadata', () => {
  const payload = crypto.encrypt('Private message', 'mother:session:turn:1');
  assert.equal(crypto.decrypt(payload, 'mother:session:turn:1'), 'Private message');
  assert.throws(() => crypto.decrypt(payload, 'another:session:turn:1'));
  assert.throws(() => crypto.decrypt(payload, 'mother:session:metadata:1'));
  assert.notEqual(crypto.encrypt('Private message', 'same'), crypto.encrypt('Private message', 'same'));
  assert.equal(crypto.fingerprint('hello'), crypto.fingerprint('hello'));
});
test('three-language independent safety never depends on an LLM', () => {
  for (const text of ['I want to kill myself', 'main khudkushi karna chahti hoon', 'میں خودکشی کرنا چاہتی ہوں']) {
    assert.equal(policy.inspectSafety(text).requires_help, true, text);
    assert.equal(policy.inspectSafety(text).alert_worthy, true, text);
  }
  for (const text of ['I do not want to harm myself', 'What is suicide?', 'I might hurt my baby',
    'Voices are telling me to hurt my baby', 'My abusive husband is violent and I want to kill myself',
    'My husband beats me and I want to kill myself', 'Mera shohar mujhe marta hai, main khudkushi karna chahti hoon',
    'I want to kill myself, I do not want my husband notified', 'I am hearing voices and have not slept for days',
    'main khudkushi karna chahti hoon, mere shohar ko mat batana']) {
    assert.equal(policy.inspectSafety(text).requires_help, true, text);
    assert.equal(policy.inspectSafety(text).alert_worthy, false, text);
  }
  assert.equal(policy.inspectSafety('I need help with sleep').requires_help, false);
  for (const text of ['I will overdose', 'I took too many pills', 'میں نے بہت زیادہ گولیاں کھا لی ہیں', 'main ne bohat ziada goliyan kha li hain']) {
    assert.equal(policy.inspectSafety(text).requires_help, true, text);
  }
  for (const language of policy.LANGUAGES) {
    assert.equal(policy.fallback(language, { requires_help: true, reason: 'urgent' }).mode, 'safety');
    assert.equal(policy.fallback(language).mode, 'unavailable');
  }
});
test('opaque pagination is bounded and handles ordinal turn order', () => {
  const cursor = policy.cursor({ created_at: new Date(), id: randomUUID(), ordinal: '42' });
  assert.equal(policy.pagination({ before: cursor }).before.ordinal, '42');
  assert.throws(() => policy.pagination({ limit: '31' }), { statusCode: 422 });
  assert.throws(() => policy.pagination({ before: 'bad' }), { statusCode: 422 });
  assert.throws(() => policy.pagination({ other: 'x' }), { statusCode: 422 });
  for (const malformed of [{ created_at: 'January 1', id: randomUUID() },
    { created_at: new Date().toISOString(), id: '-'.repeat(36) },
    { created_at: new Date().toISOString(), id: randomUUID(), ordinal: '9999999999999999999' }]) {
    assert.throws(() => policy.pagination({ before: Buffer.from(JSON.stringify(malformed)).toString('base64url') }), { statusCode: 422 });
  }
});
test('only trusted private inference endpoints and bounded, nonclinical answers are accepted', async () => {
  assert.equal(client.privateHost('127.0.0.1'), true);
  assert.equal(client.privateHost('192.168.1.5'), true);
  assert.equal(client.privateHost('api.third-party-ai.example'), false);
  const previousUrl = process.env.ML_SERVICE_URL;
  try {
    process.env.ML_SERVICE_URL = 'http://192.168.1.5:8001';
    assert.throws(() => client.baseUrl(), /requires HTTPS/);
    process.env.ML_SERVICE_URL = 'https://192.168.1.5:8001';
    assert.equal(client.baseUrl(), 'https://192.168.1.5:8001');
  } finally { if (previousUrl === undefined) delete process.env.ML_SERVICE_URL; else process.env.ML_SERVICE_URL = previousUrl; }
  const valid = { reply: 'A supportive reply.', language: 'en', mode: 'retrieval_only', sources: [], actions: ['mood'],
    safety: { requires_help: false, guardian_alert_allowed: true, reason: null }, state: {}, model_version: 'test', clinical_validation: false };
  assert.equal(client.validateReply(valid, 'en').safety.guardian_alert_allowed, false);
  assert.throws(() => client.validateReply({ ...valid, clinical_validation: true }, 'en'));
  assert.throws(() => client.validateReply({ ...valid, actions: ['delete_account'] }, 'en'));
  assert.throws(() => client.validateReply({ ...valid, sources: [{ id: 'x', title: 'bad', url: 'javascript:alert(1)' }] }, 'en'));
  const originalFetch = global.fetch;
  global.fetch = async () => { throw new Error('network offline'); };
  try { assert.equal((await client.reply({ message: 'hello', language: 'ur', history: [], context: {}, state: {} })).mode, 'unavailable'); }
  finally { global.fetch = originalFetch; }
});
test('mood slope uses elapsed dates, not number of logged entries', () => {
  assert.equal(slope([{ entry_date: '2026-10-01', mood_rating: 1 }, { entry_date: '2026-10-11', mood_rating: 5 }]), 0.4);
  assert.equal(slope([{ entry_date: '2026-10-01', mood_rating: 3 }]), null);
});
test('real aggregate builder matches the shared Python contract fixture and never selects raw bodies', async () => {
  const sources = [
    [{ entry_date: '2026-10-07', mood_rating: 2 }, { entry_date: '2026-10-08', mood_rating: 4 }],
    [{ instrument_type: 'epds', instrument_version: 'epds-v1', language: 'en', total_score: 12,
      completed_at: new Date('2026-09-28T12:00:00Z'), self_harm_positive: false },
    { instrument_type: 'phq9', instrument_version: 'phq9-v1', language: 'ur', total_score: 10,
      completed_at: new Date('2026-10-02T12:00:00Z'), self_harm_positive: false }],
    [{ depression_probability: '0.65', risk_level: 'moderate', generated_at: new Date('2026-10-05T12:00:00Z'),
      model_version: 'synthetic-peri-dep-v1', model_scope: 'cross_sectional_baseline', input_summary: {} }],
    [{ record_count: 4, mean_score: '-0.25', rule_safety_count: 1, latest_at: new Date('2026-10-08T08:00:00Z') }],
  ];
  const fake = { query: async (sql) => {
    assert.equal(sql.includes('content_encrypted'), false);
    assert.equal(sql.includes('voice_object_key'), false);
    return { rows: sources.shift() };
  } };
  const context = await aggregate(fake, 'synthetic-owner-never-transmitted', true, new Date('2026-10-08T12:00:00Z'));
  assert.deepEqual(context, require('./chatbot_context.fixture.json'));
  assert.equal(JSON.stringify(context).includes('synthetic-owner-never-transmitted'), false);
  assert.equal(context.risk.stale, true);
  assert.equal(context.screenings[0].stale, true);
  assert.equal(context.screenings[1].stale, false);
});
