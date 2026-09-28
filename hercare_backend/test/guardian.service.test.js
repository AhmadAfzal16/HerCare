const test = require('node:test');
const assert = require('node:assert/strict');

const {
  getGuardianRecommendations,
  _private: { generateSecureCode, epdsToRisk, getCanonicalPeriod },
} = require('../src/modules/guardian/guardian.service');
const { validateAcceptInvite } = require('../src/modules/guardian/guardian.validator');

function runValidation(middleware, body) {
  let statusCode;
  let payload;
  let passed = false;
  const req = { body };
  const res = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(value) {
      payload = value;
      return this;
    },
  };
  middleware(req, res, () => { passed = true; });
  return { passed, statusCode, payload, value: req.body };
}

test('invite codes have 12 unambiguous characters and useful entropy', () => {
  const codes = new Set();
  for (let index = 0; index < 1000; index += 1) {
    const code = generateSecureCode();
    assert.match(code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$/);
    codes.add(code);
  }
  assert.equal(codes.size, 1000);
});

test('EPDS risk mapping does not label missing data as low risk', () => {
  assert.equal(epdsToRisk(null), null);
  assert.equal(epdsToRisk(8), 'low');
  assert.equal(epdsToRisk(9), 'moderate');
  assert.equal(epdsToRisk(13), 'high');
  assert.equal(epdsToRisk(19), 'severe');
});

test('canonical weekly period is Monday through Sunday', () => {
  assert.deepEqual(getCanonicalPeriod('weekly', '2026-09-22'), {
    periodStart: '2026-09-21',
    periodEnd: '2026-09-27',
  });
});

test('canonical monthly period handles month length', () => {
  assert.deepEqual(getCanonicalPeriod('monthly', '2024-02-15'), {
    periodStart: '2024-02-01',
    periodEnd: '2024-02-29',
  });
});

test('unknown risk recommendations avoid false reassurance', () => {
  const recommendations = getGuardianRecommendations(null, 'en');
  assert.equal(recommendations.length, 3);
  assert.match(recommendations[1], /check-in/i);
});

test('invite validation rejects legacy short codes', () => {
  const result = runValidation(validateAcceptInvite, {
    invite_code: 'HERAB12C',
    guardian_name: 'Ahmed',
    relationship: 'husband',
  });
  assert.equal(result.passed, false);
  assert.equal(result.statusCode, 422);
});

test('invite validation normalizes valid codes', () => {
  const result = runValidation(validateAcceptInvite, {
    invite_code: 'abcdefgh2345',
    guardian_name: '  Ahmed  ',
    relationship: 'husband',
  });
  assert.equal(result.passed, true);
  assert.equal(result.value.invite_code, 'ABCDEFGH2345');
  assert.equal(result.value.guardian_name, 'Ahmed');
});
