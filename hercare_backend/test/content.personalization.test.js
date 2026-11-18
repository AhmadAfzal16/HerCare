const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const r = require('../src/modules/content/content.ranking');
const { item, weights, preferences } = require('./helpers/content.fixture');

const now = Date.parse('2026-10-15T12:00:00Z');
const rank = (items, extra = {}) => r.rank(items, { userId: 'account', day: '2026-10-15', role: 'mother', preferences,
  context: {}, weights, now, limit: 30, ...extra });
const daysAgo = (days) => new Date(now - days * 86400000).toISOString();

test('Phase 1 weights saved before migration 024 still validate, and new weights stay bounded', () => {
  const merged = r.validateWeights(weights);
  assert.equal(merged.profile, 20); assert.equal(merged.repeat, -8); assert.equal(merged.novelty, 4);
  assert.equal(r.validateWeights({ ...weights, profile: 50 }).profile, 50);
  for (const bad of [{ ...weights, repeat: 1 }, { ...weights, repeat: -101 }, { ...weights, profile: -1 },
    { ...weights, novelty: 101 }, { ...weights, profile: Infinity }]) assert.throws(() => r.validateWeights(bad));
});

test('Phase 1 postpartum stage advances through fixed bands', () => {
  assert.equal(r.stageTag(0), 'stage_0_6w');
  assert.equal(r.stageTag(1.49), 'stage_0_6w');
  assert.equal(r.stageTag(2), 'stage_6w_3m');
  assert.equal(r.stageTag(4), 'stage_3_6m');
  assert.equal(r.stageTag(12), 'stage_6_12m');
  assert.equal(r.stageTag(13), 'stage_12m_plus');
  for (const missing of [null, undefined, NaN, -1]) assert.equal(r.stageTag(missing), null);
});

test('Phase 1 profile tags use delivery, complications and support; recovery tags expire', () => {
  const early = { monthsPostpartum: 1, deliveryMethod: 'cesarean', hemorrhage: true, preeclampsia: false,
    gestationalDiabetes: true, pretermBirth: true, primarySupport: 'none', householdType: 'joint' };
  assert.deepEqual(r.profileTags(early, 'mother').sort(), ['cesarean_recovery', 'health_followup', 'joint_family',
    'low_support', 'physical_recovery', 'preterm_baby', 'stage_0_6w'].sort());
  const later = r.profileTags({ ...early, monthsPostpartum: 7 }, 'mother');
  assert.ok(!later.includes('cesarean_recovery') && !later.includes('physical_recovery'));
  assert.ok(later.includes('stage_6_12m') && later.includes('preterm_baby'));
  assert.deepEqual(r.profileTags(early, 'guardian'), []);
  assert.deepEqual(r.profileTags(null, 'mother'), []);
  assert.deepEqual(r.profileTags({ monthsPostpartum: null }, 'mother'), []);
});

test('Phase 1 profile match lifts stage-appropriate content and explains why', () => {
  const general = item(); const stage = item({ tags: ['stage_0_6w'] }); const later = item({ tags: ['stage_6_12m'] });
  const csec = item({ tags: ['cesarean_recovery'] });
  const profile = { monthsPostpartum: 0.5, deliveryMethod: 'cesarean' };
  const ranked = rank([general, later, stage, csec], { context: { profile } });
  assert.deepEqual(new Set(ranked.slice(0, 2).map(({ row }) => row.id)), new Set([stage.id, csec.id]));
  assert.equal(ranked.find(({ row }) => row.id === stage.id).reasons[0], 'stage');
  assert.equal(ranked.find(({ row }) => row.id === csec.id).reasons[0], 'recovery');
  for (const code of ['stage', 'recovery', 'support', 'mood_declining']) assert.equal(r.REASONS[code].length, 2, code);
});

test('Phase 1 today\'s state outranks the static profile and is shown first', () => {
  const both = item({ tags: ['low_mood', 'stage_0_6w'] });
  const result = rank([both], { context: { mood: 1, profile: { monthsPostpartum: 0.5 } } });
  assert.deepEqual(result[0].reasons, ['low_mood', 'stage']);
  const stageOnly = item({ tags: ['stage_0_6w'] }); const moodOnly = item({ tags: ['low_mood'] });
  assert.equal(rank([stageOnly, moodOnly], { context: { mood: 1, profile: { monthsPostpartum: 0.5 } } })[0].row.id, moodOnly.id);
});

test('Phase 1 7-day trends catch a low or falling week even when today looks fine', () => {
  assert.ok(r.contextTags({ mood: 4, moodTrend: { days: 5, average: 2.2, recent: 4, earlier: 1.5 } }, 'mother').includes('low_mood'));
  const falling = r.contextTags({ moodTrend: { days: 6, average: 3.2, recent: 2.5, earlier: 4 } }, 'mother');
  assert.ok(falling.includes('mood_declining') && falling.includes('low_mood'));
  assert.deepEqual(r.contextTags({ moodTrend: { days: 2, average: 1, recent: 1, earlier: null } }, 'mother'), []);
  assert.deepEqual(r.contextTags({ moodTrend: { days: 6, average: 3.5, recent: 3.4, earlier: 3.6 } }, 'mother'), []);
  assert.ok(r.contextTags({ sleepTrend: { nights: 4, averageMinutes: 320, averageQuality: 3 } }, 'mother').includes('sleep_support'));
  assert.ok(r.contextTags({ sleepTrend: { nights: 4, averageMinutes: 420, averageQuality: 1.5 } }, 'mother').includes('sleep_support'));
  assert.deepEqual(r.contextTags({ sleepTrend: { nights: 2, averageMinutes: 100, averageQuality: 1 } }, 'mother'), []);
  const declining = item({ tags: ['low_mood', 'mood_declining'] });
  assert.equal(rank([declining], { context: { moodTrend: { days: 6, average: 3, recent: 2, earlier: 4 } } })[0].reasons[0], 'mood_declining');
});

test('Phase 1 recently opened articles rotate down; practices, saved and helpful items are exempt', () => {
  const w = r.validateWeights(weights);
  assert.equal(r.repeatAdjustment(item(), w, now), w.novelty);
  assert.equal(r.repeatAdjustment(item({ saved: true }), w, now), 0);
  const fresh = r.repeatAdjustment(item({ view_count: 3, last_viewed_at: daysAgo(0) }), w, now);
  const older = r.repeatAdjustment(item({ view_count: 3, last_viewed_at: daysAgo(7) }), w, now);
  assert.ok(fresh < older && older < 0);
  assert.equal(r.repeatAdjustment(item({ view_count: 50, last_viewed_at: daysAgo(0) }), w, now), fresh, 'penalty is capped');
  assert.equal(r.repeatAdjustment(item({ view_count: 3, last_viewed_at: daysAgo(15) }), w, now), 0);
  for (const exempt of [{ format: 'activity' }, { saved: true }, { feedback: 'helpful' }]) {
    assert.equal(r.repeatAdjustment(item({ view_count: 3, last_viewed_at: daysAgo(0), ...exempt }), w, now), 0);
  }
  const seen = item({ priority: 10, view_count: 3, last_viewed_at: daysAgo(0) }); const unseen = item({ priority: 0 });
  assert.equal(rank([seen, unseen])[0].row.id, unseen.id);
  assert.equal(rank([item({ ...seen, saved: true })], { savedOnly: true }).length, 1);
});

test('Phase 1 safety override still beats every new signal', () => {
  const row = item({ tags: ['stage_0_6w', 'low_mood'] });
  assert.deepEqual(rank([row], { context: { safetyPriority: true, profile: { monthsPostpartum: 0.5 },
    moodTrend: { days: 7, average: 1, recent: 1, earlier: 1 } } }), []);
});

test('Phase 1 feed loads profile/trend aggregates and detail records a rate-limited open', async () => {
  const userId = randomUUID(); const contentId = randomUUID(); const sql = [];
  const db = { query: async (text, args) => {
    sql.push({ text, args });
    if (/SELECT id,role/.test(text)) return { rows: [{ id: userId, role: 'mother', is_active: true, onboarding_complete: true }] };
    if (/SELECT consent_tier1/.test(text)) return { rows: [{ consent_tier1: true }] };
    if (/SELECT revision,policy_version,weights/.test(text)) return { rows: [{ revision: '1', policy_version: 1, weights }] };
    if (/AS needs_help/.test(text)) return { rows: [{ needs_help: false }] };
    if (/months_postpartum/.test(text)) return { rows: [{ months_postpartum: 0.4, delivery_method: 'cesarean', primary_support: 'none' }] };
    if (/AS days/.test(text)) return { rows: [{ days: 5, average: 2, recent: 2, earlier: 2 }] };
    if (/LEFT JOIN content_feedback/.test(text)) return { rows: [item({ id: contentId, tags: ['cesarean_recovery'] })] };
    return { rows: [] };
  } };
  const original = database.withTransaction;
  database.withTransaction = async (fn) => fn(db);
  try {
    const feed = await service.feed(userId);
    assert.deepEqual(feed.context.available_signals.sort(), ['mood_trend', 'profile']);
    assert.equal(feed.items[0].reason_codes[0], 'recovery');
    for (const field of ['delivery_method', 'months_postpartum', 'monthsPostpartum', 'primary_support', 'moodTrend']) {
      assert.equal(JSON.stringify(feed).includes(field), false, `raw profile value ${field} is never returned`);
    }
    assert.equal(feed.items[0].view_count, undefined);
    assert.ok(sql.some(({ text }) => /months_since_birth_recorded_at/.test(text)));
    assert.ok(sql.every(({ text }) => !/full_name|income_range|city/.test(text)), 'only ranking-relevant profile fields are read');
    await service.detail(userId, contentId);
    const view = sql.find(({ text }) => /INSERT INTO content_views/.test(text));
    assert.ok(view); assert.match(view.text, /30 minutes/); assert.deepEqual(view.args, [userId, contentId, null]);
  } finally { database.withTransaction = original; }
});
