const test = require('node:test');
const assert = require('node:assert/strict');
const context = require('../src/modules/risk/risk.context');
const research = require('../src/modules/research/research.service');
const analysis = require('../src/modules/mood/text_analysis.service');

test('exact optional context distinguishes unknown and confirmed absence', () => {
  assert.deepEqual(context.validateContext({}), { number_of_children: null, basic_needs_affordable: null, mother_in_law_relationship: null });
  assert.equal(context.validateContext({ number_of_children: 0 }).number_of_children, 0);
  assert.throws(() => context.validateContext({ number_of_children: '2' }));
  assert.throws(() => context.validateContext({ financial_strain: 0 }));
  assert.throws(() => context.validateContext({ basic_needs_affordable: 'yes' }));
});
test('research consent is independent and versioned; export ranges are bounded', () => {
  assert.throws(() => research.validateConsent({ enabled: true, policy_version: 'other' }));
  assert.equal(research.validateConsent({ enabled: false, policy_version: research.POLICY_VERSION }).enabled, false);
  assert.throws(() => research.exportOptions({ from: '2026-02-30', to: '2026-03-01', purpose: 'external_validation' }));
  assert.throws(() => research.exportOptions({ from: '2025-01-01', to: '2026-01-01', purpose: 'external_validation' }));
  assert.notEqual(research.pseudonym('x'.repeat(32), 'participant', 'original-id'), 'original-id');
});
test('optional sentiment never overrides crisis rules and falls back without losing saves', async () => {
  const originalFetch = global.fetch;
  let calls = 0;
  try {
    global.fetch = async () => { calls += 1; return { ok: true, json: async () => ({ label: 'positive', score: .9,
      status: 'estimated', language: 'en', model_version: 'fixture' }) }; };
    const danger = await analysis.analyzeText('I want to hurt myself');
    assert.equal(danger.containsDanger, true);
    assert.equal(calls, 0);
    const calm = await analysis.analyzeText('I feel calm today');
    assert.equal(calm.sentimentLabel, 'positive');
    assert.equal(calm.metadata.clinical_validation, false);
    assert.equal(calm.metadata.distress_source, 'rules');
    global.fetch = async () => { throw new Error('offline'); };
    const fallback = await analysis.analyzeText('I feel sad');
    assert.equal(fallback.sentimentLabel, 'negative');
    assert.equal(fallback.metadata.model_status, 'unavailable');
  } finally { global.fetch = originalFetch; analysis._reset(); }
});
