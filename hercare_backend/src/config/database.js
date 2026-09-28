const { Pool } = require('pg');
const logger = require('../utils/logger');

/**
 * PostgreSQL connection pool.
 * Uses environment variables — never hard-code credentials.
 *
 * Pool settings are tuned for a moderate load mobile backend.
 * Increase max connections for production deployments.
 */
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME     || 'hercare_db',
  user:     process.env.DB_USER     || 'hercare_user',
  password: process.env.DB_PASSWORD,

  // Pool config
  max:             10,   // max connections
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,

  // SSL for production (e.g., AWS RDS)
  ssl: process.env.DB_SSL === 'true'
    ? { rejectUnauthorized: true }
    : false,
});

// Log successful connection on first acquire
pool.on('connect', () => {
  logger.debug('PostgreSQL: new client connected');
});

pool.on('error', (err) => {
  logger.error('PostgreSQL pool error:', err.message);
});

/**
 * Execute a parameterized query.
 * Always use this instead of raw pool.query to ensure consistency.
 *
 * @param {string} text  - SQL with $1, $2 placeholders
 * @param {any[]}  params - Values array
 */
const query = async (text, params = []) => {
  const start = Date.now();
  const result = await pool.query(text, params);
  const duration = Date.now() - start;
  logger.debug(`SQL [${duration}ms]: ${text.slice(0, 80)}`);
  return result;
};

/**
 * Run a function within a transaction.
 * Automatically commits or rolls back.
 *
 * @param {(client: PoolClient) => Promise<T>} fn
 */
const withTransaction = async (fn) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

module.exports = { query, withTransaction, pool };
