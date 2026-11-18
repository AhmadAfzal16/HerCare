const test = require('node:test');
const assert = require('node:assert/strict');
const { WEIGHTS, buildM4Reports } = require('../src/modules/risk/m4.score');

const asOf = '2026-11-13';
const dates = (start, length) => Array.from({ length }, (_, offset) => `2026-11-${String(start + offset).padStart(2, '0')}`);
const screens = (scores) => scores.map(([date, score]) => ({ date, score, instrument: 'epds', version: '1', language: 'ur' }));
const pair = screens([['2026-11-06', 6], [asOf, 6]]);
const rising = screens([['2026-10-30', 4], ['2026-11-06', 7], [asOf, 10]]);
const group = (report, key) => report.groups.find((entry) => entry.key === key);
const build = (data) => buildM4Reports({ asOf, ...data });

test('four report periods recompute evidence and preserve partial coverage', () => {
  assert.equal(Object.values(WEIGHTS).reduce((sum, value) => sum + value, 0), 100);
  const result = build({
    screenings: pair,
    moods: dates(1, 13).map((date) => ({ date, mood_rating: date < '2026-11-07' ? 4 : 2, energy_level: null })),
  });
  assert.deepEqual(result.reports.map((report) => [report.period, report.window_days, report.start_date, report.end_date]), [
    ['daily', 1, '2026-11-13', asOf], ['weekly', 7, '2026-11-07', asOf],
    ['fortnightly', 14, '2026-10-31', asOf], ['overall', 30, '2026-10-15', asOf],
  ]);
  const [daily, weekly, fortnightly] = result.reports;
  assert.equal(daily.previous_start_date, '2026-11-06');
  assert.equal(weekly.previous_end_date, '2026-11-06');
  assert.equal(weekly.findings.includes('mood_worsening'), true);
  assert.equal(group(weekly, 'mood_energy').coverage, 70);
  assert.equal(group(fortnightly, 'mood_energy').coverage, 45.5);
  assert.ok(weekly.coverage < 100 && weekly.score_max_with_missing >= weekly.score);
  assert.deepEqual(result.forecast, { status: 'not_trained', probability: null, horizon_days: 14 });
});

test('persistent EPDS rise warns before the elevated threshold', () => {
  const [daily, weekly, fortnightly, overall] = build({ screenings: rising }).reports;
  for (const report of [daily, weekly, fortnightly, overall]) {
    assert.equal(report.screenings.epds.latest_score, 10);
    assert.equal(report.screenings.epds.change, 3);
    assert.equal(report.screenings.epds.elevated, false);
    assert.equal(report.direction, 'worsening');
    assert.equal(report.level, 'early_warning');
    assert.equal(report.next_step, 'screening_follow_up');
  }
  assert.equal(group(weekly, 'epds').points, 15.2);
  assert.equal(weekly.score, group(weekly, 'epds').points);
  assert.equal(weekly.coverage, 35);
});

test('improving screening and worsening sleep stay visible together', () => {
  const previous = dates(1, 6).map((date) => ({ date, sleep_minutes: 410, quality: 4, awakenings: 1 }));
  const current = dates(7, 7).map((date) => ({ date, sleep_minutes: 300, quality: 2, awakenings: 50 }));
  const moods = dates(1, 13).map((date) => ({ date, mood_rating: date < '2026-11-07' ? 4 : 2 }));
  const [, report] = build({
    screenings: screens([['2026-11-06', 12], [asOf, 8]]), sleeps: [...previous, ...current], moods,
  }).reports;
  assert.equal(report.direction, 'improving');
  assert.equal(report.level, 'monitor');
  assert.equal(report.next_step, 'sleep_support');
  assert.ok(report.findings.includes('sleep_worsening'));
  assert.ok(report.findings.includes('epds_falling'));
  assert.ok(report.findings.includes('supporting_changes'));
  assert.equal(group(report, 'sleep').metrics.find((entry) => entry.key === 'awakenings').current, 50);
});

test('same-day repeats, language switches, invalid and future rows cannot create a trend', () => {
  const assessments = screens([['2026-10-20', 2], ['2026-11-06', 4], [asOf, 5], [asOf, 7],
    ['2026-11-14', 17], ['2026-11-31', 18]]);
  assessments[1].language = 'en';
  const { reports: [report] } = build({ screenings: assessments });
  assert.equal(report.screenings.epds.latest_score, 7);
  assert.equal(report.score, null);
  assert.equal(report.level, 'insufficient_data');
  assert.equal(report.coverage, 22.8);
  assert.throws(() => buildM4Reports({ asOf: '2026-02-30' }), /calendar day/);
});

test('safety and elevated screening each take priority when the numeric score is unavailable', () => {
  const assessments = screens([[asOf, 18]]);
  const [elevated] = build({ screenings: assessments }).reports;
  assert.equal(elevated.level, 'screening_elevated');
  assert.equal(elevated.next_step, 'professional_support');
  assert.equal(elevated.score, null);
  const [safety] = build({ screenings: assessments, safetyPriority: true }).reports;
  assert.equal(safety.level, 'safety_priority');
  assert.equal(safety.next_step, 'immediate_help');
});

test('same-day text repetition and duplicate sleep quality cannot inflate evidence', () => {
  const sleeps = [{ date: asOf, quality: 4 }];
  const moods = [{ date: asOf, mood_rating: 4, sleep_quality: 1 }];
  const texts = [{ date: asOf, distress: true, source: 'journal' }, { date: asOf, distress: true, source: 'hum_raaz' }];
  const [first] = build({ screenings: pair, sleeps, moods, texts }).reports;
  const [repeated] = build({ screenings: pair, sleeps, moods, texts: [...texts, { date: '2026-11-12', distress: true, source: 'hum_raaz' }] }).reports;
  assert.equal(group(first, 'sleep').metrics.find((entry) => entry.key === 'sleep_quality').current, 4);
  assert.equal(group(first, 'text').points, null);
  assert.equal(group(repeated, 'text').points, 3.3);
  assert.ok(repeated.findings.includes('recurring_text_distress'));
});

test('context preserves distinct fields and answers and never copies identifiers', () => {
  const { context, reports: [, report] } = build({
    screenings: pair,
    profile: { age: 27, parity: 2, name: 'private', city: 'private', income_range: 'unknown', baby_gender: 'female' },
    modelContext: { updated_date: asOf, number_of_children: 1, basic_needs_affordable: false, mother_in_law_relationship: 'poor' },
    checkins: [{ date: asOf, financial_strain: 0, support_gap: 2, relationship_strain: null, recovery_difficulty: null }],
    moods: dates(7, 7).map((date) => ({ date, mood_rating: 3, social_support: 2 })),
  });
  assert.equal(context.profile.parity, 2);
  assert.equal(context.model_context.number_of_children, 1);
  assert.ok(!Object.hasOwn(context.profile, 'name') && !Object.hasOwn(context.profile, 'city'));
  const financial = group(report, 'weekly_context').metrics.find((entry) => entry.key === 'financial_strain');
  const relationship = group(report, 'weekly_context').metrics.find((entry) => entry.key === 'relationship_strain');
  assert.equal(financial.source, 'weekly_context');
  assert.equal(financial.current, 0);
  assert.equal(relationship.source, 'mother_in_law_relationship');
  assert.deepEqual(group(report, 'support').metrics.map((entry) => entry.key), ['social_support', 'support_gap']);
  assert.equal(group(report, 'support').points, 2.6);
});

test('optional phone fields require their individual access and never use an incomplete current day', () => {
  const telemetry = dates(1, 13).map((date) => ({
    date,
    usage_access: date !== asOf,
    screen_time_minutes: date === asOf ? 1440 : 200,
    notification_access: false,
    message_notifications: 500,
    distress_notifications: 490,
  }));
  const [report] = build({ screenings: pair, telemetry }).reports;
  const phone = group(report, 'phone');
  assert.equal(phone.points, 0);
  assert.equal(phone.coverage, 12.5);
  assert.equal(phone.metrics.find((entry) => entry.key === 'screen_time_minutes').current, 200);
  assert.equal(phone.metrics.find((entry) => entry.key === 'distress_notifications').current, null);
});
