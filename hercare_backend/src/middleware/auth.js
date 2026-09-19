const { verifyAccessToken } = require('../utils/jwt');
const logger = require('../utils/logger');

/**
 * Authentication middleware.
 * Validates the Bearer token from the Authorization header.
 * Attaches the decoded payload to req.user.
 */
const authenticate = (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      message: 'Authentication required. Please log in.',
    });
  }

  const token = authHeader.slice(7); // Remove 'Bearer '

  try {
    const decoded = verifyAccessToken(token);
    req.user = decoded; // { userId, role, iat, exp }
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({
        success: false,
        code: 'TOKEN_EXPIRED',
        message: 'Session expired. Please refresh your token.',
      });
    }
    logger.warn(`Invalid token attempt: ${err.message}`);
    return res.status(401).json({
      success: false,
      message: 'Invalid authentication token.',
    });
  }
};

/**
 * Role-based authorization middleware.
 * Usage: authorize('admin') or authorize('user', 'guardian')
 */
const authorize = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return res.status(403).json({
      success: false,
      message: 'You do not have permission to access this resource.',
    });
  }
  next();
};

module.exports = { authenticate, authorize };
