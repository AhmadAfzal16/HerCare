const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const service = require('./chatbot.service');
const router = Router();
const limiter = rateLimit({ windowMs: 60000, max: 12, standardHeaders: true, legacyHeaders: false,
  message: { success: false, message: 'Please pause before sending more Hum-Raaz messages.' } });
router.use(authenticate, authorize('mother'));
function handle(fn, status = 200) {
  return async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    try { res.status(status).json({ success: true, data: await fn(req) }); } catch (error) { next(error); }
  };
}
router.get('/status', handle((req) => service.status(req.user.userId)));
router.put('/consent', handle((req) => service.setConsent(req.user.userId, req.body)));
router.get('/sessions', handle((req) => service.listSessions(req.user.userId, req.query)));
router.post('/sessions', handle((req) => service.createSession(req.user.userId, req.body), 201));
router.get('/sessions/:sessionId/messages', handle((req) => service.listMessages(req.user.userId, req.params.sessionId, req.query)));
router.post('/sessions/:sessionId/messages', limiter, handle((req) => service.sendMessage(req.user.userId, req.params.sessionId, req.body)));
router.delete('/sessions/:sessionId', handle((req) => service.deleteSession(req.user.userId, req.params.sessionId)));
module.exports = router;
