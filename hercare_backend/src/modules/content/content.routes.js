const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const p = require('./content.policy');
const service = require('./content.service');

const router = Router();
// Set before authentication so failed responses cannot be shared-cached either.
router.use((_req, res, next) => { res.set('Cache-Control', 'private, no-store'); res.set('Vary', 'Authorization, X-Content-Account-Id'); next(); });
router.use(authenticate);
router.use(async (req, _res, next) => {
  try {
    const expected = req.get('X-Content-Account-Id');
    if (!expected || p.uuid(expected) !== req.user.userId.toLowerCase()) p.fail('Your account changed. Reopen content recommendations.', 409);
    const user = await service.actor(req.user.userId);
    if (user.role !== req.user.role) p.fail('Your account permissions changed. Sign in again.', 403);
    if (!['GET', 'HEAD'].includes(req.method)) await service.spendQuota(req.user.userId);
    next();
  } catch (error) { next(error); }
});
const endpoint = (fn, status = 200) => async (req, res, next) => {
  try { res.status(status).json({ success: true, data: await fn(req) }); } catch (error) { next(error); }
};
router.get('/feed', endpoint((r) => service.feed(r.user.userId, r.query)));
router.get('/saved', endpoint((r) => service.feed(r.user.userId, r.query, true)));
router.get('/preferences', endpoint((r) => service.getPreferences(r.user.userId)));
router.put('/preferences', endpoint((r) => service.updatePreferences(r.user.userId, r.body)));
router.get('/items/:id', endpoint((r) => service.detail(r.user.userId, r.params.id)));
router.put('/items/:id/feedback', endpoint((r) => service.interaction(r.user.userId, r.params.id, r.body, 'feedback')));
router.put('/items/:id/saved', endpoint((r) => service.interaction(r.user.userId, r.params.id, r.body, 'saved')));
router.get('/admin/items', endpoint((r) => service.adminList(r.user.userId, r.query)));
router.post('/admin/items', endpoint((r) => service.createItem(r.user.userId, r.body), 201));
router.put('/admin/items/:id', endpoint((r) => service.updateItem(r.user.userId, r.params.id, r.body)));
router.put('/admin/items/:id/review', endpoint((r) => service.reviewItem(r.user.userId, r.params.id, r.body)));
router.put('/admin/items/:id/publication', endpoint((r) => service.publication(r.user.userId, r.params.id, r.body)));
router.delete('/admin/items/:id', endpoint((r) => service.archive(r.user.userId, r.params.id, r.query.version)));
router.get('/admin/policy', endpoint((r) => service.adminPolicy(r.user.userId)));
router.put('/admin/policy', endpoint((r) => service.adminPolicy(r.user.userId, r.body)));

module.exports = router;
