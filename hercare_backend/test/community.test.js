const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const policy = require('../src/modules/community/community.policy');
const metadata = { model_version: 'reviewed-test-revision', policy_version: 'community-test-v2', runtime: 'onnx-cpu',
  clinical_validation: false, full_text_processed: true };
const scores = { self_harm: 0.8, bullying: 0, spam: 0, medical_advice: 0, support: 0.2 };
async function environment(values, run) {
  const saved = Object.fromEntries(Object.keys(values).map((key) => [key, process.env[key]]));
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }
  try { await run(); } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}

test('community validates text, UUIDs and opaque pagination', () => {
  assert.equal(policy.text('  he\u200bllo  ', 2, 20), 'hello');
  assert.throws(() => policy.text('x', 2, 20));
  assert.throws(() => policy.text('private\u0000entry', 2, 20), { statusCode: 422 });
  assert.throws(() => policy.uuid("' OR 1=1"));
  assert.throws(() => policy.onlyKeys({ role: 'admin' }, ['body']));
  const row = { cursor_time: '2026-09-26 12:00:00.123456+00', id: 'bf8b66ae-8708-4a01-a3bd-987478d239c4' };
  assert.deepEqual(policy.decodeCursor(policy.encodeCursor(row)), [row.cursor_time, row.id]);
  assert.throws(() => policy.decodeCursor('malformed'));
  assert.equal(policy.uuid(row.id.toUpperCase()), row.id);
  for (const timestamp of ['February 1, 2026', '2026-02-30 12:00:00+00', '2026-09-26T25:00:00Z', '2026-09-26T12:00:00+14:30']) {
    assert.throws(() => policy.decodeCursor(policy.encodeCursor({ ...row, cursor_time: timestamp })), { statusCode: 422 });
  }
  for (const value of ['', [], `${policy.encodeCursor(row)}=`, Buffer.from(JSON.stringify([row.cursor_time, row.id, 'extra'])).toString('base64url')]) {
    assert.throws(() => policy.decodeCursor(value), { statusCode: 422 });
  }
  assert.equal(policy.validTimestamp('2028-02-29T12:30:00+05:00'), true);
});

test('community only accepts bounded typed filters and exact normalized retry payloads', () => {
  assert.deepEqual(policy.pageOptions({ mine: 'true', include_replies: 'true' }), { mine: 'true', include_replies: 'true' });
  for (const options of [{ mine: true }, { mine: ['true'] }, { include_replies: 'true' }, { limit: '5000' }, { mine: 'true', include_replies: 'true', parent_id: randomUUID() }]) {
    assert.throws(() => policy.pageOptions(options), { statusCode: 422 });
  }
  const input = { title: 'Recovery today', body: 'I felt supported.', topic: 'recovery', client_request_id: randomUUID() };
  assert.equal(policy.submission(input).fingerprint, policy.submission({ ...input, body: `  ${input.body}  ` }).fingerprint);
  assert.equal(policy.submission(input).fingerprint, policy.submission({ ...input, client_request_id: randomUUID() }).fingerprint);
  assert.notEqual(policy.submission(input).fingerprint, policy.submission({ ...input, body: 'A changed submission.' }).fingerprint);
  assert.throws(() => policy.submission({ ...input, parent_id: null }), { statusCode: 422 });
  assert.throws(() => policy.submission({ ...input, topic: [] }), { statusCode: 422 });
});
test('community multilingual safety triage and privacy flags', () => {
  assert.equal(policy.rules('I want to hurt myself').safety_support, true);
  assert.equal(policy.rules('خود کو نقصان').safety_support, true);
  for (const statement of ['I am thinking of ending my life', 'I am THINKING OF ENDING MY LIFE',
    'میں اپنی زندگی ختم کرنے کا سوچ رہی ہوں', 'main apni zindagi khatam karne ka soch rahi hoon',
    'MAIN APNI ZINDAGI KHATAM KARNE KA SOCH RAHI HOON']) {
    assert.equal(policy.rules(statement).safety_support, true, statement);
  }
  const tail = `${'Some context. '.repeat(100)}میں اپنی زندگی ختم کرنے کا سوچ رہی ہوں`;
  assert.equal(policy.rules(tail).safety_support, true);
  assert.ok(policy.rules('contact person@example.com').flags.includes('privacy_or_link'));
  assert.ok(policy.rules('میرا نمبر ۰۳۰۰۱۲۳۴۵۶۷').flags.includes('privacy_or_link'));
  assert.ok(policy.rules('رابطہ ٠٣٠٠١٢٣٤٥٦٧').flags.includes('privacy_or_link'));
  assert.equal(policy.rules('I feel supported today').safety_support, false);
  assert.match(policy.alias(), /^Kind (Lotus|Willow|Daisy|Olive) [a-f0-9]{10}$/);
});
test('AI failures and invalid scores never masquerade as successful moderation', async () => {
  await environment({ COMMUNITY_MODERATION_URL: 'https://moderation.example/v1/community/moderate', ML_SERVICE_TOKEN: 'synthetic-only' }, async () => {
    assert.equal((await policy.moderate('hello', async () => { throw new Error('offline'); })).ai, 'unavailable');
    assert.equal((await policy.moderate('hello', async () => ({ ok: true, json: async () => ({ scores: {}, model_version: 'x' }) }))).ai, 'unavailable');
    for (const value of [{ ...metadata, full_text_processed: false, scores }, { ...metadata, clinical_validation: true, scores },
      { ...metadata, scores: { ...scores, spam: NaN } }, { ...metadata, scores: { ...scores, bullying: 1.1 } },
      { ...metadata, scores: { ...scores, support: '0.2' } }]) {
      assert.equal((await policy.moderate('hello', async () => ({ ok: true, json: async () => value }))).ai, 'unavailable');
    }
    const result = await policy.moderate('hello', async (_url, options) => {
      assert.equal(options.headers.Authorization, 'Bearer synthetic-only');
      assert.equal(options.redirect, 'error');
      assert.deepEqual(JSON.parse(options.body), { text: 'hello' });
      return { ok: true, json: async () => ({ ...metadata, scores }) };
    });
    assert.equal(result.safety_support, true);
    assert.equal(result.ai, 'available');
    assert.equal(result.model_version, metadata.model_version);
    assert.equal(result.full_text_processed, true);
  });
});

test('production AI requirements are fail-closed with explicit human-only degradation', async () => {
  await environment({ NODE_ENV: 'production', COMMUNITY_AI_REQUIRED: undefined, COMMUNITY_MODERATION_URL: undefined,
    ML_SERVICE_URL: undefined, ML_SERVICE_TOKEN: undefined }, async () => {
    assert.equal(policy.aiRequired(), true);
    assert.deepEqual(await policy.readiness(), { required: true, configured: false, ready: false, human_review_required: true, clinical_validation: false });
    process.env.COMMUNITY_AI_REQUIRED = 'false';
    assert.equal(policy.aiRequired(), false);
    process.env.COMMUNITY_AI_REQUIRED = 'invalid';
    assert.equal(policy.aiRequired(), true);
  });
});

test('readiness probes shared explicit ML URL without exposing endpoints or tokens', async () => {
  await environment({ NODE_ENV: 'production', COMMUNITY_MODERATION_URL: undefined, ML_SERVICE_URL: 'https://private.example',
    ML_SERVICE_TOKEN: 'private-test-token' }, async () => {
    const result = await policy.readiness(async (url, options) => {
      assert.equal(url.href, 'https://private.example/v1/community/ready');
      assert.equal(options.method, 'GET');
      return { ok: true, json: async () => ({ status: 'ready', ...metadata, unwanted_secret: 'must-not-leak' }) };
    });
    assert.equal(result.ready, true);
    assert.equal(JSON.stringify(result).includes('private.example'), false);
    assert.equal(JSON.stringify(result).includes('private-test-token'), false);
    assert.equal(result.unwanted_secret, undefined);
  });
});

test('invalid transport, missing token and incomplete readiness never call or trust AI', async () => {
  await environment({ NODE_ENV: 'production', ML_SERVICE_URL: undefined, COMMUNITY_MODERATION_URL: 'http://private.example/v1/community/moderate',
    ML_SERVICE_TOKEN: 'test-only' }, async () => {
    const forbidden = async () => { assert.fail('Unsafe or unauthenticated endpoint must not be contacted'); };
    assert.equal((await policy.moderate('hello', forbidden)).ai, 'unavailable');
    process.env.COMMUNITY_MODERATION_URL = 'https://user:password@private.example/v1/community/moderate';
    assert.equal((await policy.readiness(forbidden)).ready, false);
    process.env.COMMUNITY_MODERATION_URL = 'https://private.example/v1/community/moderate';
    delete process.env.ML_SERVICE_TOKEN;
    assert.equal((await policy.moderate('hello', forbidden)).ai, 'unavailable');
    process.env.ML_SERVICE_TOKEN = 'test-only';
    assert.equal((await policy.readiness(async () => ({ ok: true, json: async () => ({ status: 'ready' }) }))).ready, false);
  });
});
