const db = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');

const PERIODS = { daily: 1, weekly: 7, fortnightly: 14 };
const BARS = 6;
const DAY_MS = 86400000;
const MOOD_WEIGHT = 60;
const EPDS_WEIGHT = 40;
const DIRECTION_MARGIN = 5;
const LOCAL_DAY = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit',
});

const day = (date) => Date.parse(`${date}T00:00:00Z`) / DAY_MS;
const iso = (value) => new Date(value * DAY_MS).toISOString().slice(0, 10);

function summarize(start, end, moods, screenings) {
  const ratings = moods.filter((row) => row.day >= start && row.day <= end);
  const mood = ratings.length >= Math.ceil((end - start + 1) * .4)
    ? ratings.reduce((sum, row) => sum + row.rating, 0) / ratings.length : null;
  // Carry a recent screening to the end of a period for at most seven days.
  const epds = screenings.find((row) => row.day <= end && row.day >= end - 7);
  const measures = [];
  let coverage = 0;
  let points = 0;
  if (mood !== null) {
    measures.push('mood');
    coverage += MOOD_WEIGHT;
    points += MOOD_WEIGHT * (mood - 1) / 4;
  }
  if (epds) {
    measures.push('epds');
    coverage += EPDS_WEIGHT;
    points += EPDS_WEIGHT * (30 - epds.score) / 30;
  }
  return {
    bar: {
      start_date: iso(start),
      end_date: iso(end),
      score: coverage ? Math.round(1000 * points / coverage) / 10 : null,
      coverage,
      measures,
      mood_days: ratings.length,
    },
    epds,
  };
}

function direction(previous, current) {
  if (previous.bar.score === null || current.bar.score === null
    || previous.bar.coverage !== current.bar.coverage
    || previous.epds?.version !== current.epds?.version
    || previous.epds?.scoring_version !== current.epds?.scoring_version
    || previous.epds?.language !== current.epds?.language
    || (current.bar.coverage === EPDS_WEIGHT && previous.epds.date === current.epds.date)) {
    return 'insufficient_data';
  }
  const difference = Math.round((current.bar.score - previous.bar.score) * 10);
  if (difference >= DIRECTION_MARGIN * 10) return 'improving';
  if (difference <= -DIRECTION_MARGIN * 10) return 'declining';
  return 'similar';
}

function buildTrends({ asOf, moodRows, screeningRows }) {
  const end = day(asOf);
  const moods = moodRows.map((row) => ({ day: day(row.date), rating: row.mood_rating }));
  const screenings = screeningRows.map((row) => ({ ...row, day: day(row.date) }))
    .sort((a, b) => b.day - a.day);
  const periods = Object.fromEntries(Object.entries(PERIODS).map(([type, days]) => {
    const bars = Array.from({ length: BARS }, (_, index) => {
      const windowEnd = end - (BARS - 1 - index) * days;
      return summarize(windowEnd - days + 1, windowEnd, moods, screenings);
    });
    return [type, {
      direction: direction(bars.at(-2), bars.at(-1)),
      bars: bars.map(({ bar }) => bar),
    }];
  }));
  return { method_version: 'guardian-wellbeing-v1', as_of: asOf, periods };
}

async function getTrends(guardianId, role, now = new Date()) {
  if (role !== 'guardian') throw new AppError('Only linked guardians can view these reports.', 403);
  const asOf = LOCAL_DAY.format(now);
  return db.withTransaction(async (client) => {
    // Keep the link and consent valid through both health-data reads.
    const { rows: links } = await client.query(`
      SELECT gl.mother_id FROM guardian_links gl
      JOIN users g ON g.id = gl.guardian_id AND g.role = 'guardian' AND g.is_active
      JOIN users m ON m.id = gl.mother_id AND m.role = 'mother' AND m.is_active
      JOIN onboarding_data o ON o.user_id = m.id AND o.consent_tier1 AND o.consent_tier2
      WHERE gl.guardian_id = $1 AND gl.status = 'active'
      ORDER BY gl.accepted_at DESC LIMIT 1 FOR SHARE OF gl, g, m, o`, [guardianId]);
    if (!links[0]) throw new AppError('An active guardian link and sharing permission are required.', 403);
    const motherId = links[0].mother_id;
    const dates = [motherId, asOf, iso(day(asOf) - BARS * PERIODS.fortnightly + 1)];
    const { rows: moodRows } = await client.query(`
      SELECT entry_date::text AS date, mood_rating FROM mood_checkins
      WHERE mother_id = $1 AND entry_date BETWEEN $3::date AND $2::date`, dates);
    const { rows: screeningRows } = await client.query(`
      SELECT DISTINCT ON (local_date) local_date::text AS date,
        total_score AS score, instrument_version AS version, scoring_version, language
      FROM (
        SELECT (completed_at AT TIME ZONE 'Asia/Karachi')::date AS local_date,
          total_score, instrument_version, scoring_version, language, completed_at, id
        FROM screening_assessments
        WHERE mother_id = $1 AND instrument_type = 'epds' AND status = 'completed'
          AND total_score BETWEEN 0 AND 30
          AND completed_at >= (($2::date - 7)::timestamp AT TIME ZONE 'Asia/Karachi')
          AND completed_at <= $3::timestamptz
      ) AS scores
      ORDER BY local_date DESC, completed_at DESC, id DESC`, [motherId, dates[2], now]);
    return buildTrends({ asOf, moodRows, screeningRows });
  });
}

module.exports = { buildTrends, getTrends };
