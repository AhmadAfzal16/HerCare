const { randomBytes, createHash } = require('node:crypto');
const { AppError } = require('../../middleware/error_handler');
const { analyzeJournal } = require('../mood/journal_analysis');

const RULES_VERSION = '2026-09-v1';
const TOPICS = ['coping', 'recovery', 'family', 'bonding', 'medication'];
const REACTIONS = ['heart', 'hug', 'support', 'solidarity'];
const REPORT_REASONS = ['bullying', 'self_harm', 'spam', 'privacy', 'medical_advice', 'other'];
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
function uuid(value) { if (typeof value !== 'string' || !uuidPattern.test(value)) throw new AppError('Invalid identifier.', 422); return value.toLowerCase(); }
function text(value, min, max) {
  if (typeof value !== 'string') throw new AppError('Text is required.', 422);
  const normalized = value.normalize('NFKC').replace(/[\u200B-\u200D\u202A-\u202E\u2066-\u2069\uFEFF]/gu, '').trim();
  if (Array.from(normalized).some((character) => {
    const point = character.codePointAt(0);
    return (point < 32 && ![9, 10, 13].includes(point)) || (point >= 127 && point <= 159);
  })) throw new AppError('Text contains unsupported control characters.', 422);
  if (normalized.length < min || normalized.length > max) throw new AppError(`Text must be ${min}–${max} characters.`, 422);
  return normalized;
}
function onlyKeys(body, keys) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some((key) => !keys.includes(key))) {
    throw new AppError('Unexpected request fields.', 422);
  }
}
function alias() { return `Kind ${['Lotus', 'Willow', 'Daisy', 'Olive'][randomBytes(1)[0] % 4]} ${randomBytes(5).toString('hex')}`; }
function encodeCursor(row) { return Buffer.from(JSON.stringify([row.cursor_time, row.id])).toString('base64url'); }
function validTimestamp(value, requireSeconds = true) {
  if (typeof value !== 'string') return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}(?::\d{2})?)$/.exec(value);
  if (!match || (requireSeconds && match[6] === undefined)) return false;
  const year = Number(match[1]); const month = Number(match[2]); const day = Number(match[3]);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const offset = match[8] === 'Z' ? [0, 0] : match[8].slice(1).split(':').map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > days[month - 1]
    || Number(match[4]) > 23 || Number(match[5]) > 59 || Number(match[6] || 0) > 59
    || offset[0] > 14 || (offset[1] || 0) > 59 || (offset[0] === 14 && (offset[1] || 0) !== 0)) return false;
  return Number.isFinite(Date.parse(value));
}
function decodeCursor(value) {
  if (value === undefined || value === null) return null;
  try {
    if (typeof value !== 'string' || !value.length || value.length > 300 || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error();
    const bytes = Buffer.from(value, 'base64url');
    if (bytes.toString('base64url') !== value) throw new Error();
    const parsed = JSON.parse(bytes.toString('utf8'));
    // Accept PostgreSQL's exact microsecond timestamp, not free-form Date.parse values.
    if (!Array.isArray(parsed) || parsed.length !== 2 || !validTimestamp(parsed[0])) throw new Error();
    parsed[1] = uuid(parsed[1]);
    if (encodeCursor({ cursor_time: parsed[0], id: parsed[1] }) !== value) throw new Error();
    return parsed;
  } catch { throw new AppError('Invalid page cursor.', 422); }
}
function pageOptions(value) {
  onlyKeys(value, ['parent_id', 'topic', 'session_id', 'mine', 'include_replies', 'cursor']);
  for (const key of ['mine', 'include_replies']) {
    if (value[key] !== undefined && !['true', 'false'].includes(value[key])) throw new AppError('Invalid community filter.', 422);
  }
  if (value.include_replies === 'true' && (value.mine !== 'true' || value.parent_id !== undefined)) {
    throw new AppError('Reply history is only available in your own posts.', 422);
  }
  return value;
}
function submission(body) {
  onlyKeys(body, ['title', 'body', 'topic', 'parent_id', 'session_id', 'client_request_id']);
  const parentId = body.parent_id === undefined ? null : uuid(body.parent_id);
  const sessionId = body.session_id === undefined ? null : uuid(body.session_id);
  const title = parentId ? '' : text(body.title, 3, 120);
  const content = text(body.body, 2, 2000);
  if (body.topic !== undefined && !TOPICS.includes(body.topic)) throw new AppError('Choose a community topic.', 422);
  if (!parentId && !TOPICS.includes(body.topic)) throw new AppError('Choose a community topic.', 422);
  // No private text is stored in this digest. Scope it to the exact normalized submission.
  const fingerprint = createHash('sha256').update(JSON.stringify([title, content, body.topic || null, parentId, sessionId])).digest('hex');
  return { requestId: uuid(body.client_request_id), title, content, topic: body.topic, parentId, sessionId, fingerprint };
}
function rules(content) {
  const analysis = analyzeJournal(content);
  const flags = [];
  // Broad context-only support hints, not a diagnosis or an automatic guardian alert.
  // A negation/quotation may still be queued for a human to interpret safely.
  const endingLife = /\bending\s+(?:my|own)\s+life\b|اپنی\s*زندگی\s*ختم|زندگی\s*(?:ختم|کا\s*خاتمہ)|\b(?:apni|meri)\s+zindagi\s+(?:khatam|khatm)\b/iu.test(content);
  const safetySupport = analysis.containsDanger || endingLife;
  if (safetySupport) flags.push('self_harm');
  const privacyText = content.replace(/[٠-٩۰-۹]/gu, (digit) => String(digit.codePointAt(0) & 15));
  if (/(https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\+?\d[\d\s()-]{8,}\d)/iu.test(privacyText)) flags.push('privacy_or_link');
  if (/\b(kill yourself|stupid|worthless|idiot|buy now|guaranteed cure)\b|بے\s*وقوف|نفرت|خریدیں/iu.test(content)) flags.push('abuse_or_spam');
  if (/(.)\1{12,}/u.test(content)) flags.push('spam');
  return { language: analysis.language, flags, safety_support: safetySupport, version: 'community-rules-v2' };
}

function aiRequired() {
  if (process.env.COMMUNITY_AI_REQUIRED === 'false') return false;
  return process.env.COMMUNITY_AI_REQUIRED === 'true' || process.env.NODE_ENV === 'production';
}
function configuredEndpoint() {
  return process.env.COMMUNITY_MODERATION_URL
    || (process.env.ML_SERVICE_URL ? `${process.env.ML_SERVICE_URL.replace(/\/$/, '')}/v1/community/moderate` : null);
}
function endpointUrl(ready = false) {
  const endpoint = configuredEndpoint();
  if (!endpoint || !process.env.ML_SERVICE_TOKEN?.trim()) return null;
  try {
    const url = new URL(endpoint);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.hash
      || (process.env.NODE_ENV === 'production' && url.protocol !== 'https:')) return null;
    if (ready) {
      url.pathname = url.pathname.replace(/\/moderate\/?$/, '/ready');
      if (!url.pathname.endsWith('/ready')) return null;
      url.search = '';
    }
    return url;
  } catch { return null; }
}
function modelMetadata(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || value.full_text_processed !== true || value.clinical_validation !== false) return null;
  const metadata = {};
  for (const key of ['model_version', 'policy_version', 'runtime']) {
    if (typeof value[key] !== 'string' || !value[key].trim() || value[key].length > 150
      || Array.from(value[key]).some((character) => character.codePointAt(0) < 32)) return null;
    metadata[key] = value[key];
  }
  return { ...metadata, clinical_validation: false, full_text_processed: true };
}
async function requestAi(url, fetcher, body) {
  return fetcher(url, {
    method: body === undefined ? 'GET' : 'POST', redirect: 'error', signal: AbortSignal.timeout(6000),
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.ML_SERVICE_TOKEN}` },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
async function readiness(fetcher = fetch) {
  const result = { required: aiRequired(), configured: !!configuredEndpoint(),
    ready: false, human_review_required: true, clinical_validation: false };
  const url = endpointUrl(true);
  if (!url) return result;
  try {
    const response = await requestAi(url, fetcher);
    if (!response.ok) return result;
    const value = await response.json();
    const metadata = modelMetadata(value);
    return value.status === 'ready' && metadata ? { ...result, ...metadata, ready: true } : result;
  } catch { return result; }
}
async function moderate(content, fetcher = fetch) {
  const local = rules(content);
  // Human review is required before any member content becomes public.
  const result = { ...local, ai: 'unavailable', analyzed_at: new Date().toISOString() };
  const url = endpointUrl();
  if (!url) return result;
  try {
    const response = await requestAi(url, fetcher, { text: content });
    if (!response.ok) return result;
    const value = await response.json();
    const metadata = modelMetadata(value);
    if (!metadata || !value.scores || typeof value.scores !== 'object' || Array.isArray(value.scores)) return result;
    const scores = {};
    for (const key of ['self_harm', 'bullying', 'spam', 'medical_advice', 'support']) {
      if (typeof value.scores[key] !== 'number' || !Number.isFinite(value.scores[key]) || value.scores[key] < 0 || value.scores[key] > 1) return result;
      scores[key] = value.scores[key];
    }
    return { ...result, ...metadata, ai: 'available', scores,
      safety_support: local.safety_support || scores.self_harm >= 0.5 };
  } catch { return result; }
}
module.exports = { RULES_VERSION, TOPICS, REACTIONS, REPORT_REASONS, uuid, text, onlyKeys, alias,
  encodeCursor, decodeCursor, validTimestamp, pageOptions, submission, rules, aiRequired, modelMetadata, readiness, moderate };
