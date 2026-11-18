const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate, authorize } = require('../../middleware/auth');
const { AppError } = require('../../middleware/error_handler');
const service = require('./crisis.service');
const router = Router();
// Include authentication/account-conflict errors, not just successful responses.
router.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
const writes = rateLimit({ windowMs: 60000, max: 20, standardHeaders: true, legacyHeaders: false,
  keyGenerator: (req) => req.user.userId, message: { success: false, message: 'Please pause before changing more crisis records. Emergency phone contacts remain available.' } });
function handle(fn) {
  return async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    try { res.json({ success: true, data: await fn(req) }); } catch (error) { next(error); }
  };
}
// No account, plan or location is required to read verified emergency contacts.
router.get('/contacts', handle(() => require('./crisis.contacts').getCatalog()));
// Bounded public institution data, never a location/health-data query. Private
// crisis requests below retain no-store and the existing role/consent checks.
router.get('/facilities', (req, res, next) => {
  try {
    const directory = require('./crisis.directory');
    directory.validateQuery(req.query, req.originalUrl || req.url);
    const response = directory.getResponse();
    res.set('Cache-Control', 'public, max-age=300, must-revalidate');
    res.set('ETag', response.etag);
    if (req.fresh) return res.status(304).end();
    return res.type('application/json').send(response.body);
  } catch (error) { return next(error); }
});
router.use(authenticate, authorize('mother'));
// Bind private requests to the screen's account snapshot. An interceptor/token
// refresh during account switching must not write a previous mother's plan.
router.use((req, _res, next) => {
  const account = req.get('X-Crisis-Account-Id');
  if (account && account.toLowerCase() !== req.user.userId.toLowerCase()) {
    return next(new AppError('Your account changed. Reopen immediate help before accessing private records.', 409));
  }
  return next();
});
router.get('/support', handle((req) => service.support(req.user.userId)));
router.put('/plan', writes, handle((req) => service.savePlan(req.user.userId, req.body)));
router.delete('/plan', writes, handle((req) => {
  if (Object.keys(req.query).some((key) => key !== 'version') || typeof req.query.version !== 'string' || !/^\d+$/.test(req.query.version)) {
    throw new AppError('A safety-plan version is required.', 422);
  }
  return service.deletePlan(req.user.userId, Number(req.query.version));
}));
router.put('/guardian-safety', writes, handle((req) => service.setGuardianSafety(req.user.userId, req.body)));
router.post('/events', writes, handle(async (req) => {
  const event = await service.requestSupport(req.user.userId, req.body);
  // The support transaction has committed. Nudge the durable worker without
  // waiting for Firebase or delaying emergency contacts; never promise arrival.
  if (event.guardian_notification === 'queued' && ['pending', 'retry', 'no_device'].includes(event.notification_delivery)) {
    void require('../notifications/notification.service').processPendingSafely();
  }
  return event;
}));
router.get('/events', handle((req) => service.history(req.user.userId, req.query)));
router.patch('/events/:eventId', writes, handle((req) => service.updateEvent(req.user.userId, req.params.eventId, req.body)));
module.exports = router;
