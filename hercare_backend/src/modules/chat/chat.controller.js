const service = require('./chat.service');

async function status(req, res, next) {
  try { return res.json({ success: true, data: await service.getStatus(req.user.userId, req.user.role) }); }
  catch (error) { return next(error); }
}

async function messages(req, res, next) {
  try {
    const data = await service.listMessages(req.user.userId, req.user.role, req.query);
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function send(req, res, next) {
  try {
    const data = await service.sendMessage(req.user.userId, req.user.role, req.body);
    return res.status(201).json({ success: true, data, crisis_detected: data.contains_danger });
  } catch (error) { return next(error); }
}

async function read(req, res, next) {
  try { return res.json({ success: true, data: await service.markRead(req.user.userId, req.user.role) }); }
  catch (error) { return next(error); }
}

module.exports = { status, messages, send, read };

