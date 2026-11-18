const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const policy = require('../src/modules/crisis/crisis.policy');
const crypto = require('../src/modules/crisis/crisis.crypto');

test('M10 minimal safety-plan fields are optional, bounded and allowlisted', () => {
  assert.deepEqual(policy.plan({ version: 0 }), { version: 0, coping_step: '', support_person_name: '', support_phone: '' });
  assert.equal(policy.plan({ version: 1, support_phone: '+92 (300) 123-4567' }).support_phone, '+923001234567');
  for (const body of [{ version: 0, journal: 'private' }, { version: 0, coping_step: 'a'.repeat(501) },
    { version: 0, support_phone: 'https://unsafe.test' }, { version: 0, support_person_name: '\0name' }, { version: '0' }]) {
    assert.throws(() => policy.plan(body), { statusCode: 422 });
  }
});
test('M10 plan encryption binds ownership and authenticates ciphertext without plaintext PII', () => {
  const mother = randomUUID();
  const plan = { coping_step: 'My private coping step', support_person_name: 'Private friend', support_phone: '+923001234567' };
  const one = crypto.encrypt(plan, mother);
  assert.deepEqual(crypto.decrypt(one, mother), plan);
  assert.notEqual(one, crypto.encrypt(plan, mother));
  assert.equal(one.includes('Private'), false);
  assert.equal(one.includes('92300'), false);
  assert.throws(() => crypto.decrypt(one, randomUUID()));
  const parts = one.split('.');
  parts[2] = Buffer.alloc(16).toString('base64url');
  assert.throws(() => crypto.decrypt(parts.join('.'), mother));
});
test('M10 production requires a stable encryption key', () => {
  const previous = { NODE_ENV: process.env.NODE_ENV, CRISIS_ENCRYPTION_KEY: process.env.CRISIS_ENCRYPTION_KEY, JOURNAL_ENCRYPTION_KEY: process.env.JOURNAL_ENCRYPTION_KEY };
  try {
    process.env.NODE_ENV = 'production';
    delete process.env.CRISIS_ENCRYPTION_KEY;
    delete process.env.JOURNAL_ENCRYPTION_KEY;
    assert.throws(() => crypto.encrypt({}, randomUUID()), /required/);
    process.env.CRISIS_ENCRYPTION_KEY = 'invalid';
    assert.throws(() => crypto.encrypt({}, randomUUID()), /32 bytes/);
  } finally {
    for (const [key, value] of Object.entries(previous)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
test('M10 guardian alerts require an explicit action and exact link identifier', () => {
  const uuid = randomUUID();
  assert.equal(policy.request({ client_request_id: uuid, notify_guardian: false }).guardian_link_id, null);
  assert.equal(policy.request({ client_request_id: uuid, notify_guardian: true, guardian_link_id: uuid }).notify_guardian, true);
  for (const body of [{ client_request_id: uuid }, { client_request_id: uuid, notify_guardian: true },
    { client_request_id: uuid, notify_guardian: false, guardian_link_id: uuid }, { client_request_id: uuid, notify_guardian: 'true' }]) {
    assert.throws(() => policy.request(body), { statusCode: 422 });
  }
  assert.throws(() => policy.guardian({ guardian_link_id: uuid, confirmed: 'true' }), { statusCode: 422 });
});
test('M10 acknowledgement is not closure; closure requires a nonclinical outcome', () => {
  assert.deepEqual(policy.transition({ status: 'acknowledged' }), { status: 'acknowledged', outcome: null });
  for (const outcome of policy.OUTCOMES) assert.equal(policy.transition({ status: 'resolved', outcome }).outcome, outcome);
  for (const body of [{ status: 'resolved' }, { status: 'resolved', outcome: 'cured' }, { status: 'open' },
    { status: 'acknowledged', outcome: 'support_contacted' }, { status: 'resolved', outcome: 'other', notes: 'private' }]) {
    assert.throws(() => policy.transition(body), { statusCode: 422 });
  }
});
test('M10 history cursors retain timestamp ties and reject unbounded requests', () => {
  const row = { id: randomUUID(), triggered_at: '2026-10-11T09:00:00.000Z' };
  assert.deepEqual(policy.page({ limit: '1', before: policy.cursor(row) }), { limit: 1, before: { id: row.id, at: row.triggered_at } });
  for (const options of [{ limit: '51' }, { before: '!!!' }, { before: Buffer.from('{}').toString('base64url') }, { user_id: randomUUID() }]) {
    assert.throws(() => policy.page(options), { statusCode: 422 });
  }
});
