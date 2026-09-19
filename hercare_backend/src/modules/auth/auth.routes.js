const express = require('express');
const rateLimit = require('express-rate-limit');

const controller = require('./auth.controller');
const {
  registerValidation,
  loginValidation,
  refreshValidation,
  changePasswordValidation,
  validate,
} = require('./auth.validator');
const { authenticate } = require('../../middleware/auth');

const router = express.Router();

// ─── Strict rate limiter for auth endpoints ────────────────────────────────
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10,                   // max 10 attempts per window
  message: {
    success: false,
    message: 'Too many attempts. Please try again in 15 minutes.',
  },
  standardHeaders: true,
  legacyHeaders: false,
  // Skip rate limit for successful requests (only count failures)
  skipSuccessfulRequests: true,
});

// ─── Public Routes ─────────────────────────────────────────────────────────

/**
 * @route  POST /api/v1/auth/register
 * @desc   Create a new mother or guardian account
 * @access Public
 */
router.post('/register',
  authLimiter,
  registerValidation,
  validate,
  controller.register,
);

/**
 * @route  POST /api/v1/auth/login
 * @desc   Authenticate and receive token pair
 * @access Public
 */
router.post('/login',
  authLimiter,
  loginValidation,
  validate,
  controller.login,
);

/**
 * @route  POST /api/v1/auth/refresh
 * @desc   Exchange a refresh token for a new access+refresh pair
 * @access Public (token validated in service)
 */
router.post('/refresh',
  refreshValidation,
  validate,
  controller.refresh,
);

// ─── Protected Routes (require valid access token) ────────────────────────

/**
 * @route  POST /api/v1/auth/logout
 * @desc   Invalidate refresh tokens (server-side logout)
 * @access Protected
 */
router.post('/logout',
  authenticate,
  controller.logout,
);

/**
 * @route  GET /api/v1/auth/me
 * @desc   Get current user's profile
 * @access Protected
 */
router.get('/me',
  authenticate,
  controller.me,
);

/**
 * @route  POST /api/v1/auth/change-password
 * @desc   Change password for authenticated user
 * @access Protected
 */
router.post('/change-password',
  authenticate,
  changePasswordValidation,
  validate,
  controller.changePassword,
);

module.exports = router;
