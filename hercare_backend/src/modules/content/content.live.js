// Live YouTube search, hardened for a postpartum mental-health audience.
//
// Safety model (all server side; the API key never reaches the phone):
//  1. Queries are fixed per topic. No user text, health data or account ID is sent to YouTube.
//  2. Only channels in content-catalog/live-sources.json are kept, and each channel may only
//     appear under topics suited to its kind (health / calm / music / faith).
//  3. YouTube SafeSearch=strict, public + embeddable only, no live streams, no Shorts,
//     no age-restricted or Pakistan-blocked videos, bounded duration.
//  4. Titles/descriptions with harmful or miracle-cure terms are dropped.
//  5. Results are cached per topic+language (shared, contains no personal data) so quota use is
//     bounded; music/faith need her opt-ins; an open crisis returns nothing.
//  6. She can hide any video; a video hidden by 3+ mothers is hidden for everyone.
const { readFileSync, statSync } = require('node:fs');
const { join } = require('node:path');
const sources = require('./content.sources');

const API = 'https://www.googleapis.com/youtube/v3';
const SOURCES_PATH = process.env.CONTENT_LIVE_SOURCES || join(__dirname, '../../../content-catalog/live-sources.json');
const TIMEOUT_MS = 8000;
const RESPONSE_LIMIT = 512 * 1024;
const MAX_REFRESHES_PER_HOUR = 40; // 100 quota units each: stays well under the 10,000/day default.
const FAILURE_BACKOFF_MS = 15 * 60 * 1000;
const STALE_LIMIT_HOURS = 72;
const GLOBAL_HIDE_THRESHOLD = 3;
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const CHANNEL_ID = /^UC[A-Za-z0-9_-]{22}$/;

// Fixed queries. Changing these is a code review, never runtime input.
const TOPICS = Object.freeze({
  low_mood: { kinds: ['health', 'calm'], en: 'postnatal depression support what helps', ur: 'postpartum depression urdu' },
  anxiety: { kinds: ['health', 'calm'], en: 'postpartum anxiety calming techniques', ur: 'anxiety ka ilaj urdu doctor' },
  sleep: { kinds: ['health', 'calm', 'music'], en: 'sleep relaxation for new mothers', ur: 'neend ke masail urdu' },
  calm: { kinds: ['calm', 'music'], en: 'guided breathing meditation relaxation', ur: 'relaxation breathing exercise urdu' },
  music: { kinds: ['music'], en: 'relaxing calm music', ur: 'relaxing calm music' },
  feeding: { kinds: ['health'], en: 'breastfeeding positioning attachment', ur: 'breastfeeding tips urdu' },
  body_recovery: { kinds: ['health'], en: 'postnatal recovery caesarean pelvic floor', ur: 'c section recovery urdu' },
  baby_bonding: { kinds: ['health', 'music'], en: 'bonding with your newborn baby', ur: 'newborn baby care urdu' },
  relationships: { kinds: ['health'], en: 'how partners can support postnatal depression', ur: 'postpartum depression husband support urdu' },
  faith: { kinds: ['faith'], en: 'quran recitation calm', ur: 'quran tilawat sukoon' },
  learning: { kinds: ['health'], en: 'perinatal mental health baby blues', ur: 'zachgi ke baad depression urdu' },
});
const REASONS = Object.freeze({
  low_mood: ['Live from a trusted channel, for lower days.', 'مشکل دنوں کے لیے، بھروسے مند چینل سے تازہ۔'],
  anxiety: ['Live from a trusted channel, about worry and calm.', 'فکر اور سکون کے بارے میں، بھروسے مند چینل سے تازہ۔'],
  sleep: ['Live from a trusted channel, for rest and sleep.', 'آرام اور نیند کے لیے، بھروسے مند چینل سے تازہ۔'],
  calm: ['Live from a trusted channel, for a calm moment.', 'پرسکون لمحے کے لیے، بھروسے مند چینل سے تازہ۔'],
  music: ['Live from a trusted music channel you allowed.', 'آپ کی اجازت سے، بھروسے مند موسیقی چینل سے تازہ۔'],
  feeding: ['Live from a trusted health channel, about feeding.', 'دودھ پلانے کے بارے میں، بھروسے مند طبی چینل سے تازہ۔'],
  body_recovery: ['Live from a trusted health channel, about recovery.', 'جسمانی بحالی کے بارے میں، بھروسے مند طبی چینل سے تازہ۔'],
  baby_bonding: ['Live from a trusted channel, about you and your baby.', 'آپ اور بچے کے تعلق پر، بھروسے مند چینل سے تازہ۔'],
  relationships: ['Live from a trusted channel, about family support.', 'خاندانی تعاون کے بارے میں، بھروسے مند چینل سے تازہ۔'],
  faith: ['Live recitation from a trusted channel you allowed.', 'آپ کی اجازت سے، بھروسے مند چینل سے تازہ تلاوت۔'],
  learning: ['Live from a trusted health channel, to understand what you feel.', 'اپنے احساسات سمجھنے کے لیے، بھروسے مند طبی چینل سے تازہ۔'],
});
// Words that should never reach a vulnerable mother through an unreviewed result.
const BLOCKED_TERMS = [
  /\bsuicid/i, /\bself[- ]?harm/i, /\bkill(ed|ing|s)?\b/i, /\bdie\b|\bdied\b|\bdeath\b/i, /\bmurder/i, /\babuse\b/i,
  /\bmiracle\b/i, /\bcure[sd]?\b/i, /\bguarantee/i, /\binstant(ly)? (heal|relief|cure)/i, /\b100 ?%/i,
  /\bwazifa\b/i, /\bwazaif\b/i, /\btaweez\b/i, /\bta'?wiz\b/i, /\bblack magic\b/i, /\bkala jadu\b/i, /\bjadu\b/i, /\bjinn?\b/i,
  /\bsubliminal\b/i, /\bhypnosis\b/i, /\bmanifest(ing|ation)?\b/i, /\bstop (taking )?(your )?(medication|medicine|antidepressants?)/i,
  /\bdetox\b/i, /\bprank\b/i, /\bhorror\b/i, /\bscary\b/i, /\bshocking\b/i, /\bexposed\b/i, /\bscandal/i,
  /\bweight ?loss\b/i, /\blose \d+ ?(kg|lbs?|pounds)/i, /\bdiet pill/i, /\bsponsored\b/i, /#shorts?\b/i,
  /خودکشی/, /جادو/, /تعویذ/, /وظیفہ/,
];
// Wrong stage for mothers after birth, or potentially distressing when unasked for
// (fertility, pregnancy tests, loss). Trusted channels publish these too, so they are filtered here.
const OFF_AUDIENCE = [
  /\bivf\b/i, /\bfertil/i, /\binfertil/i, /\bconceiv/i, /\bget(ting)? pregnant\b/i, /\bpregnancy test\b/i, /\bplan(ning)? (a |the )?pregnan/i,
  /\bovulat/i, /\bmiscarr/i, /\bstillbirth\b/i, /\bbaby loss\b/i, /\babortion\b/i, /\bectopic\b/i, /\btermination\b/i,
  /\bacupuncture\b/i, /\btrimester\b/i, /\bheartbreak\b/i, /\bnicu\b/i, /\bgrief\b/i, /\bloss of\b/i, /\blabou?r (pain|induction)\b/i, /\bpregnancy kab\b/i, /\bhamal\b/i, /\bbaanjh/i, /\bbe ?aulad/i,
];
const POSTPARTUM_CONTEXT = /\b(postpartum|postnatal|post-natal|after (birth|delivery|pregnancy|baby)|new (mum|mom|mother)s?|delivery ke ba(a)?d|zachgi|chilla|newborn)\b/i;
function offAudience(title) {
  if (OFF_AUDIENCE.some((pattern) => pattern.test(title))) return true;
  // Pregnancy-only content (scans, bump, birth plans) is the wrong stage unless it is about after birth.
  return /\bpregnan/i.test(title) && !POSTPARTUM_CONTEXT.test(title);
}
const KIND_CATEGORY = Object.freeze({ health: 'psychoeducation', calm: 'soothing', music: 'soothing', faith: 'islamic' });

let sourcesCache = { mtime: 0, value: null, checkedAt: 0 };
function loadSources(path = SOURCES_PATH, now = Date.now()) {
  if (sourcesCache.value && now - sourcesCache.checkedAt < 60000) return sourcesCache.value;
  const mtime = statSync(path).mtimeMs;
  if (sourcesCache.value && mtime === sourcesCache.mtime) { sourcesCache.checkedAt = now; return sourcesCache.value; }
  const raw = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
  if (!Array.isArray(raw.channels) || raw.channels.length > 500) throw new Error('Invalid live sources.');
  const channels = new Map();
  for (const channel of raw.channels) {
    if (!CHANNEL_ID.test(channel?.id) || !KIND_CATEGORY[channel.kind] || typeof channel.name !== 'string') throw new Error('Invalid live source channel.');
    channels.set(channel.id, { name: channel.name.slice(0, 120), kind: channel.kind });
  }
  const blockedVideos = new Set((raw.blocked_videos || []).filter((id) => VIDEO_ID.test(id)));
  const blockedTerms = (raw.blocked_terms || []).filter((term) => typeof term === 'string' && term.trim() && term.length <= 80)
    .map((term) => term.trim().toLowerCase());
  const value = { channels, blockedVideos, blockedTerms };
  sourcesCache = { mtime, value, checkedAt: now };
  return value;
}

function enabled(env = process.env) {
  const key = env.YOUTUBE_API_KEY;
  return env.CONTENT_LIVE_SEARCH !== 'off' && typeof key === 'string' && /^[A-Za-z0-9_-]{20,100}$/.test(key);
}
function decodeEntities(value) {
  return value.replace(/&(#\d+|#x[0-9a-f]+|amp|lt|gt|quot|apos|#39);/gi, (match, code) => {
    const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }[code.toLowerCase()];
    if (named) return named;
    const number = code[1]?.toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
    return Number.isInteger(number) && number > 31 && number < 0x110000 ? String.fromCodePoint(number) : '';
  });
}
// Untrusted text from YouTube: plain text, no control/bidi-override characters, bounded.
function cleanText(value, max) {
  if (typeof value !== 'string') return '';
  // eslint-disable-next-line no-control-regex -- deliberately strips control characters from untrusted text
  return decodeEntities(value).replace(/[\u0000-\u001f\u007f‪-‮⁦-⁩]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}
function durationSeconds(iso) {
  const match = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso || '');
  if (!match) return null;
  return Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0);
}
function blocked(text, extraTerms = []) {
  const lower = text.toLowerCase();
  return BLOCKED_TERMS.some((pattern) => pattern.test(text)) || extraTerms.some((term) => lower.includes(term));
}

async function youtube(path, params, { fetchImpl = globalThis.fetch, key = process.env.YOUTUBE_API_KEY } = {}) {
  const url = `${API}/${path}?${new URLSearchParams(params)}`;
  let response;
  try {
    // Key in a header, never the URL, so it cannot leak into logs, proxies or error text.
    response = await fetchImpl(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { Accept: 'application/json', 'X-Goog-Api-Key': key } });
    if (!response.ok || response.redirected) throw new Error('unavailable');
    return await sources.readJSON(response, RESPONSE_LIMIT);
  } catch {
    throw new Error('YouTube live search is unavailable.');
  } finally {
    if (response?.body && !response.body.locked) await response.body.cancel().catch(() => {});
  }
}

// One search (100 quota units) + one details lookup (1 unit) for a topic and language.
async function searchTopic(topic, language, options = {}) {
  const rule = TOPICS[topic];
  if (!rule) throw new Error('Unknown live topic.');
  const config = options.sources || loadSources();
  const search = await youtube('search', { part: 'snippet', type: 'video', safeSearch: 'strict', videoEmbeddable: 'true',
    videoSyndicated: 'true', maxResults: '50', q: rule[language] || rule.en, relevanceLanguage: language === 'ur' ? 'ur' : 'en',
    regionCode: 'PK' }, options);
  const candidates = new Map();
  for (const entry of Array.isArray(search?.items) ? search.items : []) {
    const id = entry?.id?.videoId; const snippet = entry?.snippet || {};
    const channel = config.channels.get(snippet.channelId);
    if (entry?.id?.kind !== 'youtube#video' || !VIDEO_ID.test(id || '') || !channel || !rule.kinds.includes(channel.kind)
        || snippet.liveBroadcastContent !== 'none' || config.blockedVideos.has(id)) continue;
    const title = cleanText(snippet.title, 200);
    if (!title || offAudience(title) || blocked(`${title} ${cleanText(snippet.description, 500)}`, config.blockedTerms)) continue;
    candidates.set(id, { video_id: id, title, channel_id: snippet.channelId, channel_title: channel.name, kind: channel.kind,
      published_at: typeof snippet.publishedAt === 'string' ? snippet.publishedAt.slice(0, 30) : null });
  }
  return (await checkDetails(candidates, options)).slice(0, 12);
}
// Second gate for every candidate (search or channel uploads): public, embeddable, processed,
// not age-restricted, available in Pakistan, not a Short, bounded length. 1 quota unit per 50.
async function checkDetails(candidates, options = {}) {
  const ids = [...candidates.keys()]; const items = [];
  for (let start = 0; start < ids.length; start += 50) {
    const details = await youtube('videos', { part: 'contentDetails,status', id: ids.slice(start, start + 50).join(','), maxResults: '50' }, options);
    for (const video of Array.isArray(details?.items) ? details.items : []) {
      const candidate = candidates.get(video?.id);
      const status = video?.status || {}; const content = video?.contentDetails || {};
      const seconds = durationSeconds(content.duration);
      const region = content.regionRestriction || {};
      if (!candidate || status.privacyStatus !== 'public' || status.embeddable !== true || status.uploadStatus !== 'processed'
          || content.contentRating?.ytRating === 'ytAgeRestricted'
          || (Array.isArray(region.blocked) && region.blocked.includes('PK'))
          || (Array.isArray(region.allowed) && !region.allowed.includes('PK'))
          || seconds == null || seconds < 60 || seconds > (candidate.kind === 'music' || candidate.kind === 'faith' ? 4 * 3600 : 3600)) continue;
      items.push({ ...candidate, duration_seconds: seconds });
    }
  }
  return items;
}
// Recent uploads of one trusted channel via its uploads playlist (1 unit per 50 videos), filtered
// through the same text and details gates. This is the main source for English topics, where a
// broad search mostly returns small unknown channels that the allowlist (correctly) rejects.
async function channelUploads(channelId, options = {}, pages = 4) {
  const config = options.sources || loadSources();
  const channel = config.channels.get(channelId);
  if (!channel) throw new Error('Unknown live channel.');
  const candidates = new Map(); let pageToken;
  for (let page = 0; page < pages; page++) {
    const list = await youtube('playlistItems', { part: 'snippet', playlistId: `UU${channelId.slice(2)}`, maxResults: '50',
      ...(pageToken ? { pageToken } : {}) }, options);
    for (const entry of Array.isArray(list?.items) ? list.items : []) {
      const snippet = entry?.snippet || {}; const id = snippet.resourceId?.videoId;
      if (!VIDEO_ID.test(id || '') || snippet.channelId !== channelId || config.blockedVideos.has(id)) continue;
      const title = cleanText(snippet.title, 200);
      if (!title || /^(private|deleted) video$/i.test(title) || offAudience(title) || blocked(`${title} ${cleanText(snippet.description, 500)}`, config.blockedTerms)) continue;
      candidates.set(id, { video_id: id, title, channel_id: channelId, channel_title: channel.name, kind: channel.kind,
        published_at: typeof snippet.publishedAt === 'string' ? snippet.publishedAt.slice(0, 30) : null });
    }
    pageToken = typeof list?.nextPageToken === 'string' ? list.nextPageToken : null;
    if (!pageToken) break;
  }
  return candidates.size ? checkDetails(candidates, options) : [];
}
// Which library videos fit a topic: channel kind must suit the topic, and the title must
// mention the topic (music/faith channels: any calm title, since the channel itself is the match).
const TOPIC_KEYWORDS = Object.freeze({
  low_mood: ['postnatal depression', 'postpartum depression', 'perinatal', 'baby blues', 'low mood', 'depression', 'mental health', 'feeling low', 'sad'],
  anxiety: ['anxiety', 'anxious', 'worry', 'panic', 'stress', 'ocd', 'intrusive', 'overwhelm', 'calm down'],
  sleep: ['sleep', 'insomnia', 'bedtime', 'neend', 'rest', 'tired', 'night'],
  calm: ['breath', 'meditation', 'meditate', 'mindful', 'relax', 'calm', 'body scan', 'rain', 'soothing', 'peace', 'stress'],
  music: ['relax', 'calm', 'sleep', 'piano', 'lullab', 'peace', 'sooth', 'meditation', 'spa', 'nature', 'healing', 'ambient', 'stress'],
  feeding: ['breastfeed', 'breast feed', 'breastfeeding', 'baby feeding', 'feeding your baby', 'latch', 'breast milk',
    'maa ka doodh', 'mother\'s milk', 'formula feeding', 'bottle feeding', 'infant feeding'],
  body_recovery: ['caesarean', 'cesarean', 'c-section', 'c section', 'pelvic floor', 'postnatal exercise', 'postpartum exercise',
    'recovery after', 'after delivery', 'delivery ke baad', 'stitches', 'episiotomy', 'physio', 'chilla', 'postpartum care'],
  baby_bonding: ['bonding', 'skin to skin', 'skin-to-skin', 'newborn', 'baby care', 'lullab', 'cuddle', 'baby massage', 'safe sleep', 'safer sleep'],
  relationships: ['partner', 'husband', 'dads', 'father', 'family support', 'supporting a', 'support someone'],
  faith: ['surah', 'quran', 'recitation', 'tilawat', 'ayat', 'ayatul', 'dua', 'سورة', 'سورۃ'],
  learning: ['postnatal', 'postpartum', 'perinatal', 'after birth', 'after childbirth', 'after delivery', 'after pregnancy',
    'maternal mental', 'maternal wellbeing', 'new mum', 'new mom', 'baby blues', 'delivery ke baad', 'zachgi', 'chilla'],
});
function matchesTopic(item, topic) {
  const rule = TOPICS[topic];
  if (!rule?.kinds.includes(item.kind) || offAudience(item.title)) return false;
  const title = item.title.toLowerCase();
  return TOPIC_KEYWORDS[topic].some((word) => title.includes(word));
}

// Topic choice: her chosen interests first, then what today's state suggests, then gentle defaults.
// Music/faith only with her opt-ins; at most 3 topics per request to bound latency and quota.
function topicsFor({ role, preferences, contextTags = [] }) {
  const allowed = (topic) => (topic !== 'music' || preferences.music_enabled) && (topic !== 'faith' || preferences.religious_enabled)
    && TOPICS[topic].kinds.some((kind) => !preferences.disabled_categories.includes(KIND_CATEGORY[kind])
      && (kind !== 'music' || preferences.music_enabled) && (kind !== 'faith' || preferences.religious_enabled));
  if (role === 'guardian') return ['relationships', 'learning'];
  const fromContext = { low_mood: 'low_mood', mood_declining: 'low_mood', sleep_support: 'sleep', screen_break: 'calm', education: 'learning' };
  const ordered = [...(preferences.interests || []), ...contextTags.map((tag) => fromContext[tag]).filter(Boolean), 'calm', 'learning'];
  return [...new Set(ordered)].filter((topic) => TOPICS[topic] && allowed(topic)).slice(0, 3);
}

function publicItem(item, topic, language) {
  const reason = REASONS[topic];
  return { video_id: item.video_id, title: item.title, channel_title: item.channel_title, duration_seconds: item.duration_seconds,
    published_at: item.published_at, topic, is_music: item.kind === 'music', is_religious: item.kind === 'faith',
    category: KIND_CATEGORY[item.kind], media_url: `https://www.youtube.com/watch?v=${item.video_id}`,
    thumbnail_url: `https://i.ytimg.com/vi/${item.video_id}/hqdefault.jpg`, reviewed: false,
    reason_en: reason[0], reason_ur: reason[1], language };
}
// Eligibility re-check at read time: config edits (removed channel, blocked video/term) apply to cached rows immediately.
function stillAllowed(item, topic, preferences, config) {
  const channel = config.channels.get(item.channel_id);
  return !!channel && channel.kind === item.kind && TOPICS[topic].kinds.includes(channel.kind)
    && !config.blockedVideos.has(item.video_id) && !blocked(item.title, config.blockedTerms) && !offAudience(item.title)
    && (item.kind !== 'music' || preferences.music_enabled) && (item.kind !== 'faith' || preferences.religious_enabled)
    && !preferences.disabled_categories.includes(KIND_CATEGORY[item.kind]);
}

module.exports = { TOPICS, REASONS, BLOCKED_TERMS, MAX_REFRESHES_PER_HOUR, FAILURE_BACKOFF_MS, STALE_LIMIT_HOURS,
  GLOBAL_HIDE_THRESHOLD, VIDEO_ID, TOPIC_KEYWORDS, loadSources, enabled, cleanText, durationSeconds, blocked, youtube, searchTopic,
  checkDetails, channelUploads, matchesTopic, offAudience,
  topicsFor, publicItem, stillAllowed, _reset: () => { sourcesCache = { mtime: 0, value: null, checkedAt: 0 }; } };
