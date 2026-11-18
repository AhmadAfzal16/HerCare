const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const r = require('../src/modules/content/content.ranking');
const p = require('../src/modules/content/content.policy');
const sources = require('../src/modules/content/content.sources');
const report = require('../scripts/content-report');
const { item, weights, preferences } = require('./helpers/content.fixture');

const now = Date.parse('2026-10-15T12:00:00Z');
const daysAgo = (days) => new Date(now - days * 86400000).toISOString();
const rank = (items, extra = {}) => r.rank(items, { userId: 'account', day: '2026-10-15', role: 'mother', preferences,
  context: {}, weights, now, limit: 30, ...extra });
const withPrefs = (extra) => ({ ...preferences, interests: [], preferred_formats: [], ...extra });

test('Phase 2 weights default for older rows and stay bounded', () => {
  const merged = r.validateWeights(weights);
  assert.deepEqual([merged.affinity, merged.interest, merged.format, merged.explore_slots], [15, 25, 8, 1]);
  for (const bad of [{ ...weights, explore_slots: 4 }, { ...weights, explore_slots: 1.5 }, { ...weights, interest: -1 },
    { ...weights, affinity: 101 }]) assert.throws(() => r.validateWeights(bad));
});

test('Phase 2 chosen topics match tags, categories and music, and lead the feed', () => {
  const sleep = item({ tags: ['sleep_support'] }); const calm = item({ category: 'soothing' });
  const music = item({ category: 'soothing', is_music: true }); const other = item();
  assert.deepEqual(r.interestMatches(sleep, ['sleep', 'calm']), ['sleep']);
  assert.deepEqual(r.interestMatches(calm, ['calm']), ['calm']);
  assert.deepEqual(r.interestMatches(music, ['music']), ['music']);
  assert.deepEqual(r.interestMatches(other, ['sleep', 'faith']), []);
  const ranked = rank([other, sleep], { preferences: withPrefs({ interests: ['sleep'] }) });
  assert.equal(ranked[0].row.id, sleep.id);
  assert.equal(ranked[0].reasons[0], 'interest');
});

test('Phase 2 a music interest never bypasses the separate music opt-in', () => {
  const music = item({ category: 'soothing', is_music: true });
  assert.equal(rank([music], { preferences: withPrefs({ interests: ['music'] }) }).length, 0);
  assert.equal(rank([music], { preferences: withPrefs({ interests: ['music'], music_enabled: true }) }).length, 1);
});

test('Phase 2 preferred formats and Urdu-language media get a modest lift', () => {
  for (let i = 0; i < 20; i++) {
    const video = item({ format: 'video', media_url: null }); const article = item();
    assert.equal(rank([article, video], { preferences: withPrefs({ preferred_formats: ['video'] }) })[0].row.id, video.id);
    const urdu = item({ tags: ['urdu'] }); const english = item();
    assert.equal(rank([english, urdu], { language: 'ur' })[0].row.id, urdu.id);
  }
});

test('Phase 2 learned taste: finished sleep videos lift other sleep items', () => {
  const finished = [1, 2, 3].map(() => item({ tags: ['sleep_support'], category: 'soothing', view_count: 1, media_opens: 1,
    completions: 1, last_viewed_at: daysAgo(1), last_engaged_at: daysAgo(1) }));
  const unseenSleep = item({ tags: ['sleep_support'], category: 'soothing' }); const unseenOther = item({ category: 'bonding' });
  const model = r.affinityModel([...finished, unseenSleep, unseenOther], now);
  assert.ok(r.affinityScore(unseenSleep, model) > 0.5);
  assert.equal(r.affinityScore(unseenOther, model), 0);
  const ranked = rank([...finished, unseenOther, unseenSleep]);
  assert.ok(ranked.findIndex(({ row }) => row.id === unseenSleep.id) < ranked.findIndex(({ row }) => row.id === unseenOther.id));
  assert.ok(ranked.find(({ row }) => row.id === unseenSleep.id).reasons.includes('affinity'));
});

test('Phase 2 old habits fade and "not helpful" pushes a topic down', () => {
  const recent = r.engagementStrength(item({ completions: 1, last_engaged_at: daysAgo(0) }), now);
  const old = r.engagementStrength(item({ completions: 1, last_engaged_at: daysAgo(42) }), now);
  assert.ok(Math.abs(old - recent / 4) < 0.01, 'two half-lives');
  assert.ok(r.engagementStrength(item({ feedback: 'not_helpful', view_count: 0, last_viewed_at: daysAgo(0) }), now) < 0);
  assert.equal(r.engagementStrength(item({ feedback: 'dismissed' }), now), 0, 'dismissing one item is not a topic dislike');
});

test('Phase 2 one helpful tap never outranks the item she marked helpful', () => {
  for (let i = 0; i < 50; i++) {
    const helpful = item({ feedback: 'helpful' }); const similar = item();
    assert.equal(rank([similar, helpful])[0].row.id, helpful.id);
  }
});

test('Phase 2 exploration places one untried category at slot 3, only once she has history', () => {
  const engaged = Array.from({ length: 6 }, () => item({ category: 'soothing', priority: 50, completions: 2, last_engaged_at: daysAgo(1) }));
  const fresh = item({ category: 'bonding', priority: 0 });
  const ranked = rank([...engaged, fresh]);
  assert.equal(ranked[2].row.id, fresh.id);
  assert.equal(ranked[2].reasons[0], 'explore');
  const noHistory = rank([...Array.from({ length: 6 }, () => item({ category: 'soothing', priority: 50 })), fresh]);
  assert.notEqual(noHistory[2].row.id, fresh.id);
  assert.notEqual(rank([...engaged, fresh], { weights: { ...weights, explore_slots: 0 } })[2].row.id, fresh.id);
});

test('Phase 2 preference validation: optional topic/format lists, unknown values rejected', () => {
  const base = { version: 0, religious_enabled: false, music_enabled: false, disabled_categories: [] };
  assert.equal(p.preferences(base).interests, undefined, 'older apps keep the stored choice');
  assert.deepEqual(p.preferences({ ...base, interests: ['sleep', 'calm', 'sleep'] }).interests, ['calm', 'sleep']);
  assert.deepEqual(p.preferences({ ...base, preferred_formats: ['video'] }).preferred_formats, ['video']);
  for (const bad of [{ interests: ['diagnosis'] }, { interests: 'sleep' }, { preferred_formats: ['hologram'] }]) {
    assert.throws(() => p.preferences({ ...base, ...bad }));
  }
});

test('Phase 2 YouTube source: channel must match; operators cannot override verified fields', async () => {
  assert.throws(() => sources.parseYouTube({ title: 'x', author_name: 'Someone Else' }, 'KBlVBOP7TGc', 'NHS'));
  const ok = sources.parseYouTube({ title: 'How do I know', author_name: 'NHS' }, 'KBlVBOP7TGc', 'nhs');
  assert.equal(ok.media_url, 'https://www.youtube.com/watch?v=KBlVBOP7TGc');
  assert.match(ok.attribution, /NHS/);
  const entry = (extra = {}) => ({ catalog_id: 'test', items: [{ key: 'a', source: { type: 'youtube', video_id: 'KBlVBOP7TGc', channel: 'NHS' },
    item: { review_after: '2030-01-01T00:00:00Z', ...extra } }] });
  assert.doesNotThrow(() => sources.validateManifest(entry()));
  assert.throws(() => sources.validateManifest(entry({ media_url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa' })));
  assert.throws(() => sources.validateManifest({ ...entry(), items: [{ ...entry().items[0], item: {} }] }));
  assert.throws(() => sources.validateManifest({ catalog_id: 'test', items: [{ key: 'a', source: { type: 'youtube', video_id: 'bad' , channel: 'NHS' }, item: {} }] }));
  const fetchImpl = async (url) => ({ ok: true, redirected: false, url,
    headers: new Headers({ 'content-type': 'application/json' }),
    body: new Response(JSON.stringify({ title: 'T', author_name: 'NHS' })).body });
  assert.equal((await sources.fetchYouTube('KBlVBOP7TGc', 'NHS', { fetchImpl })).source_name, 'NHS (YouTube)');
  const missing = async () => ({ ok: false, headers: new Headers(), body: null });
  await assert.rejects(sources.fetchYouTube('KBlVBOP7TGc', 'NHS', { fetchImpl: missing }), /could not be verified/);
});

function fakeDb(overrides = () => null) {
  const userId = randomUUID(); const sql = [];
  const db = { sql, userId, query: async (text, args) => {
    sql.push({ text, args });
    const custom = await overrides(text, args); if (custom) return custom;
    if (/SELECT id,role/.test(text)) return { rows: [{ id: userId, role: 'mother', is_active: true, onboarding_complete: true }] };
    if (/SELECT consent_tier1/.test(text)) return { rows: [{ consent_tier1: true }] };
    if (/AS needs_help/.test(text)) return { rows: [{ needs_help: false }] };
    if (/SELECT \* FROM content_items WHERE id=\$1 FOR SHARE/.test(text)) return { rows: [item({ id: args[0] })] };
    return { rows: [] };
  } };
  return db;
}
async function withDb(db, work) {
  const original = database.withTransaction;
  database.withTransaction = async (fn) => fn(db);
  try { return await work(); } finally { database.withTransaction = original; }
}

test('Phase 2 engagement stores counts/seconds only and validates the event', async () => {
  const db = fakeDb(); const contentId = randomUUID();
  await withDb(db, () => service.engagement(db.userId, contentId, { event: 'completed', seconds: 300, reason: 'interest' }));
  const write = db.sql.find(({ text }) => /INSERT INTO content_views/.test(text));
  assert.deepEqual(write.args, [db.userId, contentId, 0, 1, 300, 'interest']);
  for (const bad of [{ event: 'watched_secret_video' }, { event: 'completed', seconds: 99999 }, { event: 'engaged', reason: 'made_up' },
    { event: 'engaged', url: 'https://example.org' }]) {
    await assert.rejects(withDb(fakeDb(), () => service.engagement(db.userId, contentId, bad)), { statusCode: 422 });
  }
  const crisis = fakeDb((text) => /AS needs_help/.test(text) ? { rows: [{ needs_help: true }] } : null);
  await assert.rejects(withDb(crisis, () => service.engagement(crisis.userId, contentId, { event: 'engaged' })), { statusCode: 409 });
});

test('Phase 2 saving preferences from an older app keeps her chosen topics', async () => {
  const db = fakeDb((text) => /SELECT \* FROM content_preferences/.test(text)
    ? { rows: [{ religious_enabled: false, music_enabled: false, disabled_categories: [], interests: ['sleep'], preferred_formats: ['video'], version: 2 }] }
    : /INSERT INTO content_preferences/.test(text) ? { rows: [{ version: 3 }] } : null);
  await withDb(db, () => service.updatePreferences(db.userId, { version: 2, religious_enabled: false, music_enabled: false, disabled_categories: [] }));
  const write = db.sql.find(({ text }) => /INSERT INTO content_preferences/.test(text));
  assert.deepEqual(write.args.slice(4), [['sleep'], ['video']]);
});

test('Phase 2 bulk review approves and publishes each item, reporting failures per item', async () => {
  const adminId = randomUUID(); const good = randomUUID(); const bad = randomUUID();
  // bulkReview checks the admin outside a transaction, then runs the real review/publication flow.
  const originalQuery = database.query;
  database.query = async (text) => /SELECT id,role/.test(text)
    ? { rows: [{ id: adminId, role: 'admin', is_active: true, onboarding_complete: true }] } : { rows: [] };
  const calls = [];
  const tx = { query: async (text, args) => {
    calls.push(text);
    if (/SELECT id,role/.test(text)) return { rows: [{ id: adminId, role: 'admin', is_active: true, onboarding_complete: true }] };
    if (/FROM content_items WHERE id=\$1 FOR UPDATE/.test(text)) {
      if (args[0] === bad) return { rows: [] };
      return { rows: [{ ...item({ id: args[0], status: calls.some((c) => /status=\$2,version=version\+1,reviewed_by/.test(c)) ? 'reviewed' : 'draft' }),
        version: calls.filter((c) => /RETURNING \*/.test(c)).length + 1, review_after: new Date(Date.now() + 86400000), source_url: null }] };
    }
    if (/COUNT\(\*\)::int AS count FROM content_items/.test(text)) return { rows: [{ count: 0 }] };
    if (/RETURNING \*/.test(text)) return { rows: [{ ...item({ id: args[0] }), status: /published_at=CASE/.test(text) ? 'published' : 'reviewed', version: 2 }] };
    return { rows: [] };
  } };
  try {
    const result = await withDb(tx, () => service.bulkReview(adminId, { items: [{ id: good, version: 1 }, { id: bad, version: 1 }],
      review_note: 'Watched in full; NHS source, suitable.', reviewer_qualification: 'Midwife', publish: true }));
    assert.equal(result.approved, 1);
    assert.equal(result.results[0].ok, true); assert.equal(result.results[0].status, 'published');
    assert.equal(result.results[1].ok, false);
    await assert.rejects(service.bulkReview(adminId, { items: [], review_note: 'x'.repeat(20), reviewer_qualification: 'Midwife', publish: true }), { statusCode: 422 });
    await assert.rejects(service.bulkReview(adminId, { items: [{ id: good, version: 1 }, { id: good, version: 1 }],
      review_note: 'x'.repeat(20), reviewer_qualification: 'Midwife', publish: true }), { statusCode: 422 });
  } finally { database.query = originalQuery; }
});

test('Phase 3 report hides groups under the minimum account count', () => {
  const rows = Array.from({ length: 4 }, () => ({ user_id: randomUUID(), last_reason: 'interest', media_opens: 1, completions: 1, feedback: 'helpful' }));
  assert.equal(report.summarize(rows, (row) => row.last_reason).length, 0);
  rows.push({ user_id: randomUUID(), last_reason: 'interest', media_opens: 0, completions: 0, feedback: null });
  const [group] = report.summarize(rows, (row) => row.last_reason);
  assert.equal(group.accounts, report.MIN_GROUP); assert.equal(group.finished, '80%');
});
