const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const { item, weights } = require('./helpers/content.fixture');

const userId = randomUUID();
function fakeDb({ role = 'mother', crisis = false, candidates = [], consent = true, overrides } = {}) {
  const sql = [];
  return { sql, query: async (text, args) => {
    sql.push(text);
    if (overrides) { const result = await overrides(text, args); if (result) return result; }
    if (/SELECT id,role/.test(text)) return { rows: [{ id: userId, role, is_active: true, onboarding_complete: true }] };
    if (/SELECT consent_tier1/.test(text)) return { rows: [{ consent_tier1: consent }] };
    if (/SELECT revision,policy_version,weights/.test(text)) return { rows: [{ revision: '12', policy_version: 1, weights }] };
    if (/SELECT \* FROM content_preferences/.test(text)) return { rows: [] };
    if (/AS needs_help/.test(text)) return { rows: [{ needs_help: crisis }] };
    if (/LEFT JOIN content_feedback/.test(text)) return { rows: candidates };
    return { rows: [] };
  } };
}
async function withDb(db, work) {
  const original = database.withTransaction;
  database.withTransaction = async (fn) => fn(db);
  try { return await work(); } finally { database.withTransaction = original; }
}
test('M11 feed uses fresh privacy-minimized aggregates; no raw text, synthetic clinical scores or stale telemetry', async () => {
  const db = fakeDb({ candidates: [item()] });
  const value = await withDb(db, () => service.feed(userId, { limit: '5' }));
  assert.equal(value.items.length, 1);
  assert.equal(value.catalog_revision, '12');
  assert.equal(value.context.recommendation_type, 'transparent_rules_not_clinical_prediction');
  assert.equal(value.context.available_signals.length, 0);
  assert.ok(db.sql.some((sql) => /consent_tier3/.test(sql) && /usage_access/.test(sql) && /CURRENT_DATE-2/.test(sql)));
  assert.ok(db.sql.some((sql) => /HAVING COUNT\(\*\)>=3/.test(sql)));
  assert.ok(db.sql.every((sql) => !/journal_entries|chat_messages|content_encrypted|depression_probability|notification_text/.test(sql)));
  assert.equal(JSON.stringify(value).includes('sleepMinutes'), false);
  assert.equal(JSON.stringify(value).includes('review_note'), false);
  const catalogQueries = db.sql.filter((sql) => /LEFT JOIN content_feedback/.test(sql));
  assert.equal(catalogQueries.length, 2);
  assert.ok(!catalogQueries[0].includes('c.*'), 'ranking never loads all article bodies');
  assert.match(catalogQueries[1], /c.id=ANY\(\$3::uuid\[\]\)/);
});
test('M11 unresolved crisis never queries or returns catalog content including saved content', async () => {
  const db = fakeDb({ crisis: true, candidates: [item({ saved: true })] });
  const value = await withDb(db, () => service.feed(userId, {}, true));
  assert.equal(value.safety_priority, true);
  assert.equal(value.empty_reason, 'safety_support_required');
  assert.deepEqual(value.items, []);
  assert.equal(value.daily_verse, null);
  assert.ok(db.sql.every((sql) => !/LEFT JOIN content_feedback/.test(sql)));
});
test('M11 guardian uses independent preferences and never queries mother clinical context', async () => {
  const db = fakeDb({ role: 'guardian', candidates: [item({ audience: 'guardian' }), item({ audience: 'mother' })] });
  const value = await withDb(db, () => service.feed(userId));
  assert.equal(value.items.length, 1);
  assert.deepEqual(value.context.available_signals, []);
  assert.ok(db.sql.every((sql) => !/mood_checkins|sleep_records|device_telemetry_daily|screening_assessments|therapeutic_sessions/.test(sql)));
  const safety = db.sql.find((sql) => /guardian_alerts/.test(sql));
  assert.match(safety, /guardian_contact_confirmed/);
  assert.match(safety, /consent_tier2/);
  assert.match(safety, /mother.is_active/);
});
test('M11 consent revocation and account deactivation fail closed before context/catalog reads', async () => {
  const db = fakeDb({ consent: false });
  await assert.rejects(withDb(db, () => service.feed(userId)), { statusCode: 403 });
  assert.ok(db.sql.every((sql) => !/mood_checkins|content_items/.test(sql)));
  const inactive = fakeDb({ overrides: (sql) => /SELECT id,role/.test(sql) ? { rows: [] } : null });
  await assert.rejects(withDb(inactive, () => service.feed(userId)), { statusCode: 403 });
});
test('M11 optimistic preferences do not overwrite a newer account choice', async () => {
  const db = fakeDb({ overrides: (sql) => /SELECT \* FROM content_preferences/.test(sql)
    ? { rows: [{ religious_enabled: true, music_enabled: false, disabled_categories: [], version: 3 }] } : null });
  await assert.rejects(withDb(db, () => service.updatePreferences(userId, { version: 2, religious_enabled: false, music_enabled: false, disabled_categories: [] })), { statusCode: 409 });
  assert.ok(db.sql.every((sql) => !/INSERT INTO content_preferences/.test(sql)));
});
test('M11 idempotent retry uses the stored receipt and rejects reuse for a different action', async () => {
  const requestId = randomUUID(); const contentId = randomUUID(); const receipts = new Map(); let changes = 0;
  const db = { query: async (sql, args) => {
    if (sql.startsWith('SELECT fingerprint')) return { rows: receipts.has(args[1]) ? [receipts.get(args[1])] : [] };
    if (sql.startsWith('INSERT INTO content_mutations')) receipts.set(args[1], { fingerprint: args[2], response: JSON.parse(args[3]) });
    return { rows: [] };
  } };
  const operation = { kind: 'saved', contentId, value: true };
  const work = async () => { changes++; return { content_id: contentId, saved: true }; };
  const first = await service._private.mutation(db, userId, requestId, operation, work);
  const second = await service._private.mutation(db, userId, requestId, operation, work);
  assert.deepEqual(first, second); assert.equal(changes, 1);
  await assert.rejects(service._private.mutation(db, userId, requestId, { ...operation, value: false }, work), { statusCode: 409 });
});
test('M11 public projection never exposes operator IDs, health data or review notes', () => {
  const value = service._private.publicItem({ ...item(), created_by: randomUUID(), reviewed_by: randomUUID(), review_note: 'private admin note', input_summary: { score: 9 } });
  for (const field of ['created_by', 'reviewed_by', 'review_note', 'input_summary', 'status']) assert.equal(value[field], undefined);
  assert.equal(value.reason_codes[0], 'general');
});
test('M11 external sources require a future review expiry before approval and publication', () => {
  const check = service._private.assertReviewWindow;
  assert.doesNotThrow(() => check({ format: 'activity' }));
  for (const row of [{ source_url: 'https://example.org/article' }, { media_url: 'https://example.org/video' },
    { source_url: 'https://example.org/article', review_after: new Date(Date.now() - 1000) }]) {
    assert.throws(() => check(row), { statusCode: 422 });
    assert.throws(() => check(row, 409), { statusCode: 409 });
  }
  assert.doesNotThrow(() => check({ source_url: 'https://example.org/article', review_after: new Date(Date.now() + 86400000) }));
});
