const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { rollbackConnection } = require('./helpers/rollback_connection');

test('privacy persists only the selected permission and checks current active mother (rollback)', {
  skip: process.env.RUN_PRIVACY_DB_TESTS !== '1',
}, async () => {
  const db = require('../src/config/database');
  const client = await db.pool.connect();
  const connect = db.pool.connect;
  try {
    await client.query('BEGIN');
    db.pool.connect = rollbackConnection(client);
    const service = require('../src/modules/onboarding/onboarding.service');
    const mother = randomUUID();
    const other = randomUUID();
    for (const [id, role] of [[mother, 'mother'], [other, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete)
        VALUES($1,$2,'synthetic-no-login',$3,TRUE)`, [id, `t${id.replaceAll('-', '').slice(0, 13)}`, role]);
    }
    await client.query(`INSERT INTO onboarding_data(user_id,age,city,consent_tier1,consent_tier2,consent_tier3)
      VALUES($1,27,'Synthetic',TRUE,TRUE,FALSE)`, [mother]);
    assert.deepEqual(await service.updateConsent(mother, { consent_tier2: false }),
      { consent_tier1: true, consent_tier2: false, consent_tier3: false });
    assert.deepEqual(await service.updateConsent(mother, { consent_tier3: true }),
      { consent_tier1: true, consent_tier2: false, consent_tier3: true });
    assert.equal((await service.getConsent(mother)).consent_tier2, false);
    assert.deepEqual((await client.query('SELECT age,city FROM onboarding_data WHERE user_id=$1', [mother])).rows[0],
      { age: 27, city: 'Synthetic' });
    await assert.rejects(service.getConsent(other), { statusCode: 403 });
    await assert.rejects(service.updateConsent(other, { consent_tier2: true }), { statusCode: 403 });
    await client.query('UPDATE users SET is_active=FALSE WHERE id=$1', [mother]);
    await assert.rejects(service.updateConsent(mother, { consent_tier2: true }), { statusCode: 403 });
    await assert.rejects(service.getConsent(mother), { statusCode: 403 });
  } finally {
    db.pool.connect = connect;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
  }
});
