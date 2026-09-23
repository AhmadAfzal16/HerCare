const { body, validationResult } = require('express-validator');

// ─── Reusable validation chains ───────────────────────────────────────────────

const phoneValidation = body('phone')
  .trim()
  .notEmpty().withMessage('Phone number is required')
  .matches(/^\+92[0-9]{10}$/).withMessage('Phone must be a valid Pakistani number (+92XXXXXXXXXX)');

const passwordValidation = body('password')
  .isLength({ min: 8, max: 128 }).withMessage('Password must be 8–128 characters')
  .matches(/[A-Z]/).withMessage('Password must contain at least one uppercase letter')
  .matches(/[0-9]/).withMessage('Password must contain at least one number')
  .matches(/[^A-Za-z0-9]/).withMessage('Password must contain at least one special character');

const roleValidation = body('role')
  .notEmpty().withMessage('Account type is required')
  .isIn(['mother', 'guardian']).withMessage('Role must be mother or guardian');

// ─── Validation rule sets ─────────────────────────────────────────────────────

const registerValidation = [
  phoneValidation,
  passwordValidation,
  body('confirm_password')
    .custom((value, { req }) => {
      if (value !== req.body.password) {
        throw new Error('Passwords do not match');
      }
      return true;
    }),
  roleValidation,
];

const loginValidation = [
  phoneValidation,
  body('password')
    .notEmpty().withMessage('Password is required'),
];

const refreshValidation = [
  body('refresh_token')
    .notEmpty().withMessage('Refresh token is required'),
];

const changePasswordValidation = [
  body('current_password').notEmpty().withMessage('Current password is required'),
  body('new_password')
    .isLength({ min: 8, max: 128 }).withMessage('New password must be 8–128 characters')
    .matches(/[A-Z]/).withMessage('Must contain an uppercase letter')
    .matches(/[0-9]/).withMessage('Must contain a number')
    .matches(/[^A-Za-z0-9]/).withMessage('Must contain a special character'),
];

// ─── Middleware: validate and respond ─────────────────────────────────────────

/**
 * Reads express-validator errors and returns 422 with field details.
 * Usage: place after a validation chain array in the route.
 */
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array().map(e => ({
        field: e.path,
        message: e.msg,
      })),
    });
  }
  next();
};

module.exports = {
  registerValidation,
  loginValidation,
  refreshValidation,
  changePasswordValidation,
  validate,
};
