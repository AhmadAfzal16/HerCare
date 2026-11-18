const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const { AppError } = require('../../middleware/error_handler');
const service = require('./sleep.service');
const router = Router();
router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
router.use(authenticate, authorize('mother'));
router.use((req, _res, next) => {
  const account = req.get('X-Sleep-Account-Id');
  return account && account.toLowerCase() !== req.user.userId.toLowerCase()
    ? next(new AppError('Your account changed. Reopen sleep before accessing private records.', 409)) : next();
});
const endpoint = (fn) => async (req, res, next) => {
  try { res.json({ success: true, data: await fn(req) }); } catch (error) { next(error); }
};
router.get('/', endpoint((req) => service.dashboard(req.user.userId, req.query)));
router.put('/', rateLimit({ windowMs: 900000, max: 60, keyGenerator: (req) => req.user.userId,
  standardHeaders: true, legacyHeaders: false }), endpoint((req) => service.save(req.user.userId, req.body)));
module.exports = router;
