// Give connection-owning code a lease inside an existing fixture transaction.
// COMMIT/ROLLBACK operate on savepoints: synthetic rows can never be committed.
function rollbackConnection(client) {
  let serial = 0;
  let leased = false;
  return async () => {
    if (leased) throw new Error('Rollback fixture leases must be sequential.');
    leased = true;
    const savepoint = `m7_fixture_${++serial}`;
    let inTransaction = false;
    return {
      async query(text, values) {
        const command = typeof text === 'string' ? text.trim().toUpperCase() : '';
        if (/^BEGIN(?:\s|$)/.test(command)) {
          if (inTransaction) throw new Error('Nested fixture transaction.');
          const result = await client.query(`SAVEPOINT ${savepoint}`);
          inTransaction = true;
          return result;
        }
        if (command === 'COMMIT') {
          if (!inTransaction) throw new Error('Unexpected fixture commit.');
          const result = await client.query(`RELEASE SAVEPOINT ${savepoint}`);
          inTransaction = false;
          return result;
        }
        if (command === 'ROLLBACK') {
          if (!inTransaction) return { rows: [], rowCount: 0 };
          await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
          const result = await client.query(`RELEASE SAVEPOINT ${savepoint}`);
          inTransaction = false;
          return result;
        }
        return client.query(text, values);
      },
      release(error) {
        leased = false;
        if (inTransaction || error) {
          throw new Error('Fixture lease cleanup failed; outer transaction must roll back.');
        }
      },
    };
  };
}

module.exports = { rollbackConnection };
