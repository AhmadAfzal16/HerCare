const { body, query, validationResult } = require('express-validator');
const { isKnownActivity } = require('./therapy.catalog');

const sessionValidation = [
  body('activity_type').isIn(['breathing', 'meditation', 'cbt', 'game']),
  body('activity_id').isString().isLength({ min: 2, max: 40 })
    .custom((value, { req }) => isKnownActivity(req.body.activity_type, value))
    .withMessage('Unknown therapeutic activity.'),
  body('duration_seconds').isInt({ min: 1, max: 7200 }).toInt(),
  body('mood_before').optional({ nullable: true }).isInt({ min: 1, max: 5 }).toInt(),
  body('mood_after').optional({ nullable: true }).isInt({ min: 1, max: 5 }).toInt(),
  body('completed').optional().isBoolean().toBoolean(),
  body('client_request_id').isUUID(),
  body().custom((value) => {
    const allowed = new Set([
      'activity_type', 'activity_id', 'duration_seconds', 'mood_before',
      'mood_after', 'completed', 'client_request_id',
    ]);
    const unexpected = Object.keys(value).filter((key) => !allowed.has(key));
    if (unexpected.length) throw new Error('Private worksheet or game content must not be uploaded.');
    return true;
  }),
];

const historyValidation = [
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
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

module.exports = { sessionValidation, historyValidation, validate };

