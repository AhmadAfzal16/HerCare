const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const controller = require('./therapy.controller');
const { sessionValidation, historyValidation, validate } = require('./therapy.validator');

const router = Router();
router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
router.use(authenticate, authorize('mother'));
router.use((req, res, next) => {
  const account = req.get('X-Therapy-Account-Id');
  return account && account.toLowerCase() !== req.user.userId.toLowerCase()
    ? res.status(409).json({ success: false, code: 'ACCOUNT_CHANGED',
      message: 'Your account changed. Reopen your activity history.' }) : next();
});
const writeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 100, keyGenerator: (req) => req.user.userId,
  standardHeaders: true, legacyHeaders: false,
  message: { success: false, message: 'Too many activity updates. Please try again later.' },
});
router.get('/recommendation', controller.recommendation);
router.get('/summary', controller.summary);
router.get('/sessions', historyValidation, validate, controller.history);
router.post('/sessions', writeLimiter, sessionValidation, validate, controller.record);

module.exports = router;

