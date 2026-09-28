const test = require('node:test');
const assert = require('node:assert/strict');
const { validateSleep, summarize } = require('../src/modules/sleep/sleep.logic');

const now = Date.parse('2026-09-26T08:00:00Z');
const sample = {
  sleep_date: '2026-09-26', bedtime: '2026-09-25T23:00:00+05:00',
  wake_time: '2026-09-26T07:00:00+05:00', awake_minutes: 30,
  quality: 3, awakenings: 2, timezone_offset_minutes: -300,
};
test('sleep accepts overnight local dates and timezone-aware timestamps', () => {
  assert.deepEqual(validateSleep(sample, now), sample);
});
test('sleep rejects future times, invalid intervals, mismatched dates, and private extras', () => {
  for (const change of [
    { wake_time: '2026-09-27T07:00:00+05:00' },
    { bedtime: sample.wake_time }, { awake_minutes: 480 }, { quality: 6 },
    { awakenings: -1 }, { sleep_date: '2026-09-25' }, { journal: 'private' },
    { bedtime: '2026-09-25T23:00:00' }, { timezone_offset_minutes: 900 },
  ]) assert.throws(() => validateSleep({ ...sample, ...change }, now));
});
test('sleep summary preserves missing data and accepts database numeric strings', () => {
  assert.equal(summarize([]).average_minutes, null);
  assert.equal(summarize([{ sleep_minutes: '420' }, { sleep_minutes: '480' }]).average_minutes, 450);
});
