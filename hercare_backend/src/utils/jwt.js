const jwt = require('jsonwebtoken');

const ACCESS_SECRET  = process.env.JWT_ACCESS_SECRET;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;

if (!ACCESS_SECRET || !REFRESH_SECRET) {
  throw new Error('JWT secrets must be set in environment variables');
}

const ACCESS_EXPIRY  = process.env.JWT_ACCESS_EXPIRY  || '15m';
const REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || '7d';

/**
 * Signs a short-lived access token.
 * Payload is intentionally minimal — no PHI stored in JWT.
 */
const signAccessToken = (payload) => {
  return jwt.sign(payload, ACCESS_SECRET, {
    expiresIn: ACCESS_EXPIRY,
    algorithm: 'HS256',
    issuer: 'hercare-api',
    audience: 'hercare-app',
  });
};

/**
 * Signs a longer-lived refresh token (stored securely on device).
 */
const signRefreshToken = (payload) => {
  return jwt.sign(payload, REFRESH_SECRET, {
    expiresIn: REFRESH_EXPIRY,
    algorithm: 'HS256',
    issuer: 'hercare-api',
    audience: 'hercare-app',
  });
};

/**
 * Verifies an access token.
 * @throws {JsonWebTokenError | TokenExpiredError}
 */
const verifyAccessToken = (token) => {
  return jwt.verify(token, ACCESS_SECRET, {
    algorithms: ['HS256'],
    issuer: 'hercare-api',
    audience: 'hercare-app',
  });
};

/**
 * Verifies a refresh token.
 */
const verifyRefreshToken = (token) => {
  return jwt.verify(token, REFRESH_SECRET, {
    algorithms: ['HS256'],
    issuer: 'hercare-api',
    audience: 'hercare-app',
  });
};

module.exports = {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
};
