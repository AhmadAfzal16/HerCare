const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./risk.controller');
const validator = require('./risk.validator');
const { accountScope } = require('../../middleware/account_scope');
const monitoring = require('./m4.service');

const router = Router();
const predictionLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 6,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Please wait before generating another insight.' },
});

const m4 = Router();
m4.use((req, res, next) => {
  res.set('Cache-Control', 'private, no-store');
  next();
});
m4.use(authenticate, authorize('mother'), accountScope('X-Risk-Account-Id', { required: true }));
m4.get('/', async (req, res, next) => {
  try { res.json({ success: true, data: await monitoring.summary(req.user.userId) }); }
  catch (error) { next(error); }
});
m4.put('/context-checkin', async (req, res, next) => {
  try { res.json({ success: true, data: await monitoring.saveCheckin(req.user.userId, req.body) }); }
  catch (error) { next(error); }
});
m4.put('/text-consent', async (req, res, next) => {
  try { res.json({ success: true, data: await monitoring.saveTextConsent(req.user.userId, req.body) }); }
  catch (error) { next(error); }
});
router.use('/m4', m4);
router.use(authenticate, authorize('mother'), accountScope('X-Risk-Account-Id'));
router.get('/recovery', async (req, res, next) => {
  try { res.json({ success: true, data: await require('./recovery.service').summary(req.user.userId) }); }
  catch (error) { next(error); }
});
router.get('/context', async (req, res, next) => {
  try { res.json({ success: true, data: await require('./risk.context').getContext(req.user.userId) }); }
  catch (error) { next(error); }
});
router.put('/context', async (req, res, next) => {
  try { res.json({ success: true, data: await require('./risk.context').saveContext(req.user.userId, req.body) }); }
  catch (error) { next(error); }
});
router.get('/status', controller.status);
router.patch('/consent', validator.consentValidation, validator.validate, controller.consent);
router.post('/telemetry', validator.telemetryValidation, validator.validate, controller.saveTelemetry);
router.post('/predictions', predictionLimiter, controller.predict);
router.get('/predictions/latest', controller.latest);
router.get('/predictions/history', validator.historyValidation, validator.validate, controller.history);

module.exports = router;
