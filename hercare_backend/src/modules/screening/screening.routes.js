const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./screening.controller');
const validator = require('./screening.validator');

const router = Router();
const submitLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many screening requests. Please wait.' },
});

router.use(authenticate, authorize('mother'));
router.get('/instruments/:type', validator.instrumentParam, validator.validate, controller.getInstrument);
router.post('/assessments', submitLimiter, validator.startValidation, validator.validate, controller.start);
router.put('/assessments/:assessmentId/draft', validator.draftValidation, validator.validate, controller.saveDraft);
router.post('/assessments/:assessmentId/submit', submitLimiter, validator.submitValidation, validator.validate, controller.submit);
router.get('/assessments/latest', validator.latestValidation, validator.validate, controller.latest);
router.get('/assessments/history', validator.historyValidation, validator.validate, controller.history);
router.get('/assessments/:assessmentId', validator.assessmentId, validator.validate, controller.getOne);
router.get('/reminder', validator.latestValidation, validator.validate, controller.reminder);

module.exports = router;
