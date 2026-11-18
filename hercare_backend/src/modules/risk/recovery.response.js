const Joi = require('joi');
const { AppError } = require('../../middleware/error_handler');

const numeric = (low, high) => Joi.number().strict().min(low).max(high).allow(null);
const day = Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).allow(null);
const nullableText = Joi.string().max(200).allow(null);
const windows = Joi.array().max(4).items(Joi.object({ window_days: Joi.number().valid(1, 7, 14, 30).required() }).unknown(true));
const signal = Joi.object({
  status: Joi.string().valid('observations_available', 'insufficient_data').required(),
  direction: Joi.string().valid('descriptive_only').required(), latest_date: day.required(),
  age_days: numeric(0, 36500).required(), stale: Joi.boolean().strict().required(),
  note: Joi.string().max(600).required(), windows: windows.required(), source: Joi.string().valid('self_reported'),
}).unknown(false);
const monitoring = Joi.object({
  status: Joi.string().valid('observed_monitoring_only').required(),
  requires_safety_review: Joi.boolean().strict().required(),
  screening_trends: Joi.array().length(2).unique('instrument').items(Joi.object({
    instrument: Joi.string().valid('epds', 'phq9').required(), version: nullableText.required(),
    language: Joi.string().valid('en', 'ur').allow(null).required(),
    current_score: numeric(0, 30).integer().required(), previous_score: numeric(0, 30).integer().required(),
    current_date: day.required(), previous_date: day.required(), score_change_points: numeric(-30, 30).integer().required(),
    actual_interval_days: numeric(1, 36500).integer().required(),
    direction: Joi.string().valid('lower_recorded_symptoms', 'higher_recorded_symptoms', 'no_change', 'insufficient_data').required(),
    stale: Joi.boolean().strict().required(), age_days: numeric(0, 36500).integer().required(),
    safety_positive: Joi.boolean().strict().required(),
    reason: Joi.string().valid('no_completed_assessment', 'language_or_version_changed', 'baseline_only', 'stale_assessment',
      'outside_followup_window', 'comparable_assessments').required(),
    comparison_rule: Joi.object({ scheduled_interval_days: Joi.number().valid(7, 14).required(),
      tolerance_days: Joi.number().valid(3).required(),
      meaning: Joi.string().valid('project_comparability_rule_not_clinical_validation').required() }).required(),
  })).required(),
  supporting_signals: Joi.object({ mood: signal.required(), sleep: signal.required() }).required(),
  future_outlook: Joi.object({ status: Joi.string().valid('not_trained').required(), probability: Joi.valid(null).required(),
    horizon_days: Joi.number().strict().valid(14).required(), target: Joi.string().valid('future_screen_positive').required(),
    reason: Joi.string().valid('genuine_dated_followup_model_unavailable').required(), notice: Joi.string().max(600).required() }).required(),
  safety_history: Joi.object({ recorded_positive_count: Joi.number().strict().integer().min(0).max(1000000).required(),
    latest_positive_date: day.required(), resolution_known: Joi.valid(false, null).required(),
    meaning: Joi.string().valid('recorded_safety_history_for_review_not_present_imminent_danger_assessment').required() }).required(),
  interpretation: Joi.string().max(600).required(),
}).unknown(false);
const response = Joi.object({
  as_of: day, periods: windows.required(), screening_changes: Joi.array().max(2).items(Joi.object()),
  requires_safety_review: Joi.boolean().strict(), validation_status: Joi.string().valid('descriptive_not_clinically_validated').required(),
  notice: Joi.string().max(600), depression_monitoring: monitoring,
}).unknown(false);

function validateRecoveryResponse(data) {
  const fail = () => { throw new AppError('The monitoring service returned an invalid response.', 503); };
  const visit = (value, depth = 0) => {
    if (depth > 12) fail();
    if (typeof value === 'number' && !Number.isFinite(value)) fail();
    if (typeof value === 'string' && value.length > 1200) fail();
    if (Array.isArray(value)) {
      if (value.length > 120) fail();
      value.forEach((entry) => visit(entry, depth + 1));
    } else if (value && typeof value === 'object') {
      if (Object.keys(value).length > 60) fail();
      for (const [key, child] of Object.entries(value)) {
        if (['mother_id', 'user_id', 'participant_id', 'journal', 'text', 'message', 'transcript', 'raw_journal', 'raw_chat'].includes(key)) fail();
        if (child != null && (/(?:_mean|_sd|_points|_percent|_per_day|_observed_days|_change)$/.test(key)
          || ['coverage', 'observed_days', 'expected_days', 'mean_minute', 'variability_minutes', 'rci'].includes(key))
          && typeof child !== 'number') fail();
        if (key === 'coverage' && (child < 0 || child > 1)) fail();
        visit(child, depth + 1);
      }
    }
  };
  visit(data);
  if (JSON.stringify(data).length > 196608 || response.validate(data, { convert: false }).error) fail();
  if (data.depression_monitoring) {
    const result = data.depression_monitoring;
    if (!data.as_of) fail();
    if (data.requires_safety_review !== result.requires_safety_review) fail();
    if ((result.safety_history.recorded_positive_count > 0) !== result.requires_safety_review) fail();
    for (const trend of result.screening_trends) {
      const cadence = trend.instrument === 'epds' ? 7 : 14;
      if (trend.comparison_rule.scheduled_interval_days !== cadence) fail();
      if (trend.instrument === 'phq9' && [trend.current_score, trend.previous_score].some((value) => value != null && value > 27)) fail();
      if (trend.direction !== 'insufficient_data' && (trend.stale || trend.reason !== 'comparable_assessments'
        || trend.current_score == null || trend.previous_score == null
        || trend.score_change_points !== trend.current_score - trend.previous_score
        || Math.abs(trend.actual_interval_days - cadence) > 3
        || (Date.parse(trend.current_date) - Date.parse(trend.previous_date)) / 86400000 !== trend.actual_interval_days)) fail();
      const expected = trend.score_change_points < 0 ? 'lower_recorded_symptoms' : trend.score_change_points > 0 ? 'higher_recorded_symptoms' : 'no_change';
      if (trend.direction !== 'insufficient_data' && trend.direction !== expected) fail();
    }
  }
  return data;
}
module.exports = { validateRecoveryResponse };
