const { AppError } = require('../../middleware/error_handler');
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OUTCOMES = ['support_contacted', 'professional_help_contacted', 'accidental_activation', 'other'];
function fail(message) { throw new AppError(message, 422); }
function object(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some((key) => !allowed.includes(key))) fail('Unsupported crisis request fields.');
}
function id(value) { if (typeof value !== 'string' || !UUID.test(value)) fail('A valid identifier is required.'); return value.toLowerCase(); }
function version(value) { if (!Number.isInteger(value) || value < 0 || value > 2147483646) fail('A valid safety-plan version is required.'); return value; }
function text(value, max) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || value.length > max || [...value].some((char) => {
    const code = char.codePointAt(0);
    return (code < 32 && ![9, 10, 13].includes(code)) || code === 127;
  })) fail('Safety-plan text is invalid or too long.');
  return value.trim();
}
function plan(body) {
  object(body, ['version', 'coping_step', 'support_person_name', 'support_phone']);
  const phone = text(body.support_phone, 40).replace(/[\s().-]/g, '');
  if (phone && !/^\+?\d{6,15}$/.test(phone)) fail('Use a valid phone number with an optional country code.');
  return { version: version(body.version), coping_step: text(body.coping_step, 500), support_person_name: text(body.support_person_name, 80), support_phone: phone };
}
function guardian(body) {
  object(body, ['guardian_link_id', 'confirmed']);
  if (typeof body.confirmed !== 'boolean') fail('Please explicitly confirm or disable guardian contact.');
  return { guardian_link_id: id(body.guardian_link_id), confirmed: body.confirmed };
}
function request(body) {
  object(body, ['client_request_id', 'notify_guardian', 'guardian_link_id']);
  if (typeof body.notify_guardian !== 'boolean') fail('Choose whether to notify your guardian.');
  const link = body.guardian_link_id == null ? null : id(body.guardian_link_id);
  if (body.notify_guardian && !link) fail('Select the current guardian before sending an alert.');
  if (!body.notify_guardian && link) fail('Guardian details are unnecessary for a private request.');
  return { client_request_id: id(body.client_request_id), notify_guardian: body.notify_guardian, guardian_link_id: link };
}
function transition(body) {
  object(body, ['status', 'outcome']);
  if (!['acknowledged', 'resolved'].includes(body.status)) fail('Choose acknowledgement or closure.');
  if (body.status === 'resolved' && !OUTCOMES.includes(body.outcome)) fail('Choose how the support request was closed.');
  if (body.status === 'acknowledged' && body.outcome != null) fail('An acknowledgement cannot mark the request resolved.');
  return { status: body.status, outcome: body.outcome || null };
}
function cursor(row) { return Buffer.from(JSON.stringify({ at: row.cursor_at || new Date(row.triggered_at).toISOString(), id: row.id })).toString('base64url'); }
function page(query = {}) {
  object(query, ['limit', 'before']);
  const limit = query.limit === undefined ? 20 : Number(query.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) fail('History limit must be between 1 and 50.');
  let before = null;
  if (query.before !== undefined) {
    if (typeof query.before !== 'string' || query.before.length > 200 || !/^[A-Za-z0-9_-]+$/.test(query.before)) fail('Invalid history cursor.');
    try {
      before = JSON.parse(Buffer.from(query.before, 'base64url').toString('utf8'));
      object(before, ['at', 'id']);
      before.id = id(before.id);
      if (typeof before.at !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3,6}Z$/.test(before.at) || !Number.isFinite(Date.parse(before.at))) fail('Invalid history cursor.');
    } catch { fail('Invalid history cursor.'); }
  }
  return { limit, before };
}
module.exports = { id, version, plan, guardian, request, transition, page, cursor, OUTCOMES };
