const service = require('./therapy.service');

async function record(req, res, next) {
  try {
    const data = await service.recordSession(req.user.userId, req.user.role, req.body);
    return res.status(201).json({ success: true, data });
  } catch (error) { return next(error); }
}
async function history(req, res, next) {
  try {
    const data = await service.getHistory(req.user.userId, req.user.role, req.query.limit || 30);
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}
async function recommendation(req, res, next) {
  try {
    return res.json({ success: true, data: await service.getRecommendation(req.user.userId, req.user.role) });
  } catch (error) { return next(error); }
}
async function summary(req, res, next) {
  try {
    return res.json({ success: true, data: await service.getSummary(req.user.userId, req.user.role) });
  } catch (error) { return next(error); }
}
module.exports = { record, history, recommendation, summary };

