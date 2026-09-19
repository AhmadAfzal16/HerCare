const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { query, withTransaction } = require('../../config/database');
const {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} = require('../../utils/jwt');
const { AppError } = require('../../middleware/error_handler');
const logger = require('../../utils/logger');

const BCRYPT_ROUNDS = 12; // Recommended: 10–14

/**
 * Register a new user (mother or guardian).
 *
 * @param {object} data - { phone, password, role, language }
 * @returns {{ user, accessToken, refreshToken }}
 */
const register = async ({ phone, password, role = 'mother', language = 'en' }) => {
  return withTransaction(async (client) => {
    // 1. Check phone uniqueness
    const existing = await client.query(
      'SELECT id FROM users WHERE phone = $1',
      [phone],
    );
    if (existing.rows.length > 0) {
      throw new AppError('An account with this phone number already exists.', 409);
    }

    // 2. Hash password (bcrypt with high cost factor)
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    // 3. Insert user
    const userId = uuidv4();
    const { rows } = await client.query(
      `INSERT INTO users (id, phone, password_hash, role, language, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
       RETURNING id, phone, role, language, created_at`,
      [userId, phone, passwordHash, role, language],
    );
    const user = rows[0];

    // 4. Issue tokens
    const tokenPayload = { userId: user.id, role: user.role };
    const accessToken  = signAccessToken(tokenPayload);
    const refreshToken = signRefreshToken(tokenPayload);

    // 5. Store refresh token hash (one active refresh token per user)
    const refreshHash = await bcrypt.hash(refreshToken, 10);
    await client.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '7 days')`,
      [user.id, refreshHash],
    );

    logger.info(`New user registered: ${user.id} [${role}]`);

    return {
      user: {
        id:        user.id,
        phone:     user.phone,
        role:      user.role,
        language:  user.language,
        createdAt: user.created_at,
      },
      accessToken,
      refreshToken,
    };
  });
};

/**
 * Authenticate an existing user.
 *
 * @param {object} data - { phone, password }
 * @returns {{ user, accessToken, refreshToken }}
 */
const login = async ({ phone, password }) => {
  // 1. Fetch user by phone
  const { rows } = await query(
    'SELECT id, phone, password_hash, role, language, is_active FROM users WHERE phone = $1',
    [phone],
  );

  // Constant-time response even if user not found (prevent enumeration)
  const user = rows[0];
  const dummyHash = '$2a$12$invalidHashForTimingConsistency000000000000000000000';

  const isMatch = await bcrypt.compare(
    password,
    user ? user.password_hash : dummyHash,
  );

  if (!user || !isMatch) {
    throw new AppError('Incorrect phone number or password.', 401);
  }

  if (!user.is_active) {
    throw new AppError('Your account has been suspended. Please contact support.', 403);
  }

  // 2. Invalidate old refresh tokens for this user
  await query(
    'DELETE FROM refresh_tokens WHERE user_id = $1',
    [user.id],
  );

  // 3. Issue new tokens
  const tokenPayload = { userId: user.id, role: user.role };
  const accessToken  = signAccessToken(tokenPayload);
  const refreshToken = signRefreshToken(tokenPayload);

  // 4. Store new refresh token hash
  const refreshHash = await bcrypt.hash(refreshToken, 10);
  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '7 days')`,
    [user.id, refreshHash],
  );

  logger.info(`User logged in: ${user.id}`);

  return {
    user: {
      id:       user.id,
      phone:    user.phone,
      role:     user.role,
      language: user.language,
    },
    accessToken,
    refreshToken,
  };
};

/**
 * Refresh access token using a valid refresh token.
 */
const refresh = async (refreshToken) => {
  let decoded;
  try {
    decoded = verifyRefreshToken(refreshToken);
  } catch {
    throw new AppError('Invalid or expired refresh token.', 401);
  }

  // Verify token is in DB
  const { rows } = await query(
    `SELECT rt.token_hash, u.id, u.role, u.is_active
     FROM refresh_tokens rt
     JOIN users u ON u.id = rt.user_id
     WHERE rt.user_id = $1 AND rt.expires_at > NOW()`,
    [decoded.userId],
  );

  if (rows.length === 0) {
    throw new AppError('Session not found. Please log in again.', 401);
  }

  const row = rows[0];

  if (!row.is_active) {
    throw new AppError('Account suspended.', 403);
  }

  const tokenMatch = await bcrypt.compare(refreshToken, row.token_hash);
  if (!tokenMatch) {
    // Possible token theft — invalidate all sessions for this user
    await query('DELETE FROM refresh_tokens WHERE user_id = $1', [decoded.userId]);
    logger.warn(`Refresh token mismatch (possible theft) for user: ${decoded.userId}`);
    throw new AppError('Invalid refresh token. All sessions invalidated.', 401);
  }

  // Issue new pair (token rotation)
  const newAccessToken  = signAccessToken({ userId: row.id, role: row.role });
  const newRefreshToken = signRefreshToken({ userId: row.id, role: row.role });
  const newHash = await bcrypt.hash(newRefreshToken, 10);

  await query(
    `UPDATE refresh_tokens SET token_hash = $1, expires_at = NOW() + INTERVAL '7 days'
     WHERE user_id = $2`,
    [newHash, row.id],
  );

  return { accessToken: newAccessToken, refreshToken: newRefreshToken };
};

/**
 * Logout — invalidates the user's refresh tokens.
 */
const logout = async (userId) => {
  await query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
  logger.info(`User logged out: ${userId}`);
};

/**
 * Change password for an authenticated user.
 */
const changePassword = async (userId, currentPassword, newPassword) => {
  const { rows } = await query(
    'SELECT password_hash FROM users WHERE id = $1',
    [userId],
  );
  if (!rows[0]) throw new AppError('User not found.', 404);

  const isMatch = await bcrypt.compare(currentPassword, rows[0].password_hash);
  if (!isMatch) throw new AppError('Current password is incorrect.', 401);

  const newHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  await query(
    'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
    [newHash, userId],
  );

  // Invalidate all refresh tokens after password change
  await query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
  logger.info(`Password changed for user: ${userId}`);
};

module.exports = { register, login, refresh, logout, changePassword };
