const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const live = require('../src/modules/content/content.live');

const HEALTH = 'UCbVg41jzM8UroywvEr73Pdw'; // NHS
const MUSIC = 'UCwobzUc3z-0PrFpoRxNszXQ'; // Yellow Brick Cinema
const config = live.loadSources();
const KEY = 'AIzaTestKeyOnly_abcdefghijklmnopqrstu';

function jsonResponse(url, body) {
  return { ok: true, redirected: false, url, headers: new Headers({ 'content-type': 'application/json' }),
    body: new Response(JSON.stringify(body)).body };
}
const searchItem = (videoId, channelId, title, extra = {}) => ({ id: { kind: 'youtube#video', videoId },
  snippet: { channelId, title, description: 'A calm guide.', publishedAt: '2026-01-01T00:00:00Z', liveBroadcastContent: 'none', ...extra } });
const details = (id, extra = {}) => ({ id, status: { privacyStatus: 'public', embeddable: true, uploadStatus: 'processed', ...extra.status },
  contentDetails: { duration: 'PT5M10S', contentRating: {}, ...extra.contentDetails } });
function fakeYouTube({ search, videos }) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return jsonResponse(url, url.includes('/search?') ? { items: search } : { items: videos });
  };
  return { fetchImpl, calls };
}

test('live search keeps only safe videos from trusted channels suited to the topic', async () => {
  const yt = fakeYouTube({
    search: [
      searchItem('goodvideo01', HEALTH, 'Postnatal depression: getting help &amp; support'),
      searchItem('untrusted01', 'UCaaaaaaaaaaaaaaaaaaaaaa', 'Postnatal depression help'),
      searchItem('wrongkind01', MUSIC, 'Relaxing music'), // music channel is not allowed under "learning"
      searchItem('livestrm001', HEALTH, 'Live Q&A', { liveBroadcastContent: 'live' }),
      searchItem('miracle0001', HEALTH, 'Miracle cure for depression in 3 days'),
      searchItem('wazifa00001', HEALTH, 'Wazifa for a happy home'),
      searchItem('shortvid001', HEALTH, 'Baby blues explained'),
      searchItem('agerestrict', HEALTH, 'Birth stories'),
      searchItem('pkblocked01', HEALTH, 'Feeding guide'),
      searchItem('notembed001', HEALTH, 'Feeding guide 2'),
      { id: { kind: 'youtube#channel', channelId: HEALTH }, snippet: { channelId: HEALTH, title: 'NHS' } },
    ],
    videos: [details('goodvideo01'), details('shortvid001', { contentDetails: { duration: 'PT45S' } }),
      details('agerestrict', { contentDetails: { contentRating: { ytRating: 'ytAgeRestricted' } } }),
      details('pkblocked01', { contentDetails: { regionRestriction: { blocked: ['PK'] } } }),
      details('notembed001', { status: { embeddable: false } })],
  });
  const items = await live.searchTopic('learning', 'en', { fetchImpl: yt.fetchImpl, key: KEY, sources: config });
  assert.deepEqual(items.map((item) => item.video_id), ['goodvideo01']);
  assert.equal(items[0].title, 'Postnatal depression: getting help & support');
  assert.equal(items[0].channel_title, 'NHS');
  assert.equal(items[0].duration_seconds, 310);
  const [search, lookup] = yt.calls;
  assert.match(search.url, /safeSearch=strict/); assert.match(search.url, /videoEmbeddable=true/); assert.match(search.url, /regionCode=PK/);
  assert.ok(!search.url.includes(KEY) && !lookup.url.includes(KEY), 'API key is never in a URL');
  assert.equal(search.init.headers['X-Goog-Api-Key'], KEY);
  assert.equal(search.init.redirect, 'error');
  assert.equal(new URL(search.url).searchParams.get('q'), 'perinatal mental health baby blues', 'query is the fixed topic text');
});

test('live text is cleaned and harmful terms are blocked in English and Urdu', () => {
  assert.equal(live.cleanText('Calm‮ evil\u0007 &#39;breath&#39;', 100), "Calm evil 'breath'");
  for (const bad of ['Suicide awareness story', 'Kala jadu ka tor', 'Stop taking your medication now', 'خودکشی', 'Lose 10 kg after birth', 'Funny #shorts'])
    assert.ok(live.blocked(bad), bad);
  for (const ok of ['A short breathing exercise', 'Postpartum anxiety: what helps', 'Surah Rahman recitation'])
    assert.ok(!live.blocked(ok), ok);
  assert.equal(live.durationSeconds('PT1H2M3S'), 3723);
  assert.equal(live.durationSeconds('P1D'), null);
});

test('topics come from her choices and state; music/faith need opt-ins; guardians get support topics', () => {
  const prefs = { music_enabled: false, religious_enabled: false, disabled_categories: [], interests: ['music', 'faith', 'sleep'] };
  assert.deepEqual(live.topicsFor({ role: 'mother', preferences: prefs }), ['sleep', 'calm', 'learning']);
  assert.deepEqual(live.topicsFor({ role: 'mother', preferences: { ...prefs, music_enabled: true, religious_enabled: true } }),
    ['music', 'faith', 'sleep']);
  assert.deepEqual(live.topicsFor({ role: 'mother', preferences: { ...prefs, interests: [] }, contextTags: ['low_mood'] }),
    ['low_mood', 'calm', 'learning']);
  assert.deepEqual(live.topicsFor({ role: 'mother', preferences: { ...prefs, interests: [], disabled_categories: ['psychoeducation'] } }),
    ['calm']);
  assert.deepEqual(live.topicsFor({ role: 'guardian', preferences: prefs }), ['relationships', 'learning']);
});

test('cached results are re-checked against the current trusted list and opt-ins', () => {
  const item = { video_id: 'goodvideo01', title: 'Calm music', channel_id: MUSIC, kind: 'music' };
  const prefs = { music_enabled: true, religious_enabled: false, disabled_categories: [] };
  assert.ok(live.stillAllowed(item, 'music', prefs, config));
  assert.ok(!live.stillAllowed(item, 'music', { ...prefs, music_enabled: false }, config));
  assert.ok(!live.stillAllowed(item, 'learning', prefs, config));
  const removed = { ...config, channels: new Map() };
  assert.ok(!live.stillAllowed(item, 'music', prefs, removed), 'removing a channel takes effect on cached rows');
  assert.ok(!live.stillAllowed(item, 'music', prefs, { ...config, blockedVideos: new Set(['goodvideo01']) }));
});

function fakeDb({ crisis = false, cache = {}, hidden = [], reviewed = [] } = {}) {
  const userId = randomUUID(); const writes = [];
  const query = async (text, args) => {
    if (/SELECT id,role/.test(text)) return { rows: [{ id: userId, role: 'mother', is_active: true, onboarding_complete: true }] };
    if (/SELECT consent_tier1/.test(text)) return { rows: [{ consent_tier1: true }] };
    if (/AS needs_help/.test(text)) return { rows: [{ needs_help: crisis }] };
    if (/FROM content_live_cache/.test(text)) { const row = cache[`${args[0]}:${args[1]}`]; return { rows: row ? [row] : [] }; }
    if (/INSERT INTO content_live_cache/.test(text)) { writes.push(args); return { rows: [] }; }
    if (/FROM content_live_hidden/.test(text)) return { rows: hidden.map((video_id) => ({ video_id })) };
    if (/SELECT media_url FROM content_items/.test(text)) return { rows: reviewed.map((id) => ({ media_url: `https://www.youtube.com/watch?v=${id}` })) };
    return { rows: [] };
  };
  return { userId, writes, query };
}
async function withDb(db, env, work) {
  const original = { tx: database.withTransaction, query: database.query, key: process.env.YOUTUBE_API_KEY, off: process.env.CONTENT_LIVE_SEARCH };
  database.withTransaction = async (fn) => fn(db); database.query = db.query;
  Object.assign(process.env, env);
  if (env.YOUTUBE_API_KEY === undefined) delete process.env.YOUTUBE_API_KEY;
  service._live.liveState.failures.clear(); service._live.liveState.refreshes.length = 0;
  try { return await work(); } finally {
    database.withTransaction = original.tx; database.query = original.query;
    if (original.key === undefined) delete process.env.YOUTUBE_API_KEY; else process.env.YOUTUBE_API_KEY = original.key;
    if (original.off === undefined) delete process.env.CONTENT_LIVE_SEARCH; else process.env.CONTENT_LIVE_SEARCH = original.off;
  }
}
const cached = (ids, kind = 'calm', channel = 'UC3JhfsgFPLSLNEROQCdj-GQ') => ({ fetched_at: new Date(),
  items: ids.map((video_id) => ({ video_id, title: `Video ${video_id}`, channel_id: channel, channel_title: 'Headspace', kind, duration_seconds: 300 })) });

test('live feed: crisis or missing key returns nothing and never calls YouTube', async () => {
  let called = false; const fetchImpl = async () => { called = true; };
  const crisis = fakeDb({ crisis: true });
  const blocked = await withDb(crisis, { YOUTUBE_API_KEY: KEY }, () => service.liveFeed(crisis.userId, {}, { fetchImpl, backgroundRefresh: false }));
  assert.equal(blocked.empty_reason, 'safety_support_required'); assert.deepEqual(blocked.items, []);
  const unconfigured = fakeDb();
  const off = await withDb(unconfigured, { YOUTUBE_API_KEY: undefined }, () => service.liveFeed(unconfigured.userId, {}, { fetchImpl, backgroundRefresh: false }));
  assert.equal(off.empty_reason, 'live_search_not_configured');
  const disabled = await withDb(unconfigured, { YOUTUBE_API_KEY: KEY, CONTENT_LIVE_SEARCH: 'off' }, () => service.liveFeed(unconfigured.userId, {}, { fetchImpl, backgroundRefresh: false }));
  assert.equal(disabled.enabled, false);
  assert.equal(called, false);
});

test('live feed serves the shared cache, drops hidden and already-reviewed videos, labels results unreviewed', async () => {
  const db = fakeDb({ cache: { 'calm:en': cached(['calmvideo01', 'calmvideo02', 'calmvideo03']),
    'learning:en': cached(['learnvideo1'], 'health', HEALTH) }, hidden: ['calmvideo02'], reviewed: ['calmvideo03'] });
  const fetchImpl = async () => { throw new Error('should use cache'); };
  const result = await withDb(db, { YOUTUBE_API_KEY: KEY }, () => service.liveFeed(db.userId, {}, { fetchImpl, backgroundRefresh: false }));
  assert.deepEqual(result.topics, ['calm', 'learning']);
  assert.deepEqual(result.items.map((item) => item.video_id), ['calmvideo01', 'learnvideo1']);
  assert.equal(result.items[0].reviewed, false);
  assert.match(result.notice_en, /Not individually reviewed/);
  assert.equal(result.items[0].media_url, 'https://www.youtube.com/watch?v=calmvideo01');
  assert.equal(JSON.stringify(result).includes(db.userId), false);
});

test('live feed refreshes a stale topic once, and serves stale results if YouTube fails', async () => {
  const old = { ...cached(['oldvideo001']), fetched_at: new Date(Date.now() - 20 * 3600000) };
  const db = fakeDb({ cache: { 'calm:en': old, 'learning:en': cached([]) } });
  const yt = fakeYouTube({ search: [searchItem('newvideo001', 'UC3JhfsgFPLSLNEROQCdj-GQ', 'Breathing for calm')], videos: [details('newvideo001')] });
  const fresh = await withDb(db, { YOUTUBE_API_KEY: KEY }, () => service.liveFeed(db.userId, {}, { fetchImpl: yt.fetchImpl, backgroundRefresh: false }));
  assert.deepEqual(fresh.items.map((item) => item.video_id), ['newvideo001']);
  assert.equal(db.writes.length, 1);
  const failing = fakeDb({ cache: { 'calm:en': old, 'learning:en': cached([]) } });
  const down = async () => { throw new Error('network'); };
  const stale = await withDb(failing, { YOUTUBE_API_KEY: KEY }, () => service.liveFeed(failing.userId, {}, { fetchImpl: down, backgroundRefresh: false }));
  assert.deepEqual(stale.items.map((item) => item.video_id), ['oldvideo001']);
});

test('hiding a live video validates the ID and stores only the ID', async () => {
  const writes = []; const userId = randomUUID();
  const original = database.query;
  database.query = async (text, args) => {
    if (/SELECT id,role/.test(text)) return { rows: [{ id: userId, role: 'mother', is_active: true, onboarding_complete: true }] };
    if (/SELECT consent_tier1/.test(text)) return { rows: [{ consent_tier1: true }] };
    if (/INSERT INTO content_live_hidden/.test(text)) writes.push(args);
    return { rows: [] };
  };
  try {
    assert.deepEqual(await service.hideLive(userId, { video_id: 'abcdefghijk' }), { video_id: 'abcdefghijk', hidden: true });
    assert.deepEqual(writes, [[userId, 'abcdefghijk']]);
    for (const bad of [{ video_id: '../etc' }, { video_id: 'abcdefghijk', note: 'x' }, {}]) {
      await assert.rejects(service.hideLive(userId, bad), { statusCode: 422 });
    }
  } finally { database.query = original; }
});

test('off-audience filter: fertility, IVF, pregnancy-only and loss content never reach mothers after birth', () => {
  for (const title of ['IVF success tips', 'How soon can you get pregnant after C-section?', 'Home pregnancy test negative',
    'Pregnancy scan guide', 'Coping with miscarriage', 'From Heartbreak to Motherhood', 'Third trimester checklist'])
    assert.ok(live.offAudience(title), title);
  for (const title of ['Postpartum exercises after pregnancy', 'Breastfeeding positions', 'Postnatal depression: getting help'])
    assert.ok(!live.offAudience(title), title);
});

test('library topic match needs a suitable channel kind and a topic word in the title', () => {
  const health = (title) => ({ title, kind: 'health' });
  assert.ok(live.matchesTopic(health('How to breastfeed comfortably'), 'feeding'));
  assert.ok(!live.matchesTopic(health('Can diabetics drink doodh?'), 'feeding'), 'bare "milk" is not feeding');
  assert.ok(live.matchesTopic(health('After C-Section Exercise'), 'body_recovery'));
  assert.ok(!live.matchesTopic({ title: 'Relaxing piano for sleep', kind: 'music' }, 'learning'), 'music never appears under health topics');
  assert.ok(live.matchesTopic({ title: 'Relaxing piano for sleep', kind: 'music' }, 'music'));
  assert.ok(!live.matchesTopic(health('Pregnancy scan guide'), 'learning'));
});

test('channel uploads: only that channel, through the same text and details gates, 1 unit per page', async () => {
  const uploads = [
    { snippet: { channelId: HEALTH, title: 'Postnatal depression: where to get help', description: '', publishedAt: '2026-11-01T00:00:00Z', resourceId: { videoId: 'okvideo0001' } } },
    { snippet: { channelId: HEALTH, title: 'Private video', description: '', resourceId: { videoId: 'private0001' } } },
    { snippet: { channelId: HEALTH, title: 'IVF explained', description: '', resourceId: { videoId: 'ivfvideo001' } } },
    { snippet: { channelId: 'UCaaaaaaaaaaaaaaaaaaaaaa', title: 'Reposted elsewhere', description: '', resourceId: { videoId: 'otherchan01' } } },
  ];
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(url);
    return jsonResponse(url, url.includes('/playlistItems?') ? { items: uploads } : { items: [details('okvideo0001')] });
  };
  const items = await live.channelUploads(HEALTH, { fetchImpl, key: KEY, sources: config });
  assert.deepEqual(items.map((item) => item.video_id), ['okvideo0001']);
  assert.equal(new URL(calls[0]).searchParams.get('playlistId'), `UU${HEALTH.slice(2)}`);
  assert.equal(calls.length, 2, 'one page (no next token) + one details lookup');
  await assert.rejects(live.channelUploads('UCaaaaaaaaaaaaaaaaaaaaaa', { fetchImpl, key: KEY, sources: config }));
});

test('live feed merges recent trusted-channel uploads with search results and names the channel', async () => {
  const db = fakeDb({ cache: { 'calm:en': cached([]), 'learning:en': cached([]) } });
  const library = [
    { video_id: 'libvideo001', channel_id: HEALTH, kind: 'health', title: 'Postnatal depression: getting help', published_at: new Date(), duration_seconds: 200 },
    { video_id: 'libvideo002', channel_id: HEALTH, kind: 'health', title: 'IVF explained', published_at: new Date(), duration_seconds: 200 },
    { video_id: 'libvideo003', channel_id: 'UCaaaaaaaaaaaaaaaaaaaaaa', kind: 'health', title: 'Postnatal tips', published_at: new Date(), duration_seconds: 200 },
  ];
  const query = db.query;
  db.query = async (text, args) => /FROM content_live_library/.test(text) ? { rows: library } : query(text, args);
  const result = await withDb(db, { YOUTUBE_API_KEY: KEY }, () => service.liveFeed(db.userId, {}, { backgroundRefresh: false }));
  assert.deepEqual(result.items.map((item) => item.video_id), ['libvideo001']);
  assert.equal(result.items[0].channel_title, 'NHS');
});
