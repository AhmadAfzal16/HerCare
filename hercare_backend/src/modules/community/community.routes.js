const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const service = require('./community.service');
const router = Router();
router.use(authenticate);
router.use((_req, res, next) => { res.set('Cache-Control', 'private, no-store'); next(); });
router.use(async (req, _res, next) => {
  try {
    await service.actor(req.user.userId, false);
    if (!['GET', 'HEAD'].includes(req.method)) await service.spendQuota(req.user.userId);
    next();
  } catch (error) { next(error); }
});
const endpoint = (fn) => async (req, res, next) => {
  try { res.json({ success: true, data: await fn(req) }); } catch (error) { next(error); }
};
router.get('/status', endpoint((r) => service.status(r.user.userId)));
router.post('/join', endpoint((r) => service.join(r.user.userId, r.body)));
router.get('/posts', endpoint((r) => service.list(r.user.userId, r.query)));
router.post('/posts', endpoint((r) => service.create(r.user.userId, r.body)));
router.get('/posts/:id', endpoint((r) => service.detail(r.user.userId, r.params.id)));
router.get('/posts/:id/comments', endpoint((r) => service.list(r.user.userId, { ...r.query, parent_id: r.params.id })));
router.delete('/posts/:id', endpoint((r) => service.remove(r.user.userId, r.params.id)));
router.put('/posts/:id/reactions', endpoint((r) => service.react(r.user.userId, r.params.id, r.body)));
router.post('/posts/:id/reports', endpoint((r) => service.report(r.user.userId, r.params.id, r.body)));
router.get('/blocks', endpoint((r) => service.blocks(r.user.userId)));
router.put('/blocks/:id', endpoint((r) => service.block(r.user.userId, r.params.id, true)));
router.delete('/blocks/:id', endpoint((r) => service.block(r.user.userId, r.params.id, false)));
router.get('/sessions', endpoint((r) => service.sessions(r.user.userId)));
router.get('/moderation', endpoint((r) => service.queue(r.user.userId, r.query.cursor)));
router.put('/moderation/:id', endpoint((r) => service.review(r.user.userId, r.params.id, r.body)));
router.put('/members/:id/suspension', endpoint((r) => service.suspend(r.user.userId, r.params.id, r.body)));
router.post('/sessions', endpoint((r) => service.schedule(r.user.userId, r.body)));
router.delete('/sessions/:id', endpoint((r) => service.cancelSession(r.user.userId, r.params.id)));
module.exports = router;
