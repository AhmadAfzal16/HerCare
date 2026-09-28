const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate } = require('../../middleware/auth');
const controller = require('./therapy.controller');
const { sessionValidation, historyValidation, validate } = require('./therapy.validator');

const router = Router();
router.use(authenticate);
const writeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 100, standardHeaders: true, legacyHeaders: false,
  message: { success: false, message: 'Too many activity updates. Please try again later.' },
});
router.get('/recommendation', controller.recommendation);
router.get('/summary', controller.summary);
router.get('/sessions', historyValidation, validate, controller.history);
router.post('/sessions', writeLimiter, sessionValidation, validate, controller.record);

module.exports = router;

