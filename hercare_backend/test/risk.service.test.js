const test = require('node:test');
const assert = require('node:assert/strict');
const risk = require('../src/modules/risk/risk.service')._private;

test('telemetry summary contains only aggregates and stable ratios', () => {
  const summary = risk.summarizeTelemetry([
    {
      message_notifications: 10,
      notification_access: true,
      usage_access: true,
      negative_notifications: 4,
      distress_notifications: 2,
      abuse_notifications: 1,
      screen_time_minutes: 120,
      social_minutes: 50,
      late_night_minutes: 20,
    },
    {
      message_notifications: 10,
      notification_access: true,
      usage_access: true,
      negative_notifications: 2,
      distress_notifications: 0,
      abuse_notifications: 1,
      screen_time_minutes: 180,
      social_minutes: 70,
      late_night_minutes: 40,
    },
  ]);
  assert.equal(summary.negative_notification_ratio, 0.3);
  assert.equal(summary.distress_notification_ratio, 0.1);
  assert.equal(summary.average_screen_minutes, 150);
  assert.equal(summary.telemetry_days, 2);
  assert.equal(Object.hasOwn(summary, 'content'), false);
});

test('mood slope detects a sustained decline', () => {
  const rows = [5, 4, 3, 2].map((mood) => ({
    mood_rating: mood,
    energy_level: 3,
    sleep_quality: 3,
    social_support: 3,
  }));
  assert.equal(risk.summarizeMood(rows).mood_slope, -1);
});

test('skipped daily details remain unknown in risk summary', () => {
  const summary = risk.summarizeMood([
    { mood_rating: 2, energy_level: null, sleep_quality: null, social_support: null },
    { mood_rating: 3, energy_level: 4, sleep_quality: null, social_support: null },
  ]);
  assert.equal(summary.average_mood, 2.5);
  assert.equal(summary.average_energy, 4);
  assert.equal(summary.average_sleep_quality, null);
  assert.equal(summary.average_social_support, null);
});

test('runtime social mappings remain explicit', () => {
  assert.equal(risk.financialStrain('30000-50000'), null);
  assert.equal(risk.financialStrain(false), 1);
  assert.equal(risk.financialStrain(true), 0);
  assert.equal(risk.supportQuality('none'), null);
  assert.equal(risk.supportQuality('husband'), null);
  assert.equal(risk.supportQuality('poor'), 0);
  assert.equal(risk.supportQuality('good'), 1);
});

test('permissions and absent notification denominators preserve missing measurements', () => {
  const unknown = risk.summarizeTelemetry([{ message_notifications: 0, usage_access: false, notification_access: false }]);
  assert.equal(unknown.average_screen_minutes, null);
  assert.equal(unknown.negative_notification_ratio, null);
  assert.equal(unknown.telemetry_days, 0);
});

test('irregular check-ins use calendar days rather than record index', () => {
  const summary = risk.summarizeMood([
    { entry_date: '2026-10-01', mood_rating: 1 }, { entry_date: '2026-10-05', mood_rating: 5 },
  ]);
  assert.equal(summary.mood_slope, 1);
});

test('telemetry dates are validated in the device local timezone', () => {
  const utcEvening = new Date('2026-09-23T23:30:00.000Z');
  assert.equal(risk.telemetryDateAgeDays('2026-09-24', -300, utcEvening), 0);
  assert.equal(risk.telemetryDateAgeDays('2026-09-10', -300, utcEvening), 14);
  assert.equal(risk.telemetryDateAgeDays('2026-09-09', -300, utcEvening), 15);
});
