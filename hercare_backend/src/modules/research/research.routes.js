const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const service = require('./research.service');
const router = Router();
router.use(authenticate);
router.get('/consent', authorize('mother'), async (req, res, next) => {
  try { res.json({ success: true, data: await service.status(req.user.userId) }); }
  catch (error) { next(error); }
});
router.put('/consent', authorize('mother'), async (req, res, next) => {
  try { res.json({ success: true, data: await service.setConsent(req.user.userId, req.body) }); }
  catch (error) { next(error); }
});
router.post('/export', authorize('admin'), rateLimit({ windowMs: 60000, max: 3, standardHeaders: true, legacyHeaders: false }), async (req, res, next) => {
  try {
    const data = await service.exportData(req.user.userId, req.body);
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data });
  } catch (error) { next(error); }
});
module.exports = router;
