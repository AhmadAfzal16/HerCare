const test = require('node:test');
const assert = require('node:assert/strict');

const {
  completeOnboardingValidation,
  validate,
} = require('../src/modules/onboarding/onboarding.validator');

const validPayload = Object.freeze({
  full_name: 'Ayesha Khan',
  age: 27,
  education_level: 'Graduate',
  city: 'Lahore',
  months_since_birth: 3,
  delivery_method: 'cesarean',
  parity: 1,
  baby_gender: 'female',
  has_preeclampsia: false,
  has_postpartum_hemorrhage: false,
  has_preterm_birth: false,
  has_gestational_diabetes: false,
  household_type: 'nuclear',
  income_range: '50000-100000',
  primary_support: 'husband',
  consent_tier1: true,
  consent_tier2: true,
  consent_tier3: false,
});

async function runValidation(body) {
  const req = { body: { ...body } };
  for (const rule of completeOnboardingValidation) {
    await rule.run(req);
  }

  let statusCode;
  let payload;
  let passed = false;
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
  validate(req, res, () => { passed = true; });
  return { passed, statusCode, payload, value: req.body };
}

test('valid mother onboarding payload is accepted', async () => {
  const result = await runValidation(validPayload);
  assert.equal(result.passed, true);
  assert.equal(result.value.consent_tier1, true);
});

test('required basic monitoring consent cannot be declined', async () => {
  const result = await runValidation({
    ...validPayload,
    consent_tier1: false,
  });
  assert.equal(result.passed, false);
  assert.equal(result.statusCode, 422);
  assert.equal(
    result.payload.errors.some((error) => error.field === 'consent_tier1'),
    true,
  );
});

test('unsupported support-source values are rejected', async () => {
  const result = await runValidation({
    ...validPayload,
    primary_support: 'friend',
  });
  assert.equal(result.passed, false);
  assert.equal(result.statusCode, 422);
});
