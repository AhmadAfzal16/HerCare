const { body, validationResult } = require('express-validator');

const completeOnboardingValidation = [
  body('full_name').trim().isLength({ min: 2, max: 100 }),
  body('age').isInt({ min: 15, max: 55 }).toInt(),
  body('education_level').trim().isLength({ min: 1, max: 50 }),
  body('city').trim().isLength({ min: 1, max: 60 }),
  body('months_since_birth').isInt({ min: 0, max: 12 }).toInt(),
  body('delivery_method').isIn(['vaginal', 'cesarean']),
  body('parity').isInt({ min: 0, max: 20 }).toInt(),
  body('baby_gender').isIn(['male', 'female']),
  body('has_preeclampsia').isBoolean().toBoolean(),
  body('has_postpartum_hemorrhage').isBoolean().toBoolean(),
  body('has_preterm_birth').isBoolean().toBoolean(),
  body('has_gestational_diabetes').isBoolean().toBoolean(),
  body('household_type').isIn(['nuclear', 'joint']),
  body('income_range').trim().isLength({ min: 1, max: 50 }),
  body('primary_support').isIn(['husband', 'mother_in_law', 'siblings', 'none']),
  body('consent_tier1')
    .isBoolean()
    .withMessage('Basic monitoring consent must be a boolean')
    .bail()
    .custom((value) => value === true)
    .withMessage('Basic monitoring consent is required'),
  body('consent_tier2').isBoolean().toBoolean(),
  body('consent_tier3').isBoolean().toBoolean(),
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

module.exports = { completeOnboardingValidation, validate };
