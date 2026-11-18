const { Router } = require('express');
const express = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./mood.controller');
const validator = require('./mood.validator');
const transcription = require('./transcription.service');
const transcriptionWorker = require('./transcription.worker');
const database = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');

const router = Router();
const journalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many journal requests. Please wait a moment.' },
});

router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
router.use(authenticate, authorize('mother'));
router.use(async (req, _res, next) => {
  try {
    const owner = req.get('X-Mood-Account-Id');
    if (owner && owner.toLowerCase() !== req.user.userId.toLowerCase()) {
      throw new AppError('Your account changed. Reopen your private journal.', 409);
    }
    await transcription.authorize(database, req.user.userId);
    next();
  } catch (error) { next(error); }
});

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
  '/voice',
  journalLimiter,
  express.raw({ type: ['audio/wav', 'audio/mp4', 'audio/mpeg'], limit: '4mb' }),
  validator.privateVoiceValidation,
  validator.validate,
  controller.savePrivateVoiceJournal,
);
router.get(
  '/voice/:journalId/audio',
  validator.journalIdValidation,
  validator.validate,
  controller.getPrivateVoiceAudio,
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

const voiceWorkLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 20, keyGenerator: (req) => req.user.userId,
  standardHeaders: true, legacyHeaders: false,
});
const voiceAction = (fn, status = 200) => async (req, res, next) => {
  try { res.status(status).json({ success: true, data: await fn(req) }); }
  catch (error) { next(error); }
};
router.post('/voice/:journalId/transcription', voiceWorkLimiter, validator.journalIdValidation, validator.validate,
  voiceAction(async (req) => {
    if (Object.keys(req.body || {}).length) throw new AppError('This action does not accept journal content.', 422);
    const result = await transcription.request(req.user.userId, req.params.journalId);
    void transcriptionWorker.processPendingSafely();
    return result;
  }, 202));
router.get('/voice/:journalId/transcription', validator.journalIdValidation, validator.validate,
  voiceAction((req) => transcription.get(req.user.userId, req.params.journalId)));
router.put('/voice/:journalId/transcription', journalLimiter, validator.journalIdValidation, validator.validate,
  voiceAction((req) => transcription.confirm(req.user.userId, req.params.journalId, req.body)));
router.delete('/voice/:journalId/transcription', validator.journalIdValidation, validator.validate,
  voiceAction((req) => transcription.cancel(req.user.userId, req.params.journalId)));
module.exports = router;
