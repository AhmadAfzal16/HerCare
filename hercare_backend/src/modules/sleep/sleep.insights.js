// Descriptive within-person observations. Never diagnosis, causality, ML labels
// or an automatic guardian-alert trigger. Bounds/coverage are project rules.
const DAY = 86400000;
const POLICY = Object.freeze({ version: 'm8-observed-v1', paired_days: 14, group_days: 4,
  freshness_days: 2, short_minutes: 360, drop_minutes: 60, clock_sd_minutes: 90 });
const number = (value, low, high) => {
  if (value === null || value === undefined || value === '' || !['string', 'number'].includes(typeof value)) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= low && parsed <= high ? parsed : null;
};
const mean = (values) => values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
const round = (value, places = 1) => value === null ? null : Number(value.toFixed(places));
const dateMs = (date) => typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date)
  && Number.isFinite(Date.parse(date)) && new Date(date).toISOString().slice(0, 10) === date ? Date.parse(date) : null;
const dayKey = (value) => new Date(value).toISOString().slice(0, 10);

function clean(rows, dateField, asOf, map) {
  const unique = new Map();
  for (const row of rows.slice(0, 120)) {
    const time = dateMs(row[dateField]);
    if (time === null || time > asOf || time < asOf - 59 * DAY) continue;
    const value = map(row);
    if (value !== null && !unique.has(time)) unique.set(time, { ...value, date: row[dateField], time });
  }
  return [...unique.values()].sort((a, b) => a.time - b.time);
}
function ranks(values) {
  const ordered = values.map((value, index) => ({ value, index })).sort((a, b) => a.value - b.value);
  const result = new Array(values.length);
  for (let start = 0; start < ordered.length;) {
    let end = start + 1;
    while (end < ordered.length && ordered[end].value === ordered[start].value) end++;
    for (let index = start; index < end; index++) result[ordered[index].index] = (start + 1 + end) / 2;
    start = end;
  }
  return result;
}
function spearman(x, y) {
  if (x.length !== y.length || x.length < 2) return null;
  const a = ranks(x), b = ranks(y), am = mean(a), bm = mean(b);
  const aa = a.reduce((sum, value) => sum + (value - am) ** 2, 0);
  const bb = b.reduce((sum, value) => sum + (value - bm) ** 2, 0);
  if (!aa || !bb) return null;
  return Math.max(-1, Math.min(1, a.reduce((sum, value, i) => sum + (value - am) * (b[i] - bm), 0) / Math.sqrt(aa * bb)));
}
function clockSpread(rows, field) {
  const values = rows.map((row) => {
    const timestamp = Date.parse(row[field]);
    return Number.isFinite(timestamp) && row.offset !== null
      ? ((timestamp / 60000 - row.offset) % 1440 + 1440) % 1440 : null;
  }).filter((value) => value !== null);
  if (values.length < 7 || new Set(rows.map((row) => row.offset)).size !== 1) return null;
  const angles = values.map((value) => value * 2 * Math.PI / 1440);
  const length = Math.hypot(mean(angles.map(Math.sin)), mean(angles.map(Math.cos)));
  return round(Math.min(720, Math.sqrt(-2 * Math.log(Math.max(Math.min(length, 1), 1e-12))) * 1440 / (2 * Math.PI)));
}
function window(rows, start, end) {
  const selected = rows.filter((row) => row.time >= start && row.time <= end);
  const field = (key) => selected.map((row) => row[key]).filter((value) => value !== null);
  return { nights: selected.length, average_minutes: round(mean(field('minutes'))),
    average_quality: round(mean(field('quality'))), quality_nights: field('quality').length,
    average_awakenings: round(mean(field('awakenings'))), awakening_nights: field('awakenings').length,
    short_nights: selected.filter((row) => row.minutes < POLICY.short_minutes).length };
}

function buildInsights({ sleep = [], moods = [], telemetry = [], asOf, safetyPriority = false, telemetryConsent = false }) {
  const anchor = dateMs(asOf);
  if (anchor === null) throw new TypeError('A valid local as-of date is required');
  const nights = clean(sleep, 'sleep_date', anchor, (row) => {
    const minutes = number(row.sleep_minutes, 1, 1440);
    return minutes === null ? null : { minutes, quality: number(row.quality, 1, 5),
      awakenings: number(row.awakenings, 0, 50), bedtime: row.bedtime, wake_time: row.wake_time,
      offset: number(row.timezone_offset_minutes, -840, 840) };
  });
  const moodDays = clean(moods, 'entry_date', anchor, (row) => {
    const mood = number(row.mood_rating, 1, 5);
    return mood === null ? null : { mood };
  });
  const latest = nights.at(-1)?.date || null;
  const stale = latest === null || (anchor - dateMs(latest)) / DAY > POLICY.freshness_days;
  const windows = [7, 14, 30].map((days) => {
    const start = anchor - (days - 1) * DAY;
    const current = window(nights, start, anchor);
    const previous = window(nights, start - days * DAY, start - DAY);
    const minimum = days === 7 ? 5 : days === 14 ? 10 : 14;
    const enough = !stale && current.nights >= minimum && previous.nights >= minimum;
    const change = enough ? round(current.average_minutes - previous.average_minutes) : null;
    return { days, start: dayKey(start), end: asOf, minimum_nights: minimum, current, previous,
      change_minutes: change, direction: !enough ? 'insufficient_data'
        : change <= -POLICY.drop_minutes ? 'less_recorded_sleep'
          : change >= POLICY.drop_minutes ? 'more_recorded_sleep' : 'similar_recorded_sleep' };
  });
  const recent = nights.filter((row) => row.time >= anchor - 29 * DAY);
  const moodsByDate = new Map(moodDays.map((row) => [row.date, row.mood]));
  const pairs = recent.filter((row) => moodsByDate.has(row.date)).map((row) => ({ ...row, mood: moodsByDate.get(row.date) }));
  const latestPair = pairs.at(-1)?.date || null;
  const pairStale = stale || latestPair === null || (anchor - dateMs(latestPair)) / DAY > POLICY.freshness_days;
  const rho = pairs.length >= POLICY.paired_days && !pairStale ? spearman(pairs.map((row) => row.minutes), pairs.map((row) => row.mood)) : null;
  const group = (short) => {
    const selected = pairs.filter((row) => (row.minutes < POLICY.short_minutes) === short);
    return { days: selected.length, average_mood: !pairStale && pairs.length >= POLICY.paired_days && selected.length >= POLICY.group_days
      ? round(mean(selected.map((row) => row.mood)), 2) : null };
  };
  const correlation = { status: pairStale && pairs.length ? 'stale' : pairs.length < POLICY.paired_days ? 'insufficient_data' : rho === null ? 'no_variation' : 'available',
    latest_paired_date: latestPair,
    paired_days: pairs.length, minimum_days: POLICY.paired_days, window_days: 30, coefficient: round(rho, 3),
    direction: rho === null ? 'insufficient_data' : rho >= .3 ? 'positive' : rho <= -.3 ? 'negative' : 'no_clear_pattern',
    under_six_hours: group(true), six_hours_or_more: group(false), causal_claim: false };
  const bedtimeSd = clockSpread(recent, 'bedtime'), wakeSd = clockSpread(recent, 'wake_time');
  const patterns = [];
  if (!stale && windows[0].current.nights >= 5 && windows[0].current.short_nights >= 3) patterns.push('repeated_short_sleep');
  if (windows.some((value) => value.direction === 'less_recorded_sleep')) patterns.push('less_sleep_than_previous_period');
  if (!stale && (bedtimeSd > POLICY.clock_sd_minutes || wakeSd > POLICY.clock_sd_minutes)) patterns.push('variable_sleep_timing');
  const digital = clean(telemetryConsent ? telemetry : [], 'local_date', anchor, (row) => {
    if (row.usage_access !== true) return null;
    const screen = number(row.screen_time_minutes, 0, 1440), social = number(row.social_minutes, 0, 1440), late = number(row.late_night_minutes, 0, 480);
    return screen === null || social === null || late === null ? null : { screen, social, late };
  }).filter((row) => row.time >= anchor - 6 * DAY);
  const latestDigital = digital.at(-1)?.date || null;
  const digitalFresh = latestDigital !== null && (anchor - dateMs(latestDigital)) / DAY <= 2;
  const latestNight = nights.at(-1);
  return { version: POLICY.version, as_of: asOf, source: 'self_reported', latest_sleep_date: latest, stale,
    windows, correlation, patterns,
    timing: { bedtime_sd_minutes: bedtimeSd, wake_sd_minutes: wakeSd,
      timezone_consistent: new Set(recent.map((row) => row.offset)).size <= 1 },
    digital: { sharing_enabled: telemetryConsent, recorded_days: digital.length, latest_date: latestDigital,
      fresh: digitalFresh, average_screen_minutes: round(mean(digital.map((row) => row.screen))),
      average_social_minutes: round(mean(digital.map((row) => row.social))), average_late_night_minutes: round(mean(digital.map((row) => row.late))),
      high_social_days: digital.filter((row) => row.social >= 300).length, late_use_days: digital.filter((row) => row.late >= 30).length },
    safety_priority: safetyPriority,
    activity: safetyPriority ? 'crisis' : patterns.length || (!stale && latestNight?.quality !== null && latestNight?.quality <= 2)
      || (digitalFresh && digital.at(-1).late >= 30) ? 'body_scan' : 'box_breathing',
    interpretation: 'Observed records only; not a diagnosis, cause, recovery percentage or clinical sleep assessment.',
    rules: { ...POLICY, clinically_validated: false } };
}
module.exports = { buildInsights, spearman, POLICY };
