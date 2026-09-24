const { body, param, query, validationResult } = require('express-validator');

const instrumentParam = param('type').isIn(['epds', 'phq9']);
const assessmentId = param('assessmentId').isUUID();
const answersRule = body('answers')
  .isArray({ min: 0, max: 10 })
  .withMessage('answers must be an array with at most 10 items');
const answerFields = [
  body('answers.*.question_number').isInt({ min: 1, max: 10 }).toInt(),
  body('answers.*.option_index').isInt({ min: 0, max: 3 }).toInt(),
];

const startValidation = [
  body('instrument_type').isIn(['epds', 'phq9']),
  body('language').isIn(['en', 'ur']),
  body('client_request_id').isUUID(),
];
const draftValidation = [assessmentId, answersRule, ...answerFields];
const submitValidation = [assessmentId, answersRule, ...answerFields];
const historyValidation = [
  query('instrument').optional().isIn(['epds', 'phq9']),
  query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
];
const latestValidation = [query('instrument').optional().isIn(['epds', 'phq9'])];

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
  instrumentParam,
  assessmentId,
  startValidation,
  draftValidation,
  submitValidation,
  historyValidation,
  latestValidation,
  validate,
};
