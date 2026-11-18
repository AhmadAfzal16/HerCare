const METHOD_VERSION = 'm4-monitoring-v1';
const WEIGHTS = Object.freeze({
  epds: 35, phq9: 10, mood_energy: 13, sleep: 15, support: 5, weekly_context: 15, text: 5, phone: 2,
});
const PERIODS = { daily: 1, weekly: 7, fortnightly: 14, overall: 30 };
const SCREENING = {
  epds: { max: 30, elevated: 13, cadence: 7, fullRise: 6 },
  phq9: { max: 27, elevated: 10, cadence: 14, fullRise: 6 },
};
const DAY_MS = 86400000;
const round = (value) => Math.round(value * 10) / 10;
const clip = (value) => Math.max(0, Math.min(1, value));
const mean = (values) => values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
const present = (value) => value !== null && value !== undefined;
const dateFor = (value) => new Date(value * DAY_MS).toISOString().slice(0, 10);

function day(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return NaN;
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) return NaN;
  return parsed.getTime() / DAY_MS;
}

function dated(rows, end) {
  return rows.map((row) => ({ ...row, day: day(row.date) }))
    .filter((row) => Number.isFinite(row.day) && row.day <= end && row.day >= end - 89);
}

function number(value, min, max) {
  if (typeof value !== 'number' && (typeof value !== 'string' || !value.trim())) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= min && parsed <= max ? parsed : null;
}

function inWindow(rows, end, days) {
  return rows.filter((row) => row.day > end - days && row.day <= end);
}

function oncePerDay(rows) {
  return [...new Map(rows.map((row) => [row.day, row])).values()];
}

function series(rows, read) {
  return oncePerDay(rows).map(read).filter(present);
}

function metric(key, current, previous, concern, currentDays, previousDays, coverage = 1) {
  return { key, current, previous, concern, current_days: currentDays, previous_days: previousDays, coverage: concern === null ? 0 : coverage };
}

function group(key, parts) {
  const weight = WEIGHTS[key];
  const covered = parts.filter((part) => part.value !== null);
  return {
    key,
    weight,
    points: covered.length ? round(covered.reduce((sum, part) => sum + part.share * part.value * weight, 0)) : null,
    coverage: round(100 * covered.reduce((sum, part) => sum + part.share * (part.coverage ?? 1), 0)),
    metrics: parts.flatMap((part) => part.metrics ?? []),
  };
}

function screeningGroup(rows, instrument, end) {
  const config = SCREENING[instrument];
  const eligible = oncePerDay(rows.filter((row) => row.instrument === instrument && row.version && row.language
    && Number.isInteger(number(row.score, 0, config.max))))
    .sort((left, right) => right.day - left.day);
  const latest = eligible[0];
  const compatible = latest ? eligible.filter((row) => row.version === latest.version && row.language === latest.language) : [];
  const previousFor = (current) => compatible
    .filter((row) => Math.abs(current.day - row.day - config.cadence) <= 3)
    .sort((left, right) => Math.abs(current.day - left.day - config.cadence)
      - Math.abs(current.day - right.day - config.cadence) || right.day - left.day)[0];
  const previous = latest && previousFor(latest);
  const third = previous && previousFor(previous);
  const fresh = !!latest && end - latest.day <= config.cadence;
  const latestScore = latest ? Number(latest.score) : null;
  const previousScore = previous ? Number(previous.score) : null;
  const change = fresh && previous ? latestScore - previousScore : null;
  const priorChange = third ? previousScore - Number(third.score) : null;
  const rise = change === null ? null : clip((change + (change > 0 && priorChange > 0 ? Math.min(priorChange, 4) * .25 : 0)) / config.fullRise);
  return {
    details: {
      latest_score: latestScore, latest_date: latest?.date ?? null,
      previous_score: previousScore, previous_date: previous?.date ?? null,
      change, comparable: change !== null, fresh,
      elevated: fresh && latestScore >= config.elevated,
      persistent_rise: change > 0 && priorChange > 0,
      history: compatible.slice(0, 3).reverse().map((row) => ({ date: row.date, score: Number(row.score) })),
    },
    group: group(instrument, [
      { share: .65, value: fresh ? latestScore / config.max : null },
      { share: .35, value: rise },
    ]),
  };
}

function minDays(days) {
  return Math.max(1, Math.ceil(days * .4));
}

function compareMetric(key, currentRows, previousRows, read, currentMin, previousMin, convert, levelFraction = 1) {
  const current = series(currentRows, read);
  const previous = series(previousRows, read);
  const c = current.length >= currentMin ? mean(current) : null;
  const p = previous.length >= previousMin ? mean(previous) : null;
  return metric(key, c === null ? null : round(c), p === null ? null : round(p),
    c === null ? null : convert(c, p), current.length, previous.length, p === null ? levelFraction : 1);
}

const rating = (field) => (row) => number(row[field], 1, 5);
const ordinal = (field) => (row) => number(row[field], 0, 3);

function ratingConcern(current, previous) {
  const currentLevel = (5 - current) / 4;
  const decline = previous === null ? 0 : clip((previous - current) / 2);
  return .65 * currentLevel + .35 * decline;
}

function part(share, ...metrics) {
  return {
    share,
    value: metrics.some((entry) => entry.concern !== null)
      ? mean(metrics.map((entry) => entry.concern ?? 0)) : null,
    coverage: mean(metrics.map((entry) => entry.coverage)),
    metrics,
  };
}

function sleepGroup(data, end, days, previousDays) {
  // A night can have a diary quality and a mood-form quality. Prefer the diary.
  const nights = new Map(oncePerDay(data.sleeps).map((row) => [row.day, row]));
  for (const row of oncePerDay(data.moods)) {
    const quality = rating('sleep_quality')(row);
    if (quality === null || rating('quality')(nights.get(row.day) ?? {}) !== null) continue;
    nights.set(row.day, { ...nights.get(row.day), date: row.date, day: row.day, quality });
  }
  const current = inWindow([...nights.values()], end, days);
  const previous = inWindow([...nights.values()], end - days, previousDays);
  const compare = (key, read, convert, levelFraction) => compareMetric(key, current, previous, read,
    minDays(days), minDays(previousDays), convert, levelFraction);
  const duration = compare('sleep_minutes', (row) => number(row.sleep_minutes, 0, 1440),
    (c, p) => .6 * clip((420 - c) / 240) + .4 * (p === null ? 0 : clip((p - c) / 120)), .6);
  const quality = compare('sleep_quality', rating('quality'), ratingConcern, .65);
  const awakenings = compare('awakenings', (row) => number(row.awakenings, 0, 50),
    (c, p) => .6 * clip(c / 6) + .4 * (p === null ? 0 : clip((c - p) / 3)), .6);
  const awake = compare('awake_minutes', (row) => number(row.awake_minutes, 0, 1439),
    (c, p) => .6 * clip(c / 180) + .4 * (p === null ? 0 : clip((c - p) / 60)), .6);
  const offsets = new Set([...current, ...previous].map((row) => number(row.timezone_offset_minutes, -840, 840)).filter(present));
  const timing = ['bedtime_minute', 'wake_minute'].map((field) => offsets.size > 1
    ? metric(`${field}_variation`, null, null, null, 0, 0)
    : clockMetric(field, current, previous, minDays(days), minDays(previousDays)));
  return group('sleep', [part(.3, duration), part(.3, quality), part(.2, awakenings, awake), part(.2, ...timing)]);
}

function clockMetric(field, currentRows, previousRows, currentMin, previousMin) {
  const read = (row) => number(row[field], 0, 1439);
  const c = series(currentRows, read);
  const p = series(previousRows, read);
  const angle = (minute) => minute * Math.PI / 720;
  const distance = (a, b) => Math.min(Math.abs(a - b), 1440 - Math.abs(a - b));
  const centre = (values) => {
    const x = mean(values.map((minute) => Math.cos(angle(minute))));
    const y = mean(values.map((minute) => Math.sin(angle(minute))));
    return Math.hypot(x, y) < 1e-9 ? null : (Math.atan2(y, x) * 720 / Math.PI + 1440) % 1440;
  };
  const priorCentre = p.length >= Math.max(previousMin, 2) ? centre(p) : null;
  if (c.length < currentMin || priorCentre === null) return metric(`${field}_variation`, null, null, null, c.length, p.length);
  const currentVariation = mean(c.map((value) => distance(value, priorCentre)));
  const priorVariation = mean(p.map((value) => distance(value, priorCentre)));
  return metric(`${field}_variation`, round(currentVariation), round(priorVariation),
    clip((currentVariation - priorVariation) / 120), c.length, p.length);
}

function recentCheckins(rows, end, days) {
  // The questionnaire covers one week. Extra submissions within that week
  // update the estimate instead of making a heavily reported week count twice.
  const result = [];
  for (let offset = 0; offset < days; offset += 7) {
    const latest = inWindow(rows, end - offset, Math.min(7, days - offset))
      .sort((left, right) => right.day - left.day)[0];
    if (latest) result.push(latest);
  }
  return result;
}

function contextMetrics(data, end, days) {
  const window = Math.max(7, days);
  const current = recentCheckins(data.checkins, end, window);
  const previous = recentCheckins(data.checkins, end - window, window);
  return ['financial_strain', 'relationship_strain', 'support_gap', 'recovery_difficulty'].map((key) => {
    const entry = compareMetric(key, current, previous, ordinal(key), 1, 1,
      (c, p) => .85 * c / 3 + .15 * (p === null ? 0 : clip((c - p) / 3)), .85);
    entry.source = 'weekly_context';
    if (entry.concern !== null) return entry;
    // A fresh, explicit profile response is a fallback for this domain only.
    // A questionnaire answer takes priority and only comparable check-ins
    // contribute to change. Unknown or not applicable has no numeric value.
    const updated = day(data.modelContext.updated_date);
    const affordable = data.modelContext.basic_needs_affordable;
    if (!(updated <= end && updated > end - window)) return entry;
    if (key === 'financial_strain' && typeof affordable === 'boolean') {
      return { ...metric(key, affordable ? 0 : 3, null, affordable ? 0 : .85, 1, 0, .85), source: 'basic_needs_affordable' };
    }
    const quality = { poor: 2, moderate: 1, good: 0 };
    const relationship = data.modelContext.mother_in_law_relationship;
    if (key === 'relationship_strain' && Object.hasOwn(quality, relationship)) {
      const concern = quality[relationship];
      return { ...metric(key, concern, null, .85 * concern / 3, 1, 0, .85), source: 'mother_in_law_relationship' };
    }
    return entry;
  });
}

function textGroup(rows, end, days) {
  const window = Math.max(7, days);
  const counts = (until) => {
    const byDay = new Map();
    for (const row of inWindow(rows, until, window)) {
      if (!['journal', 'hum_raaz'].includes(row.source) || typeof row.distress !== 'boolean') continue;
      byDay.set(row.day, byDay.get(row.day) || row.distress);
    }
    return { total: byDay.size, flagged: [...byDay.values()].filter(Boolean).length };
  };
  const current = counts(end);
  const previous = counts(end - window);
  const concern = current.total < 2 ? null : current.flagged < 2 ? 0 : clip(current.flagged / Math.ceil(window * 3 / 7));
  return group('text', [part(1, metric('distress_days', current.flagged, previous.flagged, concern, current.total, previous.total))]);
}

function phoneGroup(rows, end, days, previousDays) {
  // Skip the reporting day because its upload can still change. Older
  // snapshots are observations, not proof of continuous device monitoring.
  const current = inWindow(rows, end - 1, days);
  const previous = inWindow(rows, end - days - 1, previousDays);
  const usageFields = {
    screen_time_minutes: [1440, 180], social_minutes: [1440, 120], late_night_minutes: [480, 60], app_switches: [20000, 60],
  };
  const usage = Object.entries(usageFields).map(([field, [max, scale]]) =>
    compareMetric(field, current, previous, (row) => row.usage_access === true ? number(row[field], 0, max) : null,
      minDays(days), minDays(previousDays), (c, p) => p === null ? null : clip((c - p) / scale)));
  const notifications = ['negative_notifications', 'distress_notifications', 'abuse_notifications'].map((field) => {
    const ratio = (entries) => {
      let count = 0;
      let flagged = 0;
      let daysCovered = 0;
      for (const row of oncePerDay(entries)) {
        const messages = row.notification_access === true ? number(row.message_notifications, 1, 10000) : null;
        const flags = messages === null ? null : number(row[field], 0, messages);
        if (flags === null) continue;
        count += messages;
        flagged += flags;
        daysCovered += 1;
      }
      return { value: count >= 5 ? flagged / count : null, days: daysCovered };
    };
    const c = ratio(current);
    const p = ratio(previous);
    const comparable = c.value !== null && p.value !== null
      && c.days >= minDays(days) && p.days >= minDays(previousDays);
    return metric(field, c.value === null ? null : round(100 * c.value), p.value === null ? null : round(100 * p.value),
      comparable ? clip((c.value - p.value) / .4) : null, c.days, p.days);
  });
  const counts = ['notifications_seen', 'message_notifications'].map((field) =>
    compareMetric(field, current, previous, (row) => row.notification_access === true
      ? number(row[field], 0, 10000) : null, minDays(days), minDays(previousDays), () => null));
  const result = group('phone', [part(.5, ...usage), part(.5, ...notifications)]);
  result.metrics.push(...counts);
  return result;
}

function readContext(profile, modelContext) {
  const fields = ['age', 'months_since_birth', 'education_level', 'delivery_method', 'parity', 'baby_gender',
    'has_preeclampsia', 'has_postpartum_hemorrhage', 'has_preterm_birth', 'has_gestational_diabetes',
    'household_type', 'income_range', 'primary_support'];
  const categorical = ['education_level', 'delivery_method', 'baby_gender', 'household_type', 'income_range', 'primary_support'];
  return {
    profile: Object.fromEntries(fields.map((field) => [field, field.startsWith('has_')
      ? typeof profile[field] === 'boolean' ? profile[field] : null
      : categorical.includes(field)
        ? typeof profile[field] === 'string' && profile[field].length <= 80 ? profile[field] : null
        : number(profile[field], field === 'age' ? 15 : 0, field === 'age' ? 55 : field === 'parity' ? 30 : 12)])),
    model_context: {
      number_of_children: number(modelContext.number_of_children, 0, 20),
      basic_needs_affordable: typeof modelContext.basic_needs_affordable === 'boolean' ? modelContext.basic_needs_affordable : null,
      mother_in_law_relationship: ['poor', 'moderate', 'good'].includes(modelContext.mother_in_law_relationship)
        ? modelContext.mother_in_law_relationship : null,
      updated_date: Number.isFinite(day(modelContext.updated_date)) ? modelContext.updated_date : null,
    },
  };
}

function symptomDirection(screenings) {
  const changes = Object.values(screenings).map((row) => row.change).filter(present);
  const up = changes.some((change) => change > 0);
  const down = changes.some((change) => change < 0);
  if (up && down) return 'mixed';
  if (up) return 'worsening';
  if (down) return 'improving';
  return changes.length ? 'unchanged' : 'insufficient_data';
}

function report(data, end, period, days, screen, safetyPriority) {
  const previousDays = days === 1 ? 7 : days;
  const current = inWindow(data.moods, end, days);
  const previous = inWindow(data.moods, end - days, previousDays);
  const compareRating = (key) => compareMetric(key, current, previous, rating(key), minDays(days), minDays(previousDays), ratingConcern, .65);
  const mood = compareRating('mood_rating');
  const energy = compareRating('energy_level');
  const support = compareRating('social_support');
  support.source = 'daily_checkins';
  const [financial, relationship, supportGap, recovery] = contextMetrics(data, end, days);
  const sleep = sleepGroup(data, end, days, previousDays);
  const text = textGroup(data.texts, end, days);
  const phone = phoneGroup(data.telemetry, end, days, previousDays);
  const groups = [screen.epds.group, screen.phq9.group, group('mood_energy', [part(.7, mood), part(.3, energy)]), sleep,
    group('support', [part(.5, support), part(.5, supportGap)]),
    group('weekly_context', [part(1 / 3, financial), part(1 / 3, relationship), part(1 / 3, recovery)]), text, phone];
  const screenings = { epds: screen.epds.details, phq9: screen.phq9.details };
  const coverage = round(groups.reduce((sum, item) => sum + item.coverage * item.weight / 100, 0));
  const score = screenings.epds.comparable ? Math.min(100, round(groups.reduce((sum, item) => sum + (item.points ?? 0), 0))) : null;
  const sleepWorsening = sleep.metrics.some((entry) => {
    if (entry.current === null || entry.previous === null) return false;
    const change = entry.current - entry.previous;
    if (entry.key === 'sleep_minutes') return change <= -45;
    if (entry.key === 'sleep_quality') return change <= -.75;
    if (entry.key === 'awakenings') return change >= 1;
    return change >= 30;
  });
  const lowerRating = (entry) => entry.current !== null && entry.previous !== null && entry.current - entry.previous <= -.75;
  const findings = [
    screenings.epds.change > 0 && 'epds_rising', screenings.epds.change < 0 && 'epds_falling',
    screenings.epds.persistent_rise && 'epds_persistent_rise',
    screenings.phq9.change > 0 && 'phq9_rising', screenings.phq9.change < 0 && 'phq9_falling',
    (screenings.epds.elevated || screenings.phq9.elevated) && 'screening_elevated',
    lowerRating(mood) && 'mood_worsening', lowerRating(energy) && 'energy_worsening', sleepWorsening && 'sleep_worsening',
    lowerRating(support) && 'support_worsening',
    ...[financial, relationship, supportGap, recovery].map((entry) => entry.current >= 2 && entry.key),
    text.metrics[0].concern > 0 && 'recurring_text_distress',
    phone.points > 0 && 'phone_change',
    !screenings.epds.comparable && 'insufficient_screening_history',
  ].filter(Boolean);
  const dailyDomains = [
    findings.includes('mood_worsening') || findings.includes('energy_worsening'),
    sleepWorsening,
    findings.includes('support_worsening')
      || (supportGap.current !== null && supportGap.previous !== null && supportGap.current - supportGap.previous >= 1),
  ].filter(Boolean).length;
  if (dailyDomains >= 2) findings.push('supporting_changes');
  const earlyWarning = screenings.epds.comparable && (screenings.epds.persistent_rise
    || screenings.epds.change >= 4 || (screenings.epds.change >= 2 && dailyDomains >= 1)
    || (screenings.phq9.change >= 3 && dailyDomains >= 2));
  const elevated = findings.includes('screening_elevated');
  let level = 'monitor';
  let nextStep = 'continue_checkins';
  if (safetyPriority) [level, nextStep] = ['safety_priority', 'immediate_help'];
  else if (elevated) [level, nextStep] = ['screening_elevated', 'professional_support'];
  else if (earlyWarning) [level, nextStep] = ['early_warning', 'screening_follow_up'];
  else {
    if (score === null) level = 'insufficient_data';
    if (sleepWorsening) nextStep = 'sleep_support';
    else if (findings.some((item) => ['financial_strain', 'relationship_strain', 'support_gap', 'support_worsening', 'recovery_difficulty'].includes(item))) nextStep = 'practical_support';
    else if (findings.some((item) => ['mood_worsening', 'recurring_text_distress'].includes(item))) nextStep = 'mood_support';
  }
  return {
    period, window_days: days, score, coverage, start_date: dateFor(end - days + 1), end_date: dateFor(end),
    previous_start_date: dateFor(end - days - previousDays + 1), previous_end_date: dateFor(end - days),
    score_max_with_missing: score === null ? null : Math.min(100, round(score + 100 - coverage)),
    level, groups, screenings, direction: symptomDirection(screenings), findings, next_step: nextStep,
  };
}

function buildM4Reports({
  asOf, screenings = [], moods = [], sleeps = [], telemetry = [], texts = [], checkins = [],
  profile = {}, modelContext = {}, safetyPriority = false,
}) {
  const end = day(asOf);
  if (!Number.isFinite(end)) throw new TypeError('asOf must be a valid local calendar day');
  const screens = dated(screenings, end);
  const screen = Object.fromEntries(Object.keys(SCREENING).map((key) => [key, screeningGroup(screens, key, end)]));
  const safety = safetyPriority === true || screens.some((row) => row.day === end && row.safety_positive === true);
  const data = Object.fromEntries(Object.entries({ moods, sleeps, telemetry, texts, checkins })
    .map(([key, rows]) => [key, dated(rows, end)]));
  data.modelContext = modelContext;
  return {
    as_of: asOf,
    method_version: METHOD_VERSION,
    safety_priority: safety,
    forecast: { status: 'not_trained', probability: null, horizon_days: 14 },
    reports: Object.entries(PERIODS).map(([period, days]) => report(data, end, period, days, screen, safety)),
    context: readContext(profile, modelContext),
  };
}

module.exports = { METHOD_VERSION, WEIGHTS, buildM4Reports };
