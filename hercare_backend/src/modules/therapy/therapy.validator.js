const { body, query, validationResult } = require('express-validator');
const { isKnownActivity } = require('./therapy.catalog');
const { AppError } = require('../../middleware/error_handler');

const SESSION_FIELDS = new Set([
  'activity_type', 'activity_id', 'duration_seconds', 'mood_before',
  'mood_after', 'completed', 'client_request_id', 'client_completed_at',
  'breathing_participation',
]);

function normalizeCompletedAt(value, asOf) {
  const match = typeof value === 'string'
    ? /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/.exec(value) : null;
  const fail = () => { throw new AppError('Practice time must be a valid timezone-aware ISO timestamp within the last 90 days.', 422); };
  if (!match) return fail();
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, zone] = match;
  const year = Number(yearText), month = Number(monthText), day = Number(dayText);
  if (month < 1 || month > 12 || day < 1 || day > new Date(Date.UTC(year, month, 0)).getUTCDate()
      || Number(hourText) > 23 || Number(minuteText) > 59 || Number(secondText) > 59) return fail();
  if (zone !== 'Z' && (Number(zone.slice(1, 3)) > 14 || Number(zone.slice(4)) > 59
      || (Number(zone.slice(1, 3)) === 14 && Number(zone.slice(4)) !== 0))) return fail();
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp) || timestamp > asOf + 5 * 60 * 1000
      || timestamp < asOf - 90 * 24 * 60 * 60 * 1000) return fail();
  return new Date(timestamp).toISOString();
}

function normalizeSession(value, asOf = Date.now()) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new AppError('An activity record is required.', 422);
  }
  if (Object.keys(value).some((key) => !SESSION_FIELDS.has(key))) {
    throw new AppError('Private worksheet or game content must not be uploaded.', 422);
  }
  if (typeof value.activity_type !== 'string' || typeof value.activity_id !== 'string'
      || !isKnownActivity(value.activity_type, value.activity_id)) {
    throw new AppError('Unknown therapeutic activity.', 422);
  }
  if (!Number.isInteger(value.duration_seconds) || value.duration_seconds < 1
      || value.duration_seconds > 7200) {
    throw new AppError('Activity duration must be between 1 and 7200 seconds.', 422);
  }
  for (const key of ['mood_before', 'mood_after']) {
    if (value[key] != null && (!Number.isInteger(value[key]) || value[key] < 1 || value[key] > 5)) {
      throw new AppError('Optional mood ratings must be whole numbers between 1 and 5.', 422);
    }
  }
  if (value.completed !== undefined && typeof value.completed !== 'boolean') {
    throw new AppError('Completion must be true or false.', 422);
  }
  if (value.breathing_participation != null && (value.activity_type !== 'breathing'
      || !['most_cues', 'some_cues', 'stopped_early'].includes(value.breathing_participation))) {
    throw new AppError('Invalid breathing participation response.', 422);
  }
  if (typeof value.client_request_id !== 'string'
      || !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value.client_request_id)) {
    throw new AppError('A valid activity request identifier is required.', 422);
  }
  return {
    activity_type: value.activity_type,
    activity_id: value.activity_id,
    duration_seconds: value.duration_seconds,
    mood_before: value.mood_before ?? null,
    mood_after: value.mood_after ?? null,
    completed: value.completed ?? true,
    ...(value.breathing_participation == null ? {} : { breathing_participation: value.breathing_participation }),
    client_request_id: value.client_request_id.toLowerCase(),
    ...(value.client_completed_at === undefined ? {} : {
      client_completed_at: normalizeCompletedAt(value.client_completed_at, asOf),
    }),
  };
}

const sessionValidation = [body().custom((value) => { normalizeSession(value); return true; })];

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

module.exports = { sessionValidation, historyValidation, validate, normalizeSession };

