function number(value) { return value == null ? null : Number(value); }
function slope(rows) {
  if (rows.length < 2) return null;
  const start = Date.parse(rows[0].entry_date);
  const x = rows.map((row) => (Date.parse(row.entry_date) - start) / 86400000);
  const y = rows.map((row) => Number(row.mood_rating));
  const mx = x.reduce((sum, value) => sum + value, 0) / x.length;
  const my = y.reduce((sum, value) => sum + value, 0) / y.length;
  const denominator = x.reduce((sum, value) => sum + (value - mx) ** 2, 0);
  return denominator ? Number((x.reduce((sum, value, index) => sum + (value - mx) * (y[index] - my), 0) / denominator).toFixed(4)) : null;
}
async function aggregate(client, motherId, enabled, now = new Date()) {
  const context = { personalization_enabled: enabled, as_of: now.toISOString() };
  if (!enabled) return context;
  const asOf = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  const moods = await client.query(`SELECT entry_date::text,mood_rating FROM mood_checkins
    WHERE mother_id=$1 AND entry_date BETWEEN $2::date-13 AND $2::date ORDER BY entry_date LIMIT 14`, [motherId, asOf]);
  const screens = await client.query(`SELECT DISTINCT ON(instrument_type) instrument_type,instrument_version,language,total_score,self_harm_positive,completed_at
    FROM screening_assessments WHERE mother_id=$1 AND status='completed' AND completed_at<=$2
      AND completed_at>=$2::timestamptz-INTERVAL '60 days' ORDER BY instrument_type,completed_at DESC LIMIT 2`, [motherId, now]);
  const risk = await client.query(`SELECT depression_probability,risk_level,generated_at,model_version,model_scope,input_summary
    FROM risk_predictions WHERE mother_id=$1 AND generated_at<=$2 ORDER BY generated_at DESC LIMIT 1`, [motherId, now]);
  const sentiment = await client.query(`SELECT COUNT(*)::int AS record_count,AVG(sentiment_score) AS mean_score,
    COUNT(*) FILTER(WHERE contains_danger)::int AS rule_safety_count,MAX(created_at) AS latest_at
    FROM journal_entries WHERE mother_id=$1 AND sentiment_score IS NOT NULL AND created_at BETWEEN $2::timestamptz-INTERVAL '14 days' AND $2`, [motherId, now]);
  context.mood = { window_days: 14, record_count: moods.rows.length, mean_rating: moods.rows.length ? Number((moods.rows.reduce((sum, row) => sum + Number(row.mood_rating), 0) / moods.rows.length).toFixed(3)) : null,
    latest_date: moods.rows.at(-1)?.entry_date || null, coverage_fraction: moods.rows.length / 14,
    trend_per_day: slope(moods.rows), clinical_validation: false };
  context.screenings = screens.rows.map((row) => ({ instrument: row.instrument_type, version: row.instrument_version, language: row.language,
    score: number(row.total_score), completed_at: new Date(row.completed_at).toISOString(), safety_positive: row.self_harm_positive === true,
    age_days: Number(((now - new Date(row.completed_at)) / 86400000).toFixed(1)),
    stale: now - new Date(row.completed_at) > (row.instrument_type === 'epds' ? 7 : 14) * 86400000,
    interpretation: 'screening_not_diagnosis' }));
  const prediction = risk.rows[0];
  context.risk = prediction ? { probability: number(prediction.depression_probability), risk_level: prediction.risk_level,
    generated_at: new Date(prediction.generated_at).toISOString(), model_version: prediction.model_version, model_scope: prediction.model_scope,
    validation_status: 'research_only', confidence: null, stale: now - new Date(prediction.generated_at) > 48 * 3600000,
    interpretation: 'research_estimate_not_diagnosis_or_validated_forecast' } : null;
  const signal = sentiment.rows[0];
  context.sentiment = signal?.record_count ? { window_days: 14, record_count: signal.record_count, mean_score: number(signal.mean_score),
    rule_safety_count: signal.rule_safety_count, latest_at: new Date(signal.latest_at).toISOString(), clinical_validation: false,
    interpretation: 'general_sentiment_and_rule_flags_not_clinical_distress_probability' } : null;
  return context;
}
module.exports = { aggregate, slope };
