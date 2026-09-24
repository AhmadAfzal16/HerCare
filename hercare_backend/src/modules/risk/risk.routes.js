const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./risk.controller');
const validator = require('./risk.validator');

const router = Router();
const predictionLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 6,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Please wait before generating another insight.' },
});

router.use(authenticate, authorize('mother'));
router.get('/status', controller.status);
router.patch('/consent', validator.consentValidation, validator.validate, controller.consent);
router.post('/telemetry', validator.telemetryValidation, validator.validate, controller.saveTelemetry);
router.post('/predictions', predictionLimiter, controller.predict);
router.get('/predictions/latest', controller.latest);
router.get('/predictions/history', validator.historyValidation, validator.validate, controller.history);

module.exports = router;
