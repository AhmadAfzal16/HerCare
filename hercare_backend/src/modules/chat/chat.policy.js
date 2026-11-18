const { AppError } = require('../../middleware/error_handler');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TIMESTAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{6})Z$/;

function invalid() { throw new AppError('Invalid chat request.', 422); }

function uuid(value) {
  if (typeof value !== 'string' || !UUID.test(value.toLowerCase())) invalid();
  return value.toLowerCase();
}

function timestamp(value) {
  if (typeof value !== 'string') invalid();
  const match = TIMESTAMP.exec(value);
  if (!match) invalid();
  const [, year, month, day, hour, minute, second] = match;
  const y = Number(year); const m = Number(month); const d = Number(day);
  const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (y < 1 || m < 1 || m > 12 || d < 1 || d > days[m - 1]
      || Number(hour) > 23 || Number(minute) > 59 || Number(second) > 59) invalid();
  return value;
}

function encodeCursor(conversationId, row) {
  return Buffer.from(JSON.stringify({ v: 1, c: uuid(conversationId), t: timestamp(row.created_at_exact), i: uuid(row.id) }))
    .toString('base64url');
}

function decodeCursor(value, conversationId) {
  if (typeof value !== 'string' || value.length < 30 || value.length > 300 || !/^[A-Za-z0-9_-]+$/.test(value)) invalid();
  const bytes = Buffer.from(value, 'base64url');
  if (bytes.toString('base64url') !== value) invalid();
  let parsed;
  try { parsed = JSON.parse(bytes.toString('utf8')); } catch { invalid(); }
  if (!parsed || Array.isArray(parsed) || Object.keys(parsed).sort().join(',') !== 'c,i,t,v' || parsed.v !== 1) invalid();
  const cursor = { conversation_id: uuid(parsed.c), created_at: timestamp(parsed.t), id: uuid(parsed.i) };
  // Canonical JSON also rejects alternate key order, whitespace, repeated fields and non-canonical UTF-8.
  if (encodeCursor(cursor.conversation_id, { id: cursor.id, created_at_exact: cursor.created_at }) !== value) invalid();
  if (cursor.conversation_id !== uuid(conversationId)) throw new AppError('The conversation has changed. Reload chat.', 409);
  return cursor;
}

function object(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || Object.keys(value).some((key) => !allowed.includes(key))) invalid();
}

function pageQuery(data) {
  object(data, ['conversation_id', 'before', 'after', 'limit']);
  const conversationId = uuid(data.conversation_id);
  if (data.before !== undefined && data.after !== undefined) invalid();
  let limit = 30;
  if (data.limit !== undefined) {
    if (typeof data.limit !== 'string' || !/^(?:[1-9]|[1-4][0-9]|50)$/.test(data.limit)) invalid();
    limit = Number(data.limit);
  }
  return { conversation_id: conversationId, limit,
    before: data.before === undefined ? null : decodeCursor(data.before, conversationId),
    after: data.after === undefined ? null : decodeCursor(data.after, conversationId) };
}

function sendBody(data) {
  object(data, ['content', 'client_request_id', 'conversation_id']);
  if (typeof data.content !== 'string') invalid();
  const content = data.content.trim();
  if (!content.length || content.length > 2000) invalid();
  return { content, client_request_id: uuid(data.client_request_id),
    conversation_id: data.conversation_id === undefined ? null : uuid(data.conversation_id) };
}

function readBody(data = {}) {
  object(data, ['conversation_id', 'through_cursor', 'from_cursor']);
  if (data.conversation_id === undefined) {
    if (data.through_cursor !== undefined || data.from_cursor !== undefined) invalid();
    return { conversation_id: null, through: null, from: null };
  }
  const conversationId = uuid(data.conversation_id);
  const through = data.through_cursor === undefined ? null : decodeCursor(data.through_cursor, conversationId);
  const from = data.from_cursor === undefined ? null : decodeCursor(data.from_cursor, conversationId);
  if (from && (!through || from.created_at > through.created_at
      || (from.created_at === through.created_at && from.id > through.id))) invalid();
  return { conversation_id: conversationId, through, from };
}

module.exports = { uuid, timestamp, encodeCursor, decodeCursor, pageQuery, sendBody, readBody };
