const { body, param, query, validationResult } = require('express-validator');

const dateRule = (location, field) => location(field)
  .matches(/^\d{4}-\d{2}-\d{2}$/)
  .withMessage(`${field} must use YYYY-MM-DD format`)
  .bail()
  .isISO8601({ strict: true })
  .withMessage(`${field} must be a valid date`);

const checkinValidation = [
  dateRule(param, 'entryDate'),
  body('mood_rating').isInt({ min: 1, max: 5 }).toInt(),
  body('energy_level').isInt({ min: 1, max: 5 }).toInt(),
  body('sleep_quality').isInt({ min: 1, max: 5 }).toInt(),
  body('social_support').isInt({ min: 1, max: 5 }).toInt(),
  body('client_request_id').isUUID(),
];

const todayValidation = [dateRule(query, 'date')];

const historyValidation = [
  query('from').optional().matches(/^\d{4}-\d{2}-\d{2}$/).isISO8601({ strict: true }),
  query('to').optional().matches(/^\d{4}-\d{2}-\d{2}$/).isISO8601({ strict: true }),
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
];

const summaryValidation = [
  query('period').isIn(['daily', 'weekly', 'monthly']),
  dateRule(query, 'anchor_date'),
];

const journalValidation = [
  body('content')
    .isString()
    .trim()
    .isLength({ min: 1, max: 5000 })
    .withMessage('Journal content must be between 1 and 5000 characters.'),
  body('checkin_id').optional({ nullable: true }).isUUID(),
  body('client_request_id').isUUID(),
];

const journalListValidation = [
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
];

const journalSearchValidation = [
  body('query').isString().trim().isLength({ min: 2, max: 100 }),
  body('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
];

const journalIdValidation = [param('journalId').isUUID()];

const voiceInitializeValidation = [
  body('size_bytes').isInt({ min: 1, max: 4194304 }).toInt(),
  body('language').isIn(['en', 'ur']),
  body('checkin_id').optional({ nullable: true }).isUUID(),
  body('client_request_id').isUUID(),
];

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(422).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array().map((error) => ({
        field: error.path,
        message: error.msg,
      })),
    });
  }
  return next();
}

module.exports = {
  checkinValidation,
  todayValidation,
  historyValidation,
  summaryValidation,
  journalValidation,
  journalListValidation,
  journalSearchValidation,
  journalIdValidation,
  voiceInitializeValidation,
  validate,
};
