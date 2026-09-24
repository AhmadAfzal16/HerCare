const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate } = require('../../middleware/auth');
const controller = require('./chat.controller');
const { messageValidation, historyValidation, validate } = require('./chat.validator');

const router = Router();
router.use(authenticate);

const sendLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many messages. Please pause briefly.' },
});

router.get('/status', controller.status);
router.get('/messages', historyValidation, validate, controller.messages);
router.post('/messages', sendLimiter, messageValidation, validate, controller.send);
router.patch('/read', controller.read);

module.exports = router;

