const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./mood.controller');
const validator = require('./mood.validator');

const router = Router();
const journalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many journal requests. Please wait a moment.' },
});

router.use(authenticate, authorize('mother'));

router.put(
  '/checkins/:entryDate',
  validator.checkinValidation,
  validator.validate,
  controller.saveCheckin,
);
router.get('/today', validator.todayValidation, validator.validate, controller.getToday);
router.get('/history', validator.historyValidation, validator.validate, controller.getHistory);
router.get('/summary', validator.summaryValidation, validator.validate, controller.getSummary);

router.post(
  '/journals',
  journalLimiter,
  validator.journalValidation,
  validator.validate,
  controller.createJournal,
);
router.get(
  '/journals',
  validator.journalListValidation,
  validator.validate,
  controller.listJournals,
);
router.post(
  '/journals/search',
  journalLimiter,
  validator.journalSearchValidation,
  validator.validate,
  controller.searchJournals,
);
router.delete(
  '/journals/:journalId',
  validator.journalIdValidation,
  validator.validate,
  controller.deleteJournal,
);
router.post(
  '/voice/initialize',
  journalLimiter,
  validator.voiceInitializeValidation,
  validator.validate,
  controller.initializeVoiceJournal,
);
router.post(
  '/voice/:journalId/complete',
  journalLimiter,
  validator.journalIdValidation,
  validator.validate,
  controller.completeVoiceJournal,
);

module.exports = router;
