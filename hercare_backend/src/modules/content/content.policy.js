const { isIP } = require('node:net');
const { AppError } = require('../../middleware/error_handler');
const { isKnownActivity } = require('../therapy/therapy.catalog');

const CATEGORIES = Object.freeze(['quran', 'islamic', 'soothing', 'psychoeducation', 'bonding', 'game', 'activity']);
const FORMATS = Object.freeze(['article', 'audio', 'video', 'activity']);
const CONTENT_KEYS = Object.freeze(['title_en', 'title_ur', 'summary_en', 'summary_ur', 'body_en', 'body_ur',
  'category', 'format', 'audience', 'is_religious', 'is_music', 'media_url', 'source_url', 'source_name',
  'license_name', 'attribution', 'arabic_text', 'transliteration', 'verse_reference', 'activity_type', 'activity_id',
  'duration_seconds', 'tags', 'priority', 'available_from', 'available_until', 'review_after']);

function fail(message = 'Please check the content request.', status = 422) { throw new AppError(message, status); }
function onlyKeys(body, keys) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some((key) => !keys.includes(key))) fail();
}
function uuid(value) {
  if (typeof value !== 'string' || !/^[a-f\d]{8}-[a-f\d]{4}-[1-8][a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/i.test(value)) fail('A valid identifier is required.');
  return value.toLowerCase();
}
function integer(value, min, max) {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail();
  return value;
}
function enumValue(value, options) { if (!options.includes(value)) fail(); return value; }
function text(value, max, required = false) {
  if (value == null && !required) return null;
  if (typeof value !== 'string' || value.length > max || [...value].some((c) => {
    const code = c.codePointAt(0); return code === 127 || code < 32 && ![9, 10, 13].includes(code);
  })) fail();
  const result = value.trim();
  if (!result) { if (required) fail('Required content text is missing.'); return null; }
  // Catalog text is plain text, not HTML. Clients must render as text, never a webview.
  if (/<\/?(?:script|iframe|object|embed|style|html|img|a)(?:\s|>)/i.test(result)) fail('Use plain text, not HTML.');
  return result;
}
function bool(value) { if (typeof value !== 'boolean') fail(); return value; }
function allowedHosts() {
  return [...new Set((process.env.CONTENT_MEDIA_ALLOWED_HOSTS || '').split(',').map((s) => s.trim().toLowerCase()).filter((host) =>
    host && !isIP(host) && /^[a-z\d](?:[a-z\d.-]*[a-z\d])?$/.test(host) && host.includes('.') && !host.endsWith('.local')
      && !host.endsWith('.localhost') && !host.endsWith('.internal') && !host.split('.').includes('localhost')))];
}
function url(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || value.length > 2000 || /[\s\\]/u.test(value)
      || [...value].some((c) => c.codePointAt(0) < 32)) fail('Use a trusted HTTPS link.');
  let parsed;
  try { parsed = new URL(value); } catch { fail('Use a trusted HTTPS link.'); }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port || isIP(parsed.hostname)
      || !allowedHosts().includes(parsed.hostname.toLowerCase()) || parsed.hash) fail('This content host is not enabled.');
  // Do not attach health, user IDs, tracking identifiers, or callback redirects to media links.
  for (const key of parsed.searchParams.keys()) {
    if (!['v', 'list', 't', 'start', 'feature'].includes(key)) fail('Media links may not contain tracking or personal query parameters.');
  }
  return parsed.href;
}
function date(value) {
  if (value == null || value === '') return null;
  // node-postgres returns timestamptz columns as Date objects during publication revalidation.
  if (value instanceof Date) {
    if (!Number.isFinite(value.getTime())) fail('Use an ISO date and time.');
    return value.toISOString();
  }
  if (typeof value !== 'string') fail('Use an ISO date and time with a timezone.');
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2}))$/.exec(value);
  if (!match) fail('Use an ISO date and time with a timezone.');
  const [, yearText, monthText, dayText, hourText, minuteText, secondText] = match;
  const [year, month, day, hour, minute, second] = [yearText, monthText, dayText, hourText, minuteText, secondText].map(Number);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const offsetHour = Number(match[10] || 0), offsetMinute = Number(match[11] || 0);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > days[month - 1]
      || hour > 23 || minute > 59 || second > 59 || offsetHour > 14 || offsetMinute > 59
      || offsetHour === 14 && offsetMinute !== 0 || !Number.isFinite(Date.parse(value))) fail('Use a valid calendar date, time and timezone.');
  return new Date(value).toISOString();
}
function tags(value) {
  if (!Array.isArray(value) || value.length > 20 || value.some((s) => typeof s !== 'string' || !/^[a-z][a-z0-9_]{0,39}$/.test(s))) fail();
  return [...new Set(value)].sort();
}
function item(body) {
  onlyKeys(body, [...CONTENT_KEYS, 'client_request_id', 'version']);
  const data = {
    title_en: text(body.title_en, 180, true), title_ur: text(body.title_ur, 240, true),
    summary_en: text(body.summary_en, 800, true), summary_ur: text(body.summary_ur, 1000, true),
    body_en: text(body.body_en, 16000), body_ur: text(body.body_ur, 20000),
    category: enumValue(body.category, CATEGORIES), format: enumValue(body.format, FORMATS),
    audience: enumValue(body.audience, ['mother', 'guardian', 'both']),
    is_religious: bool(body.is_religious), is_music: bool(body.is_music),
    media_url: url(body.media_url), source_url: url(body.source_url),
    source_name: text(body.source_name, 180), license_name: text(body.license_name, 300), attribution: text(body.attribution, 1000),
    arabic_text: text(body.arabic_text, 6000), transliteration: text(body.transliteration, 6000), verse_reference: text(body.verse_reference, 80),
    activity_type: text(body.activity_type, 20), activity_id: text(body.activity_id, 40),
    duration_seconds: body.duration_seconds == null ? null : integer(body.duration_seconds, 1, 7200),
    tags: tags(body.tags || []), priority: body.priority == null ? 0 : integer(body.priority, 0, 100),
    available_from: date(body.available_from), available_until: date(body.available_until), review_after: date(body.review_after),
  };
  if (data.available_from && data.available_until && data.available_from >= data.available_until) fail('Availability dates are out of order.');
  if (data.format === 'activity') {
    if (!isKnownActivity(data.activity_type, data.activity_id) || data.media_url || data.is_music || data.audience !== 'mother') {
      fail('Select an existing in-app activity for mother accounts.');
    }
    if (data.category !== (data.activity_type === 'game' ? 'game' : 'activity')) fail('Activity categories must match the in-app activity.');
  } else if (data.activity_type || data.activity_id || ['activity', 'game'].includes(data.category)) fail();
  if (data.format === 'article' && (!data.body_en || !data.body_ur || data.media_url)) fail('Articles require English and Urdu text.');
  if (['audio', 'video'].includes(data.format) && (!data.media_url || !data.source_url || !data.source_name || !data.license_name || !data.attribution)) {
    fail('Media requires a source, rights statement and attribution.');
  }
  if (['quran', 'islamic'].includes(data.category) && !data.is_religious) fail('Religious content must respect the religious-content preference.');
  if (data.category === 'quran' && (!data.arabic_text || !data.transliteration || !data.verse_reference || data.is_music)) fail('Quran content requires Arabic, transliteration and a verse reference.');
  return data;
}
const INTEREST_KEYS = Object.freeze(['sleep', 'calm', 'music', 'low_mood', 'anxiety', 'feeding', 'body_recovery',
  'baby_bonding', 'relationships', 'faith', 'learning']);
// Optional lists: older app versions omit them and keep the stored choice (undefined).
function optionalList(value, allowed) {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > allowed.length || value.some((s) => !allowed.includes(s))) fail();
  return [...new Set(value)].sort();
}
function preferences(body) {
  onlyKeys(body, ['version', 'religious_enabled', 'music_enabled', 'disabled_categories', 'interests', 'preferred_formats']);
  const disabled = body.disabled_categories;
  if (!Array.isArray(disabled) || disabled.length > CATEGORIES.length || disabled.some((s) => !CATEGORIES.includes(s))) fail();
  return { version: integer(body.version, 0, 2147483646), religious_enabled: bool(body.religious_enabled), music_enabled: bool(body.music_enabled),
    disabled_categories: [...new Set(disabled)].sort(), interests: optionalList(body.interests, INTEREST_KEYS),
    preferred_formats: optionalList(body.preferred_formats, FORMATS) };
}
function listQuery(query, admin = false, maxLimit = 30) {
  onlyKeys(query, admin ? ['status', 'limit', 'offset'] : ['language', 'limit']);
  const parse = (value, fallback, min, max) => value == null ? fallback : /^\d+$/.test(String(value)) ? integer(Number(value), min, max) : fail();
  return admin ? { status: query.status == null ? null : enumValue(query.status, ['draft', 'reviewed', 'published', 'archived']),
    limit: parse(query.limit, 50, 1, 100), offset: parse(query.offset, 0, 0, 100000) }
    : { language: query.language == null ? 'en' : enumValue(query.language, ['en', 'ur']), limit: parse(query.limit, 20, 1, maxLimit) };
}

module.exports = { CATEGORIES, FORMATS, INTEREST_KEYS, CONTENT_KEYS, onlyKeys, uuid, integer, enumValue, text, bool, item, preferences, listQuery, allowedHosts, url, fail };
