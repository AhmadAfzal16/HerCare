const service = require('./risk.service');

async function saveTelemetry(req, res, next) {
  try {
    const data = await service.saveTelemetry(req.user.userId, req.body);
    return res.json({ success: true, message: 'Aggregate telemetry saved.', data });
  } catch (error) { return next(error); }
}

async function predict(req, res, next) {
  try {
    const data = await service.generatePrediction(req.user.userId);
    return res.status(201).json({ success: true, data });
  } catch (error) { return next(error); }
}

async function latest(req, res, next) {
  try {
    return res.json({ success: true, data: await service.getLatest(req.user.userId) });
  } catch (error) { return next(error); }
}

async function history(req, res, next) {
  try {
    return res.json({
      success: true,
      data: await service.getHistory(req.user.userId, req.query.limit || 20),
    });
  } catch (error) { return next(error); }
}

async function status(req, res, next) {
  try {
    return res.json({ success: true, data: await service.getStatus(req.user.userId) });
  } catch (error) { return next(error); }
}

async function consent(req, res, next) {
  try {
    const data = await service.updateConsent(req.user.userId, req.body.enabled);
    return res.json({ success: true, message: 'Monitoring consent updated.', data });
  } catch (error) { return next(error); }
}

module.exports = { saveTelemetry, predict, latest, history, status, consent };
