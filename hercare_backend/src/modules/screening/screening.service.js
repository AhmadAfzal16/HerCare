const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const guardianService = require('../guardian/guardian.service');
const { getInstrument } = require('./screening.instruments');
const { scoreAnswers } = require('./screening.scoring');

function publicAssessment(row, responses = undefined) {
  if (!row) return null;
  const assessment = {
    id: row.id,
    instrument_type: row.instrument_type,
    instrument_version: row.instrument_version,
    scoring_version: row.scoring_version,
    language: row.language,
    status: row.status,
    total_score: row.total_score === null ? null : Number(row.total_score),
    risk_level: row.risk_level,
    self_harm_positive: row.self_harm_positive,
    started_at: row.started_at,
    completed_at: row.completed_at,
    updated_at: row.updated_at,
  };
  if (responses) {
    assessment.answers = responses.map((response) => ({
      question_number: Number(response.question_number),
      option_index: Number(response.option_index),
    }));
  }
  return assessment;
}

function validatePartialAnswers(instrument, answers) {
  if (!Array.isArray(answers) || answers.length > instrument.questions.length) {
    throw new AppError('Invalid screening answers.', 422);
  }
  const seen = new Set();
  return answers.map((answer) => {
    const questionNumber = Number(answer.question_number);
    const optionIndex = Number(answer.option_index);
    const question = instrument.questions[questionNumber - 1];
    if (!Number.isInteger(questionNumber) || !Number.isInteger(optionIndex)
        || !question || !question.options[optionIndex] || seen.has(questionNumber)) {
      throw new AppError('Invalid or duplicate screening answer.', 422);
    }
    seen.add(questionNumber);
    return {
      question_number: questionNumber,
      option_index: optionIndex,
      score: question.options[optionIndex].score,
    };
  });
}

async function replaceResponses(client, assessmentId, responses) {
  await client.query('DELETE FROM screening_responses WHERE assessment_id = $1', [assessmentId]);
  for (const response of responses) {
    await client.query(
      `INSERT INTO screening_responses
         (assessment_id, question_number, option_index, score)
       VALUES ($1, $2, $3, $4)`,
      [assessmentId, response.question_number, response.option_index, response.score],
    );
  }
}

async function getAssessmentWithResponses(db, assessmentId, motherId) {
  const { rows } = await db.query(
    'SELECT * FROM screening_assessments WHERE id = $1 AND mother_id = $2',
    [assessmentId, motherId],
  );
  if (!rows[0]) throw new AppError('Screening assessment not found.', 404);
  const responseResult = await db.query(
    `SELECT question_number, option_index, score FROM screening_responses
     WHERE assessment_id = $1 ORDER BY question_number`,
    [assessmentId],
  );
  return publicAssessment(rows[0], responseResult.rows);
}

async function startAssessment(motherId, data) {
  const instrument = getInstrument(data.instrument_type);
  if (!instrument) throw new AppError('Unsupported screening instrument.', 422);
  return withTransaction(async (client) => {
    const duplicate = await client.query(
      `SELECT * FROM screening_assessments
       WHERE mother_id = $1 AND client_request_id = $2`,
      [motherId, data.client_request_id],
    );
    if (duplicate.rows[0]) {
      return getAssessmentWithResponses(client, duplicate.rows[0].id, motherId);
    }
    await client.query(
      `UPDATE screening_assessments SET status = 'abandoned'
       WHERE mother_id = $1 AND instrument_type = $2 AND status = 'draft'`,
      [motherId, instrument.type],
    );
    const { rows } = await client.query(
      `INSERT INTO screening_assessments
         (mother_id, instrument_type, instrument_version, scoring_version,
          language, client_request_id)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [
        motherId,
        instrument.type,
        instrument.version,
        instrument.scoring_version,
        data.language,
        data.client_request_id,
      ],
    );
    return publicAssessment(rows[0], []);
  });
}

async function saveDraft(motherId, assessmentId, answers) {
  return withTransaction(async (client) => {
    const current = await getAssessmentWithResponses(client, assessmentId, motherId);
    if (current.status !== 'draft') throw new AppError('Only draft assessments can be edited.', 409);
    const instrument = getInstrument(current.instrument_type);
    const responses = validatePartialAnswers(instrument, answers);
    await replaceResponses(client, assessmentId, responses);
    await client.query(
      'UPDATE screening_assessments SET updated_at = NOW() WHERE id = $1',
      [assessmentId],
    );
    return getAssessmentWithResponses(client, assessmentId, motherId);
  });
}

function periodBounds(type, now = new Date()) {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const end = new Date(start);
  if (type === 'weekly') {
    const offset = start.getUTCDay() === 0 ? 6 : start.getUTCDay() - 1;
    start.setUTCDate(start.getUTCDate() - offset);
    end.setTime(start.getTime());
    end.setUTCDate(end.getUTCDate() + 6);
  } else if (type === 'monthly') {
    start.setUTCDate(1);
    end.setUTCFullYear(start.getUTCFullYear(), start.getUTCMonth() + 1, 0);
  }
  return {
    start: start.toISOString().slice(0, 10),
    end: end.toISOString().slice(0, 10),
  };
}

async function refreshReports(motherId, assessment) {
  let weeklyReportId = null;
  for (const periodType of ['daily', 'weekly', 'monthly']) {
    const bounds = periodBounds(periodType, new Date(assessment.completed_at));
    const reportData = JSON.stringify({
      status: 'available',
      latest_screening: {
        assessment_id: assessment.id,
        instrument: assessment.instrument_type,
        score: assessment.total_score,
        risk_level: assessment.risk_level,
        self_harm_positive: assessment.self_harm_positive,
        completed_at: assessment.completed_at,
      },
    });
    const { rows } = await query(
      `INSERT INTO health_reports
         (mother_id, period_type, period_start, period_end, epds_score,
          risk_level, report_data)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
       ON CONFLICT (mother_id, period_type, period_start, period_end)
       DO UPDATE SET
         epds_score = COALESCE(EXCLUDED.epds_score, health_reports.epds_score),
         risk_level = EXCLUDED.risk_level,
         report_data = health_reports.report_data || EXCLUDED.report_data,
         updated_at = NOW()
       RETURNING id`,
      [
        motherId,
        periodType,
        bounds.start,
        bounds.end,
        assessment.instrument_type === 'epds' ? assessment.total_score : null,
        assessment.risk_level,
        reportData,
      ],
    );
    if (periodType === 'weekly') weeklyReportId = rows[0].id;
  }
  return weeklyReportId;
}

async function createCrisisAndGuardianAlert(motherId, assessment, reportId) {
  if (!assessment.self_harm_positive) return;
  await query(
    `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
     VALUES ($1, $2, $3, 'severe') ON CONFLICT (source_type, source_id) DO NOTHING`,
    [motherId, assessment.instrument_type, assessment.id],
  );
  await query(
    `INSERT INTO guardian_alerts
       (mother_id, guardian_id, report_id, alert_type, message)
     SELECT gl.mother_id, gl.guardian_id, $2, 'crisis',
       'URGENT: A screening safety response requires immediate support. Please check on her and use the crisis plan.'
     FROM guardian_links gl
     JOIN onboarding_data od ON od.user_id = gl.mother_id
     WHERE gl.mother_id = $1 AND gl.status = 'active'
       AND od.consent_tier2 = TRUE
     ON CONFLICT DO NOTHING`,
    [motherId, reportId],
  );
}

async function submitAssessment(motherId, assessmentId, answers) {
  const completed = await withTransaction(async (client) => {
    const locked = await client.query(
      `SELECT * FROM screening_assessments
       WHERE id = $1 AND mother_id = $2 FOR UPDATE`,
      [assessmentId, motherId],
    );
    if (!locked.rows[0]) throw new AppError('Screening assessment not found.', 404);
    if (locked.rows[0].status === 'completed') {
      return publicAssessment(locked.rows[0]);
    }
    if (locked.rows[0].status !== 'draft') {
      throw new AppError('This assessment can no longer be submitted.', 409);
    }
    const instrument = getInstrument(locked.rows[0].instrument_type);
    const scored = scoreAnswers(instrument, answers);
    await replaceResponses(client, assessmentId, scored.responses);
    const { rows } = await client.query(
      `UPDATE screening_assessments SET
         status = 'completed', total_score = $1, risk_level = $2,
         self_harm_positive = $3, completed_at = NOW(), updated_at = NOW()
       WHERE id = $4 RETURNING *`,
      [scored.total_score, scored.risk_level, scored.self_harm_positive, assessmentId],
    );
    await client.query(
      `UPDATE screening_reminders SET status = 'completed', assessment_id = $1
       WHERE mother_id = $2 AND instrument_type = $3 AND status = 'scheduled'`,
      [assessmentId, motherId, instrument.type],
    );
    await client.query(
      `INSERT INTO screening_reminders (mother_id, instrument_type, due_at)
       VALUES ($1, $2, NOW() + INTERVAL '7 days')
       ON CONFLICT (mother_id, instrument_type) WHERE status = 'scheduled'
       DO UPDATE SET due_at = EXCLUDED.due_at, updated_at = NOW()`,
      [motherId, instrument.type],
    );
    return publicAssessment(rows[0]);
  });

  const reportId = await refreshReports(motherId, completed);
  await createCrisisAndGuardianAlert(motherId, completed, reportId);
  await guardianService.notifyGuardian(motherId, completed.risk_level, reportId);
  return completed;
}

async function getAssessment(motherId, assessmentId) {
  return getAssessmentWithResponses({ query }, assessmentId, motherId);
}

async function getLatest(motherId, instrumentType = 'epds') {
  const { rows } = await query(
    `SELECT * FROM screening_assessments
     WHERE mother_id = $1 AND instrument_type = $2 AND status = 'completed'
     ORDER BY completed_at DESC LIMIT 1`,
    [motherId, instrumentType],
  );
  return publicAssessment(rows[0]);
}

async function getHistory(motherId, instrumentType = 'epds', limit = 20) {
  const { rows } = await query(
    `SELECT * FROM screening_assessments
     WHERE mother_id = $1 AND instrument_type = $2 AND status = 'completed'
     ORDER BY completed_at DESC LIMIT $3`,
    [motherId, instrumentType, limit],
  );
  return rows.map((row) => publicAssessment(row));
}

async function getReminder(motherId, instrumentType = 'epds') {
  const { rows } = await query(
    `SELECT id, instrument_type, due_at, status FROM screening_reminders
     WHERE mother_id = $1 AND instrument_type = $2 AND status = 'scheduled'
     ORDER BY due_at LIMIT 1`,
    [motherId, instrumentType],
  );
  if (!rows[0]) return { instrument_type: instrumentType, due: true, due_at: null };
  return {
    ...rows[0],
    due: new Date(rows[0].due_at) <= new Date(),
  };
}

function instrumentForClient(type) {
  const instrument = getInstrument(type);
  if (!instrument) throw new AppError('Unsupported screening instrument.', 404);
  return instrument;
}

module.exports = {
  instrumentForClient,
  startAssessment,
  saveDraft,
  submitAssessment,
  getAssessment,
  getLatest,
  getHistory,
  getReminder,
  _private: { publicAssessment, validatePartialAnswers, periodBounds },
};
