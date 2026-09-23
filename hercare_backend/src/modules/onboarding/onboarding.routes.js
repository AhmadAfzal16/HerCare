const { Router } = require('express');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./onboarding.controller');
const {
  completeOnboardingValidation,
  validate,
} = require('./onboarding.validator');

const router = Router();

router.put(
  '/',
  authenticate,
  authorize('mother'),
  completeOnboardingValidation,
  validate,
  controller.complete,
);

module.exports = router;
