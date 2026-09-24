const { body, query, validationResult } = require('express-validator');

const ALLOWED_TELEMETRY_KEYS = new Set([
  'local_date',
  'timezone_offset_minutes',
  'notifications_seen',
  'message_notifications',
  'negative_notifications',
  'distress_notifications',
  'abuse_notifications',
  'screen_time_minutes',
  'social_minutes',
  'late_night_minutes',
  'app_switches',
  'notification_access',
  'usage_access',
  'analysis_version',
  'client_request_id',
]);

const telemetryValidation = [
  body().custom((value) => {
    const unexpected = Object.keys(value || {}).filter((key) => !ALLOWED_TELEMETRY_KEYS.has(key));
    if (unexpected.length) {
      throw new Error('Only aggregate telemetry is accepted; notification content is prohibited.');
    }
    return true;
  }),
  body('local_date').matches(/^\d{4}-\d{2}-\d{2}$/).isISO8601({ strict: true }),
  body('timezone_offset_minutes').isInt({ min: -840, max: 840 }).toInt(),
  ...[
    'notifications_seen',
    'message_notifications',
    'negative_notifications',
    'distress_notifications',
    'abuse_notifications',
  ].map((field) => body(field).isInt({ min: 0, max: 10000 }).toInt()),
  ...['screen_time_minutes', 'social_minutes'].map(
    (field) => body(field).isInt({ min: 0, max: 1440 }).toInt(),
  ),
  body('late_night_minutes').isInt({ min: 0, max: 480 }).toInt(),
  body('app_switches').isInt({ min: 0, max: 20000 }).toInt(),
  body('notification_access').isBoolean().toBoolean(),
  body('usage_access').isBoolean().toBoolean(),
  body('analysis_version').isString().trim().isLength({ min: 1, max: 40 }),
  body('client_request_id').isUUID(),
];

const historyValidation = [
  query('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
];

const consentValidation = [body('enabled').isBoolean().toBoolean()];

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

module.exports = {
  telemetryValidation,
  historyValidation,
  consentValidation,
  validate,
};
