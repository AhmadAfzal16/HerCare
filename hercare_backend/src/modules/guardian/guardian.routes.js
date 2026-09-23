const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate } = require('../../middleware/auth');
const ctrl = require('./guardian.controller');
const {
  validateAcceptInvite,
  validateGetReports,
  validateGenerateReport,
  validateReportId,
  validateGetDashboard,
  validateGetAlerts,
  validateMarkAlertsRead,
} = require('./guardian.validator');

const router = Router();
router.use(authenticate);

const inviteLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many invite attempts. Please try again later.' },
});

router.post('/invite', inviteLimiter, ctrl.generateInvite);
router.post('/invite/refresh', inviteLimiter, ctrl.refreshInvite);
router.post('/accept', inviteLimiter, validateAcceptInvite, ctrl.acceptInvite);
router.get('/link', ctrl.getLink);
router.delete('/link', ctrl.revokeLink);

router.get('/dashboard', validateGetDashboard, ctrl.getDashboard);

router.get('/reports', validateGetReports, ctrl.getReports);
router.get('/reports/:id', validateReportId, ctrl.getReportById);
router.post('/reports/generate', validateGenerateReport, ctrl.generateReport);

router.get('/alerts', validateGetAlerts, ctrl.getAlerts);
router.patch('/alerts/read', validateMarkAlertsRead, ctrl.markAlertsRead);

module.exports = router;
