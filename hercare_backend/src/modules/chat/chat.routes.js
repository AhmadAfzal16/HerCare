const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate } = require('../../middleware/auth');
const controller = require('./chat.controller');
const { messageValidation, historyValidation, validate } = require('./chat.validator');
const { AppError } = require('../../middleware/error_handler');

const router = Router();
// Chat polling has its own bounded budget, independent of the much smaller app-wide budget.
const ipLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many chat requests. Please pause briefly.' },
});
const readLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 600,
  keyGenerator: (req) => req.user.userId,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many chat reads. Please pause briefly.' },
});
router.use((_req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.set('Pragma', 'no-cache');
  next();
});
router.use(ipLimiter);
router.use(authenticate);
router.use((req, _res, next) => {
  const account = req.get('X-Chat-Account-Id');
  if (account !== undefined && account !== req.user.userId) {
    return next(new AppError('The account has changed. Reload chat.', 409));
  }
  return next();
});

const sendLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  keyGenerator: (req) => req.user.userId,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many messages. Please pause briefly.' },
});

router.get('/status', readLimiter, controller.status);
router.get('/messages/page', readLimiter, controller.page);
router.get('/messages', readLimiter, historyValidation, validate, controller.messages);
router.post('/messages', sendLimiter, messageValidation, validate, controller.send);
router.patch('/read', readLimiter, controller.read);

module.exports = router;

