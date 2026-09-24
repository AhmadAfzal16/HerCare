const { body, query, validationResult } = require('express-validator');

const messageValidation = [
  body('content')
    .isString().trim().isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters.'),
  body('client_request_id').isUUID().withMessage('A valid request ID is required.'),
];

const historyValidation = [
  query('before').optional().isISO8601().withMessage('before must be an ISO date.'),
  query('after').optional().isISO8601().withMessage('after must be an ISO date.'),
  query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
];

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array().map((error) => ({ field: error.path, message: error.msg })),
    });
  }
  return next();
}

module.exports = { messageValidation, historyValidation, validate };

