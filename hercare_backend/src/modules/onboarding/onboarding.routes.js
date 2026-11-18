const { Router } = require('express');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./onboarding.controller');
const service = require('./onboarding.service');
const { accountScope } = require('../../middleware/account_scope');
const {
  completeOnboardingValidation,
  validate,
} = require('./onboarding.validator');

const router = Router();

router.get('/consent', authenticate, authorize('mother'),
  accountScope('X-Privacy-Account-Id', { required: true }), async (req, res, next) => {
    try {
      res.json({ success: true, data: await service.getConsent(req.user.userId) });
    } catch (error) { next(error); }
  });
router.patch('/consent', authenticate, authorize('mother'),
  accountScope('X-Privacy-Account-Id', { required: true }), async (req, res, next) => {
    try {
      res.json({ success: true, data: await service.updateConsent(req.user.userId, req.body) });
    } catch (error) { next(error); }
  });

router.put(
  '/',
  authenticate,
  authorize('mother'),
  completeOnboardingValidation,
  validate,
  controller.complete,
);

module.exports = router;
