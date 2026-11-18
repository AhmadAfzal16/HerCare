const test = require('node:test');
const assert = require('node:assert/strict');

process.env.JWT_ACCESS_SECRET ||= 'synthetic-access-secret-for-unit-tests';
process.env.JWT_REFRESH_SECRET ||= 'synthetic-refresh-secret-for-unit-tests';

test('unknown phone performs a valid cost-12 password comparison and returns the same authentication error', async (t) => {
  const db = require('../src/config/database');
  const bcrypt = require('bcryptjs');
  const compare = bcrypt.compare;
  let comparedHash;
  t.mock.method(db, 'query', async () => ({ rows: [] }));
  t.mock.method(bcrypt, 'compare', async (password, hash) => {
    comparedHash = hash;
    return compare(password, hash);
  });
  const { login } = require('../src/modules/auth/auth.service');
  await assert.rejects(login({ phone: 'synthetic-no-account', password: 'synthetic-test' }),
    { statusCode: 401, message: 'Incorrect phone number or password.' });
  assert.equal(comparedHash.length, 60);
  assert.equal(bcrypt.getRounds(comparedHash), 12);
});
