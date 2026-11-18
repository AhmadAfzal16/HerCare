const test = require('node:test');
const assert = require('node:assert/strict');
const { accountScope } = require('../src/middleware/account_scope');
const { updateConsent } = require('../src/modules/onboarding/onboarding.service');

test('private requests reject account changes and disable HTTP caching', () => {
  for (const header of ['X-Guardian-Account-Id', 'X-Screening-Account-Id', 'X-Privacy-Account-Id']) {
    const values = {};
    const res = { set: (k, v) => { values[k] = v; }, vary: () => {} };
    const guard = accountScope(header, { required: true });
    for (const expected of [undefined, 'mother-b']) {
      let error;
      guard({ get: () => expected, user: { userId: 'mother-a' } }, res, (value) => { error = value; });
      assert.equal(error.statusCode, 409);
    }
    let error;
    guard({ get: () => 'MOTHER-A', user: { userId: 'mother-a' } }, res, (value) => { error = value; });
    assert.equal(error, undefined);
    assert.equal(values['Cache-Control'], 'private, no-store');
  }
});

test('privacy mutation rejects unrelated profile, required consent and research fields before SQL', async () => {
  for (const body of [null, {}, { consent_tier2: 'false' }, { consent_tier1: false },
    { consent_tier2: false, age: 31 }, { research_consent: true },
    { consent_tier2: true, consent_tier3: true }, { 'consent_tier2=TRUE;--': true }]) {
    await assert.rejects(updateConsent('synthetic', body), { statusCode: 422 });
  }
});
