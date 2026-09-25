const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { body, validationResult } = require('express-validator');
const { authenticate } = require('../../middleware/auth');
const controller = require('./notification.controller');

const router = Router();
router.use(authenticate);
const writeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 30, standardHeaders: true, legacyHeaders: false,
  message: { success: false, message: 'Too many device registration attempts.' },
});
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ success: false, message: 'Invalid device details.', errors: errors.array() });
  return next();
};
const tokenRule = body('token').isString().trim().isLength({ min: 20, max: 4096 });

router.get('/status', controller.getStatus);
router.post('/devices', writeLimiter, [tokenRule, body('platform').isIn(['android', 'ios', 'web'])], validate, controller.register);
router.delete('/devices', writeLimiter, [tokenRule], validate, controller.unregister);

module.exports = router;
