const test = require('node:test');
const assert = require('node:assert/strict');

test('alert retrieval checks current link, consent, and active mother', async () => {
  const database = require('../src/config/database');
  const path = require.resolve('../src/modules/guardian/guardian.service');
  const original = database.query;
  let captured;
  database.query = async (sql, params) => {
    captured = { sql, params };
    return { rows: [], rowCount: 0 };
  };
  delete require.cache[path];
  try {
    const service = require(path);
    assert.deepEqual(await service.getAlerts('guardian-id', 5), []);
    assert.match(captured.sql, /gl\.mother_id\s*=\s*ga\.mother_id/);
    assert.match(captured.sql, /gl\.guardian_id\s*=\s*ga\.guardian_id/);
    assert.match(captured.sql, /gl\.status\s*=\s*'active'/);
    assert.match(captured.sql, /od\.consent_tier2/);
    assert.match(captured.sql, /mother\.is_active/);
    assert.match(captured.sql, /plan\.guardian_contact_confirmed/);
    assert.match(captured.sql, /ga\.crisis_guardian_link_id\s*=\s*gl\.id/);
    assert.deepEqual(captured.params, ['guardian-id', 5]);
    assert.deepEqual(await service.markAlertsRead('guardian-id'), { updated: 0 });
    assert.match(captured.sql, /plan\.guardian_contact_confirmed/);
    assert.match(captured.sql, /ga\.crisis_guardian_link_id\s*=\s*gl\.id/);
  } finally {
    database.query = original;
    delete require.cache[path];
  }
});
