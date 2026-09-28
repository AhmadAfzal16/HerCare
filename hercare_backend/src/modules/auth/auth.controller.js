const authService = require('./auth.service');

/**
 * POST /api/v1/auth/register
 */
const register = async (req, res, next) => {
  try {
    const { phone, password, role, language } = req.body;
    const result = await authService.register({ phone, password, role, language });

    res.status(201).json({
      success: true,
      message: 'Account created successfully.',
      data: result,
    });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/v1/auth/login
 */
const login = async (req, res, next) => {
  try {
    const { phone, password } = req.body;
    const result = await authService.login({ phone, password });

    res.json({
      success: true,
      message: 'Logged in successfully.',
      data: result,
    });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/v1/auth/refresh
 * Body: { refresh_token }
 */
const refresh = async (req, res, next) => {
  try {
    const { refresh_token: refreshToken } = req.body;
    const tokens = await authService.refresh(refreshToken);

    res.json({
      success: true,
      message: 'Tokens refreshed.',
      data: tokens,
    });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/v1/auth/logout
 * Requires: authenticate middleware
 */
const logout = async (req, res, next) => {
  try {
    await authService.logout(req.user.userId);
    res.json({ success: true, message: 'Logged out successfully.' });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/v1/auth/change-password
 * Requires: authenticate middleware
 */
const changePassword = async (req, res, next) => {
  try {
    const { current_password, new_password } = req.body;
    await authService.changePassword(req.user.userId, current_password, new_password);

    res.json({ success: true, message: 'Password updated successfully.' });
  } catch (err) {
    next(err);
  }
};

/**
 * GET /api/v1/auth/me
 * Returns the authenticated user's profile.
 */
const me = async (req, res, next) => {
  try {
    const { query } = require('../../config/database');
    const { rows } = await query(
      'SELECT id, phone, role, language, onboarding_complete, created_at FROM users WHERE id = $1',
      [req.user.userId],
    );
    if (!rows[0]) {
      return res.status(404).json({ success: false, message: 'User not found.' });
    }
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    next(err);
  }
};

module.exports = { register, login, refresh, logout, changePassword, me };
