const service = require('./notification.service');

async function register(req, res, next) {
  try {
    const device = await service.registerDevice(req.user.userId, req.body);
    return res.status(201).json({ success: true, data: device });
  } catch (error) { return next(error); }
}

async function unregister(req, res, next) {
  try {
    return res.json({ success: true, data: await service.unregisterDevice(req.user.userId, req.body.token) });
  } catch (error) { return next(error); }
}

function getStatus(_req, res) {
  return res.json({ success: true, data: service.status() });
}

module.exports = { register, unregister, getStatus };
