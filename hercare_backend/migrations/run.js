require('dotenv').config();

const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const { pool } = require('../src/config/database');

async function run() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const files = (await fs.readdir(__dirname))
      .filter((name) => /^\d+_.+\.sql$/.test(name))
      .sort();

    for (const filename of files) {
      const sql = await fs.readFile(path.join(__dirname, filename), 'utf8');
      // Git may check out the same SQL with LF or CRLF on different deployment
      // hosts. Treat newline encoding as transport detail while still failing
      // when any SQL content was actually modified.
      const normalizedSql = sql.replace(/\r\n/g, '\n');
      const checksum = crypto.createHash('sha256').update(normalizedSql).digest('hex');
      const crlfChecksum = crypto.createHash('sha256')
        .update(normalizedSql.replace(/\n/g, '\r\n'))
        .digest('hex');
      const applied = await client.query(
        'SELECT checksum FROM schema_migrations WHERE filename = $1',
        [filename],
      );

      if (applied.rows[0]) {
        if (![checksum, crlfChecksum].includes(applied.rows[0].checksum)) {
          throw new Error(`Applied migration was modified: ${filename}`);
        }
        continue;
      }

      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query(
          'INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)',
          [filename, checksum],
        );
        await client.query('COMMIT');
        process.stdout.write(`Applied ${filename}\n`);
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      }
    }
  } finally {
    client.release();
    await pool.end();
  }
}

run().catch((error) => {
  console.error('Migration failed:', error);
  process.exitCode = 1;
});
