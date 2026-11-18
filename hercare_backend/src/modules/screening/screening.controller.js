const screeningService = require('./screening.service');
const scheduleService = require('./screening.schedule');

async function schedule(req, res, next) {
  try {
    const data = await scheduleService.getSchedule(req.user.userId);
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function getInstrument(req, res, next) {
  try {
    const data = await screeningService.instrumentForClient(req.params.type, req.query.version);
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function start(req, res, next) {
  try {
    const data = await screeningService.startAssessment(req.user.userId, req.body);
    return res.status(201).json({ success: true, data });
  } catch (error) { return next(error); }
}

async function saveDraft(req, res, next) {
  try {
    const data = await screeningService.saveDraft(
      req.user.userId, req.params.assessmentId, req.body.answers,
    );
    return res.json({ success: true, message: 'Screening draft saved.', data });
  } catch (error) { return next(error); }
}

async function submit(req, res, next) {
  try {
    const data = await screeningService.submitAssessment(
      req.user.userId, req.params.assessmentId, req.body.answers,
    );
    return res.json({
      success: true,
      message: 'Screening completed.',
      data,
      crisis_detected: data.self_harm_positive,
    });
  } catch (error) { return next(error); }
}

async function getOne(req, res, next) {
  try {
    const data = await screeningService.getAssessment(req.user.userId, req.params.assessmentId);
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function latest(req, res, next) {
  try {
    const data = await screeningService.getLatest(
      req.user.userId, req.query.instrument || 'epds',
    );
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function history(req, res, next) {
  try {
    const data = await screeningService.getHistory(
      req.user.userId, req.query.instrument || 'epds', req.query.limit || 20,
    );
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

async function reminder(req, res, next) {
  try {
    const data = await screeningService.getReminder(
      req.user.userId, req.query.instrument || 'epds',
    );
    return res.json({ success: true, data });
  } catch (error) { return next(error); }
}

module.exports = { getInstrument, start, saveDraft, submit, getOne, latest, history, reminder, schedule };
