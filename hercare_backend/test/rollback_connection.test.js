const test = require('node:test');
const assert = require('node:assert/strict');
const { rollbackConnection } = require('./helpers/rollback_connection');

test('M7 fixture leases cannot commit or roll back the outer synthetic transaction', async () => {
  const calls = [];
  const connect = rollbackConnection({ query: async (sql) => {
    calls.push(sql); return { rows: [], rowCount: 0 };
  } });
  const first = await connect();
  await first.query('BEGIN');
  await first.query('SELECT 1');
  await first.query('COMMIT');
  first.release();
  const second = await connect();
  await second.query('BEGIN');
  await second.query('ROLLBACK');
  second.release();
  assert.deepEqual(calls, [
    'SAVEPOINT m7_fixture_1', 'SELECT 1', 'RELEASE SAVEPOINT m7_fixture_1',
    'SAVEPOINT m7_fixture_2', 'ROLLBACK TO SAVEPOINT m7_fixture_2', 'RELEASE SAVEPOINT m7_fixture_2',
  ]);
});

test('M7 rollback fixtures reject overlapping leases and unexpected commits', async () => {
  const connect = rollbackConnection({ query: async () => ({ rows: [] }) });
  const first = await connect();
  await assert.rejects(connect(), /sequential/);
  await assert.rejects(first.query('COMMIT'), /Unexpected fixture commit/);
  first.release();
});

test('M7 fixture release requires successful transaction and lock cleanup', async () => {
  const connect = rollbackConnection({ query: async () => ({ rows: [] }) });
  const first = await connect();
  await first.query('BEGIN');
  assert.throws(() => first.release(), /cleanup failed/);
});
