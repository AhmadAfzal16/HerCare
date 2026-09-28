const { randomBytes } = require('node:crypto');
const { AppError } = require('../../middleware/error_handler');
const { analyzeJournal } = require('../mood/journal_analysis');

const RULES_VERSION = '2026-09-v1';
const TOPICS = ['coping', 'recovery', 'family', 'bonding', 'medication'];
const REACTIONS = ['heart', 'hug', 'support', 'solidarity'];
const REPORT_REASONS = ['bullying', 'self_harm', 'spam', 'privacy', 'medical_advice', 'other'];
const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
function uuid(value) { if (typeof value !== 'string' || !uuidPattern.test(value)) throw new AppError('Invalid identifier.', 422); return value; }
function text(value, min, max) {
  if (typeof value !== 'string') throw new AppError('Text is required.', 422);
  const normalized = value.normalize('NFKC').replace(/[\u200B-\u200D\u202A-\u202E\u2066-\u2069\uFEFF]/gu, '').trim();
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
function decodeCursor(value) {
  if (!value) return null;
  try {
    if (typeof value !== 'string' || value.length > 300) throw new Error();
    const parsed = JSON.parse(Buffer.from(value, 'base64url').toString());
    if (!Array.isArray(parsed) || parsed.length !== 2 || typeof parsed[0] !== 'string' || !Number.isFinite(Date.parse(parsed[0]))) throw new Error();
    uuid(parsed[1]);
    return parsed;
  } catch { throw new AppError('Invalid page cursor.', 422); }
}
function rules(content) {
  const analysis = analyzeJournal(content);
  const flags = [];
  if (analysis.containsDanger) flags.push('self_harm');
  if (/(https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\+?\d[\d\s()-]{8,}\d)/iu.test(content)) flags.push('privacy_or_link');
  if (/\b(kill yourself|stupid|worthless|idiot|buy now|guaranteed cure)\b|بے\s*وقوف|نفرت|خریدیں/iu.test(content)) flags.push('abuse_or_spam');
  if (/(.)\1{12,}/u.test(content)) flags.push('spam');
  return { language: analysis.language, flags, safety_support: analysis.containsDanger, version: 'community-rules-v1' };
}

async function moderate(content, fetcher = fetch) {
  const local = rules(content);
  // Human review is required before any member content becomes public.
  const result = { ...local, ai: 'unavailable' };
  const endpoint = process.env.COMMUNITY_MODERATION_URL;
  if (!endpoint) return result;
  try {
    const url = new URL(endpoint);
    if (process.env.NODE_ENV === 'production' && url.protocol !== 'https:') return result;
    const response = await fetcher(url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(6000),
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.ML_SERVICE_TOKEN || ''}` },
      body: JSON.stringify({ text: content }),
    });
    if (!response.ok) return result;
    const value = await response.json();
    if (!value.scores || typeof value.model_version !== 'string') return result;
    const scores = {};
    for (const key of ['self_harm', 'bullying', 'spam', 'medical_advice', 'support']) {
      if (typeof value.scores[key] !== 'number' || !Number.isFinite(value.scores[key]) || value.scores[key] < 0 || value.scores[key] > 1) return result;
      scores[key] = value.scores[key];
    }
    return { ...result, ai: 'available', model_version: value.model_version.slice(0, 150), scores,
      safety_support: local.safety_support || scores.self_harm >= 0.5 };
  } catch { return result; }
}
module.exports = { RULES_VERSION, TOPICS, REACTIONS, REPORT_REASONS, uuid, text, onlyKeys, alias, encodeCursor, decodeCursor, rules, moderate };
