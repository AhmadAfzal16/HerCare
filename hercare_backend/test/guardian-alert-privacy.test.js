const test = require('node:test');
const assert = require('node:assert/strict');

test('alert retrieval checks current link, consent, and active mother', async () => {
  const database = require('../src/config/database');
  const path = require.resolve('../src/modules/guardian/guardian.service');
  const original = database.query;
  let captured;
  database.query = async (sql, params) => {
    captured = { sql, params };
    return { rows: [] };
  };
  delete require.cache[path];
  try {
    const service = require(path);
    assert.deepEqual(await service.getAlerts('guardian-id', 5), []);
    assert.match(captured.sql, /gl\.mother_id = ga\.mother_id/);
    assert.match(captured.sql, /gl\.guardian_id = ga\.guardian_id/);
    assert.match(captured.sql, /gl\.status = 'active'/);
    assert.match(captured.sql, /od\.consent_tier2 = TRUE/);
    assert.match(captured.sql, /u\.is_active = TRUE/);
    assert.deepEqual(captured.params, ['guardian-id', 5]);
  } finally {
    database.query = original;
    delete require.cache[path];
  }
});
