const moodService = require('./mood.service');

async function saveCheckin(req, res, next) {
  try {
    const data = await moodService.saveCheckin(
      req.user.userId,
      req.params.entryDate,
      req.body,
    );
    return res.json({ success: true, message: 'Mood check-in saved.', data });
  } catch (error) {
    return next(error);
  }
}

async function getToday(req, res, next) {
  try {
    const data = await moodService.getCheckin(req.user.userId, req.query.date);
    return res.json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function getHistory(req, res, next) {
  try {
    const data = await moodService.getHistory(req.user.userId, {
      from: req.query.from,
      to: req.query.to,
      limit: req.query.limit || 30,
    });
    return res.json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function getSummary(req, res, next) {
  try {
    const data = await moodService.getSummary(
      req.user.userId,
      req.query.period,
      req.query.anchor_date,
    );
    return res.json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function createJournal(req, res, next) {
  try {
    const data = await moodService.createTextJournal(req.user.userId, req.body);
    return res.status(201).json({
      success: true,
      message: 'Private journal entry saved.',
      data,
      crisis_detected: data.contains_danger,
    });
  } catch (error) {
    return next(error);
  }
}

async function listJournals(req, res, next) {
  try {
    const data = await moodService.listJournals(
      req.user.userId,
      req.query.limit || 30,
    );
    return res.json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function searchJournals(req, res, next) {
  try {
    const data = await moodService.searchJournals(
      req.user.userId,
      req.body.query,
      req.body.limit || 30,
    );
    return res.json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function deleteJournal(req, res, next) {
  try {
    await moodService.deleteJournal(req.user.userId, req.params.journalId);
    return res.json({ success: true, message: 'Journal entry deleted.' });
  } catch (error) {
    return next(error);
  }
}

async function initializeVoiceJournal(req, res, next) {
  try {
    const data = await moodService.initializeVoiceJournal(req.user.userId, req.body);
    return res.status(201).json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function completeVoiceJournal(req, res, next) {
  try {
    const data = await moodService.completeVoiceJournal(
      req.user.userId,
      req.params.journalId,
    );
    return res.json({
      success: true,
      message: 'Voice journal transcribed securely.',
      data,
      crisis_detected: data.contains_danger,
    });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  saveCheckin,
  getToday,
  getHistory,
  getSummary,
  createJournal,
  listJournals,
  searchJournals,
  deleteJournal,
  initializeVoiceJournal,
  completeVoiceJournal,
};
