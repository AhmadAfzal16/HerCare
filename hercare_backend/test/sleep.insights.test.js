const test = require('node:test');
const assert = require('node:assert/strict');
const { buildInsights, spearman } = require('../src/modules/sleep/sleep.insights');
const { validateSleep, dashboardQuery } = require('../src/modules/sleep/sleep.logic');
const anchor = '2026-10-11';
const date = (ago) => new Date(Date.parse(anchor) - ago * 86400000).toISOString().slice(0, 10);
const night = (ago, minutes, quality = null) => ({ sleep_date: date(ago), sleep_minutes: String(minutes), quality,
  awakenings: null, timezone_offset_minutes: 0, bedtime: `${date(ago)}T00:05:00Z`, wake_time: `${date(ago)}T07:00:00Z` });
const mood = (ago, value) => ({ entry_date: date(ago), mood_rating: value });
const calculate = (sleep, moods = [], rest = {}) => buildInsights({ asOf: anchor, sleep, moods, ...rest });

test('M8 Spearman uses average tie ranks and never divides by constant variance', () => {
  assert.equal(spearman([1, 2, 3], [3, 2, 1]), -1);
  assert.equal(spearman([1, 1, 2, 2], [1, 1, 5, 5]), 1);
  assert.equal(spearman([2, 2], [1, 5]), null);
  assert.equal(spearman([], []), null);
  assert.equal(spearman([1, 2], [1]), null);
});
test('M8 missing dates/observations stay unknown; windows are calendar based', () => {
  const empty = calculate([]);
  assert.equal(empty.windows[0].current.average_minutes, null);
  assert.equal(empty.correlation.coefficient, null);
  assert.deepEqual(empty.patterns, []);
  const result = calculate([night(0, 420), night(7, 480)]);
  assert.equal(result.windows[0].current.nights, 1);
  assert.equal(result.windows[0].previous.nights, 1);
  assert.equal(result.windows[0].current.average_quality, null);
  assert.equal(result.windows[0].change_minutes, null);
});
test('M8 requires fourteen unique fresh paired days and never invents unmatched moods', () => {
  const sleep = Array.from({ length: 14 }, (_, i) => night(i, i < 7 ? 300 : 480));
  const moods = Array.from({ length: 14 }, (_, i) => mood(i, i < 7 ? 2 : 4));
  const result = calculate(sleep, moods);
  assert.equal(result.correlation.status, 'available');
  assert.equal(result.correlation.coefficient, 1);
  assert.equal(result.correlation.six_hours_or_more.average_mood, 4);
  assert.equal(result.correlation.under_six_hours.average_mood, 2);
  assert.equal(result.correlation.causal_claim, false);
  const short = calculate([...sleep, sleep[0]], moods.slice(1));
  assert.equal(short.correlation.paired_days, 13);
  assert.equal(short.correlation.status, 'insufficient_data');
  assert.equal(short.correlation.under_six_hours.average_mood, null);
});
test('M8 negative/no-variation associations and stale mood pairs are honest', () => {
  const sleep = Array.from({ length: 14 }, (_, i) => night(i, i < 7 ? 300 : 480));
  const negative = calculate(sleep, Array.from({ length: 14 }, (_, i) => mood(i, i < 7 ? 4 : 2)));
  assert.equal(negative.correlation.direction, 'negative');
  assert.equal(calculate(sleep, Array.from({ length: 14 }, (_, i) => mood(i, 3))).correlation.status, 'no_variation');
  const older = Array.from({ length: 14 }, (_, i) => night(i + 4, 300 + i * 10));
  assert.equal(calculate([night(0, 420), ...older], older.map((n, i) => ({ entry_date: n.sleep_date, mood_rating: i % 5 + 1 }))).correlation.status, 'stale');
});
test('M8 compares covered periods, flags recorded short sleep and protects safety guidance', () => {
  const sleep = Array.from({ length: 14 }, (_, i) => night(i, i < 7 ? 300 : 480));
  const result = calculate(sleep);
  assert.equal(result.windows[0].change_minutes, -180);
  assert.equal(result.windows[0].direction, 'less_recorded_sleep');
  assert.ok(result.patterns.includes('repeated_short_sleep'));
  assert.equal(result.activity, 'body_scan');
  assert.equal(calculate(sleep, [], { safetyPriority: true }).activity, 'crisis');
  assert.equal(calculate(Array.from({ length: 14 }, (_, i) => night(i + 5, 300))).patterns.length, 0);
});
test('M8 clock variability handles midnight and pauses mixed-timezone comparisons', () => {
  const stable = Array.from({ length: 14 }, (_, i) => ({ ...night(i, 420), bedtime: `${date(i)}T${i % 2 ? '23:55' : '00:05'}:00Z` }));
  assert.ok(calculate(stable).timing.bedtime_sd_minutes < 10);
  const varied = stable.map((n, i) => ({ ...n, bedtime: `${date(i)}T${i % 2 ? '03:00' : '23:00'}:00Z` }));
  assert.ok(calculate(varied).patterns.includes('variable_sleep_timing'));
  varied[0].timezone_offset_minutes = -300;
  assert.equal(calculate(varied).timing.bedtime_sd_minutes, null);
});
test('M8 excludes invalid/future inputs and permission-denied digital data', () => {
  const result = calculate([night(0, 420), night(-1, 480), night(1, 'NaN'), { ...night(2, 400), sleep_date: '2026-02-30' }],
    [mood(0, 3), mood(1, 9)], { telemetry: [{ local_date: anchor, usage_access: true, screen_time_minutes: 300, social_minutes: 300, late_night_minutes: 45 }] });
  assert.equal(result.windows[0].current.nights, 1);
  assert.equal(result.correlation.paired_days, 1);
  assert.equal(result.digital.recorded_days, 0);
  const digital = calculate([], [], { telemetryConsent: true, telemetry: [{ local_date: anchor, usage_access: true,
    screen_time_minutes: 330, social_minutes: 300, late_night_minutes: 45 }] });
  assert.equal(digital.digital.high_social_days, 1);
  assert.equal(digital.activity, 'body_scan');
});
test('M8 optional sleep details remain null and query dates respect the phone timezone', () => {
  const value = validateSleep({ sleep_date: anchor, bedtime: '2026-10-10T23:00:00+05:00', wake_time: '2026-10-11T07:00:00+05:00',
    awake_minutes: 0, timezone_offset_minutes: -300 }, Date.parse('2026-10-11T03:00:00Z'));
  assert.equal(value.quality, null);
  assert.equal(value.awakenings, null);
  assert.equal(dashboardQuery({ timezone_offset_minutes: '-300' }, Date.parse('2026-10-10T22:00:00Z')).asOf, anchor);
  for (const query of [{ as_of: '2026-02-30' }, { timezone_offset_minutes: '900' }, { journal: 'private' }, { as_of: '2027-10-11' }]) {
    assert.throws(() => dashboardQuery(query, Date.parse('2026-10-11')));
  }
});
