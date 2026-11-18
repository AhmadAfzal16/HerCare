const { createHash } = require('node:crypto');
const database = require('../../config/database');
const p = require('./content.policy');
const ranking = require('./content.ranking');

const publicFields = ['id', 'version', ...p.CONTENT_KEYS, 'published_at', 'updated_at', 'reviewed_at'];
const defaultPreferences = () => ({ religious_enabled: false, music_enabled: false, disabled_categories: [], version: 0 });
const fingerprint = (value) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
function preferencesResponse(row) {
  return row ? { religious_enabled: row.religious_enabled, music_enabled: row.music_enabled,
    disabled_categories: row.disabled_categories, version: row.version } : defaultPreferences();
}
function publicItem(row, reasons = ['general']) {
  const result = Object.fromEntries(publicFields.map((key) => [key, row[key] ?? null]));
  const label = ranking.REASONS[reasons[0]] || ranking.REASONS.general;
  return { ...result, saved: !!row.saved, feedback: row.feedback || null, reason_codes: reasons, reason_en: label[0], reason_ur: label[1] };
}
async function actor(userId, db = database, lock = false, admin = false) {
  const { rows } = await db.query(`SELECT id,role,is_active,onboarding_complete FROM users
    WHERE id=$1 ${lock === 'share' ? 'FOR SHARE' : lock ? 'FOR UPDATE' : ''}`, [p.uuid(userId)]);
  const user = rows[0];
  if (!user?.is_active || !['mother', 'guardian', 'admin'].includes(user.role) || (admin && user.role !== 'admin')) p.fail('Content access is unavailable.', 403);
  if (user.role === 'mother') {
    const consent = await db.query(`SELECT consent_tier1 FROM onboarding_data WHERE user_id=$1 ${lock ? 'FOR SHARE' : ''}`, [userId]);
    if (!user.onboarding_complete || consent.rows[0]?.consent_tier1 !== true) p.fail('Complete onboarding and basic consent to use personalized content.', 403);
  }
  if (user.role === 'guardian' && !user.onboarding_complete) p.fail('Complete your account setup first.', 403);
  return user;
}
async function spendQuota(userId) {
  const { rows } = await database.query(`INSERT INTO content_write_limits(user_id,writes) VALUES($1,1)
    ON CONFLICT(user_id) DO UPDATE SET
      writes=CASE WHEN content_write_limits.window_start<NOW()-INTERVAL '15 minutes' THEN 1 ELSE content_write_limits.writes+1 END,
      window_start=CASE WHEN content_write_limits.window_start<NOW()-INTERVAL '15 minutes' THEN NOW() ELSE content_write_limits.window_start END
    WHERE content_write_limits.writes<100 OR content_write_limits.window_start<NOW()-INTERVAL '15 minutes' RETURNING writes`, [userId]);
  if (!rows.length) p.fail('Please wait before making more content updates.', 429);
}
async function readPreferences(db, userId) {
  const { rows } = await db.query('SELECT * FROM content_preferences WHERE user_id=$1', [userId]);
  return preferencesResponse(rows[0]);
}
async function contextFor(db, user) {
  if (user.role === 'guardian') {
    const crisis = await db.query(`SELECT EXISTS(SELECT 1 FROM guardian_alerts ga
      JOIN crisis_events ce ON ce.id=ga.crisis_event_id AND ce.status<>'resolved'
      JOIN guardian_links gl ON gl.id=ga.crisis_guardian_link_id AND gl.status='active' AND gl.guardian_id=$1
        AND gl.mother_id=ga.mother_id AND gl.mother_id=ce.mother_id
      JOIN users mother ON mother.id=gl.mother_id AND mother.is_active AND mother.role='mother'
      JOIN onboarding_data od ON od.user_id=gl.mother_id AND od.consent_tier1 AND od.consent_tier2
      JOIN crisis_safety_plans sp ON sp.mother_id=gl.mother_id AND sp.safe_guardian_link_id=gl.id AND sp.guardian_contact_confirmed
      WHERE ga.guardian_id=$1) AS needs_help`, [user.id]);
    return { safetyPriority: crisis.rows[0]?.needs_help === true, availableSignals: [], practice: [] };
  }
  const queries = [
    `SELECT mood_rating,sleep_quality FROM mood_checkins WHERE mother_id=$1
      AND entry_date BETWEEN CURRENT_DATE-2 AND CURRENT_DATE ORDER BY entry_date DESC LIMIT 1`,
    `SELECT quality,EXTRACT(EPOCH FROM(wake_time-bedtime))/60-awake_minutes AS sleep_minutes
      FROM sleep_records WHERE mother_id=$1 AND sleep_date BETWEEN CURRENT_DATE-2 AND CURRENT_DATE ORDER BY sleep_date DESC LIMIT 1`,
    `SELECT t.screen_time_minutes,t.late_night_minutes FROM device_telemetry_daily t JOIN onboarding_data od
      ON od.user_id=t.mother_id AND od.consent_tier3 WHERE t.mother_id=$1 AND t.usage_access
      AND t.local_date BETWEEN CURRENT_DATE-2 AND CURRENT_DATE ORDER BY t.local_date DESC LIMIT 1`,
    `SELECT activity_type,activity_id,COUNT(*) AS pairs,AVG(mood_after-mood_before) AS improvement
      FROM therapeutic_sessions WHERE mother_id=$1 AND completed AND mood_before IS NOT NULL AND mood_after IS NOT NULL
      AND completed_at BETWEEN NOW()-INTERVAL '30 days' AND NOW() GROUP BY activity_type,activity_id HAVING COUNT(*)>=3`,
    `SELECT risk_level FROM screening_assessments WHERE mother_id=$1 AND status='completed'
      AND completed_at BETWEEN NOW()-INTERVAL '14 days' AND NOW() ORDER BY completed_at DESC LIMIT 1`,
    `SELECT EXISTS(SELECT 1 FROM crisis_events WHERE mother_id=$1 AND status<>'resolved') AS needs_help`,
  ];
  // A transaction owns one PostgreSQL connection; do not issue overlapping client queries.
  const results = [];
  for (const sql of queries) results.push(await db.query(sql, [user.id]));
  const [mood, sleep, telemetry, practice, screening, crisis] = results.map((result) => result.rows);
  return { mood: mood[0]?.mood_rating ?? null, sleepQuality: sleep[0]?.quality ?? mood[0]?.sleep_quality ?? null,
    sleepMinutes: sleep[0]?.sleep_minutes == null ? null : Number(sleep[0].sleep_minutes),
    screenMinutes: telemetry[0]?.screen_time_minutes ?? null, lateNightMinutes: telemetry[0]?.late_night_minutes ?? null,
    practice, screeningRisk: screening[0]?.risk_level ?? null, safetyPriority: crisis[0]?.needs_help === true,
    availableSignals: [mood.length && 'mood', sleep.length && 'sleep', telemetry.length && 'telemetry', practice.length && 'practice', screening.length && 'screening'].filter(Boolean) };
}
const rankingFields = ['id', 'status', 'audience', 'category', 'is_religious', 'is_music', 'available_from', 'available_until',
  'review_after', 'media_url', 'source_url', 'priority', 'tags', 'activity_type', 'activity_id', 'published_at'];
const candidatesSql = (full = false) => `SELECT ${full ? 'c.*' : rankingFields.map((key) => `c.${key}`).join(',')},
  f.value AS feedback, (s.content_id IS NOT NULL) AS saved FROM content_items c
  LEFT JOIN content_feedback f ON f.content_id=c.id AND f.user_id=$1
  LEFT JOIN content_saves s ON s.content_id=c.id AND s.user_id=$1
  WHERE c.status='published' AND c.audience IN ($2,'both')
    AND (c.available_from IS NULL OR c.available_from<=NOW()) AND (c.available_until IS NULL OR c.available_until>NOW())
    AND (c.review_after IS NULL OR c.review_after>NOW())`;
async function feed(userId, query = {}, savedOnly = false) {
  const options = p.listQuery(query, false, savedOnly ? 100 : 30);
  return database.withTransaction(async (db) => {
    const user = await actor(userId, db, 'share');
    if (user.role === 'admin') p.fail('Use the content management workspace.', 403);
    // A shared catalog-state lock keeps item withdrawal/revision and the returned snapshot consistent.
    const state = (await db.query('SELECT revision,policy_version,weights FROM content_catalog_state WHERE singleton=TRUE FOR SHARE')).rows[0];
    if (!state) p.fail('The content catalog is not configured.', 503);
    ranking.validateWeights(state.weights);
    const preferences = await readPreferences(db, userId);
    const context = await contextFor(db, user);
    const base = { preferences, catalog_revision: String(state.revision), policy_version: state.policy_version,
      generated_at: new Date().toISOString(), refresh_after_seconds: 30, safety_priority: context.safetyPriority,
      allowed_media_hosts: p.allowedHosts(), context: { available_signals: context.availableSignals, recommendation_type: 'transparent_rules_not_clinical_prediction' } };
    if (context.safetyPriority) return { ...base, items: [], daily_verse: null, empty_reason: 'safety_support_required' };
    const { rows } = await db.query(`${candidatesSql()} ${savedOnly ? 'AND s.content_id IS NOT NULL' : ''}
      ORDER BY c.priority DESC,c.published_at DESC,c.id LIMIT 1000`, [userId, user.role]);
    const day = base.generated_at.slice(0, 10);
    const params = { userId, role: user.role, day, preferences, context, weights: state.weights, limit: options.limit, savedOnly };
    const ranked = ranking.rank(rows, params);
    const verses = savedOnly ? [] : rows.filter((row) => row.category === 'quran' && ranking.eligible(row, preferences, user.role) && row.feedback !== 'dismissed');
    const verse = ranking.dailyVerse(verses, userId, day);
    const ids = [...new Set([...ranked.map(({ row }) => row.id), ...(verse ? [verse.id] : [])])];
    // Do not load every article/Arabic passage just to rank it. Hydrate bounded selected cards only.
    const selected = ids.length ? (await db.query(`${candidatesSql(true)} AND c.id=ANY($3::uuid[])`, [userId, user.role, ids])).rows : [];
    const hydrated = new Map(selected.map((row) => [row.id, row]));
    return { ...base, items: ranked.filter(({ row }) => hydrated.has(row.id)).map(({ row, reasons }) => publicItem(hydrated.get(row.id), reasons)),
      daily_verse: verse && hydrated.has(verse.id) ? publicItem(hydrated.get(verse.id)) : null, empty_reason: ranked.length ? null : 'no_matching_reviewed_content' };
  });
}
async function detail(userId, id) {
  p.uuid(id);
  return database.withTransaction(async (db) => {
    const user = await actor(userId, db, 'share');
    if (user.role === 'admin') p.fail('Use the content management workspace.', 403);
    const preferences = await readPreferences(db, userId);
    const context = await contextFor(db, user);
    if (context.safetyPriority) p.fail('Open immediate safety support before ordinary content.', 409);
    const { rows } = await db.query(`${candidatesSql(true)} AND c.id=$3`, [userId, user.role, id]);
    if (!rows[0] || !ranking.eligible(rows[0], preferences, user.role)) p.fail('This content is no longer available.', 404);
    return publicItem(rows[0]);
  });
}
async function getPreferences(userId) {
  return database.withTransaction(async (db) => {
    const user = await actor(userId, db, 'share');
    if (user.role === 'admin') p.fail('Content preferences are for mother and guardian accounts.', 403);
    return readPreferences(db, userId);
  });
}
async function updatePreferences(userId, body) {
  const value = p.preferences(body);
  return database.withTransaction(async (db) => {
    const user = await actor(userId, db, true);
    if (user.role === 'admin') p.fail('Content preferences are for mother and guardian accounts.', 403);
    const current = await readPreferences(db, userId);
    if (current.version !== value.version) p.fail('Your preferences changed. Refresh and try again.', 409);
    const { rows } = await db.query(`INSERT INTO content_preferences(user_id,religious_enabled,music_enabled,disabled_categories)
      VALUES($1,$2,$3,$4) ON CONFLICT(user_id) DO UPDATE SET religious_enabled=EXCLUDED.religious_enabled,
      music_enabled=EXCLUDED.music_enabled,disabled_categories=EXCLUDED.disabled_categories,
      version=content_preferences.version+1,updated_at=NOW() RETURNING *`, [userId, value.religious_enabled, value.music_enabled, value.disabled_categories]);
    return preferencesResponse(rows[0]);
  });
}
async function mutation(db, userId, requestId, operation, work) {
  const hash = fingerprint(operation);
  const prior = (await db.query('SELECT fingerprint,response FROM content_mutations WHERE user_id=$1 AND client_request_id=$2', [userId, requestId])).rows[0];
  if (prior) { if (prior.fingerprint !== hash) p.fail('This request ID was already used for a different update.', 409); return prior.response; }
  const result = await work();
  await db.query('INSERT INTO content_mutations(user_id,client_request_id,fingerprint,response) VALUES($1,$2,$3,$4)', [userId, requestId, hash, JSON.stringify(result)]);
  return result;
}
async function interaction(userId, contentId, body, kind) {
  contentId = p.uuid(contentId); p.onlyKeys(body, ['client_request_id', kind === 'feedback' ? 'value' : 'saved']);
  const requestId = p.uuid(body.client_request_id);
  const value = kind === 'feedback' ? p.enumValue(body.value, ['helpful', 'not_helpful', 'dismissed']) : p.bool(body.saved);
  return database.withTransaction(async (db) => {
    const user = await actor(userId, db, true);
    if (user.role === 'admin') p.fail('Content feedback is for mother and guardian accounts.', 403);
    return mutation(db, userId, requestId, { kind, contentId, value }, async () => {
      // Removing a private saved item stays possible after withdrawal or opting out.
      if (!(kind === 'saved' && value === false)) {
        const preferences = await readPreferences(db, userId); const context = await contextFor(db, user);
        if (context.safetyPriority) p.fail('Open immediate safety support before ordinary content.', 409);
        const row = (await db.query('SELECT * FROM content_items WHERE id=$1 FOR SHARE', [contentId])).rows[0];
        if (!row || !ranking.eligible(row, preferences, user.role)) p.fail('This content is no longer available.', 404);
      }
      if (kind === 'feedback') {
        await db.query(`INSERT INTO content_feedback(user_id,content_id,value) VALUES($1,$2,$3)
          ON CONFLICT(user_id,content_id) DO UPDATE SET value=EXCLUDED.value,updated_at=NOW()`, [userId, contentId, value]);
        return { content_id: contentId, value };
      }
      if (value) {
        const count = await db.query(`SELECT COUNT(*)::int AS count,COALESCE(BOOL_OR(content_id=$2),FALSE) AS already_saved
          FROM content_saves WHERE user_id=$1`, [userId, contentId]);
        if (count.rows[0].count >= 100 && !count.rows[0].already_saved) p.fail('Remove a saved item before saving more than 100 items.', 422);
        await db.query('INSERT INTO content_saves(user_id,content_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [userId, contentId]);
      } else await db.query('DELETE FROM content_saves WHERE user_id=$1 AND content_id=$2', [userId, contentId]);
      return { content_id: contentId, saved: value };
    });
  });
}
async function adminList(userId, query = {}) {
  const options = p.listQuery(query, true);
  await actor(userId, database, false, true);
  const { rows } = await database.query(`SELECT * FROM content_items WHERE ($1::text IS NULL OR status=$1)
    ORDER BY updated_at DESC,id DESC LIMIT $2 OFFSET $3`, [options.status, options.limit, options.offset]);
  return { items: rows, next_offset: rows.length === options.limit ? options.offset + options.limit : null };
}
async function history(db, userId, row, action, note = null) {
  await db.query('INSERT INTO content_review_history(content_id,content_version,actor_id,action,note) VALUES($1,$2,$3,$4,$5)', [row.id, row.version, userId, action, note]);
  return row;
}
async function createItem(userId, body) {
  const value = p.item(body); const requestId = p.uuid(body.client_request_id);
  if (body.version !== undefined) p.fail();
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true);
    return mutation(db, userId, requestId, { create: value }, async () => {
      const names = Object.keys(value); const values = Object.values(value);
      const { rows } = await db.query(`INSERT INTO content_items(${names.join(',')},created_by)
        VALUES(${values.map((_, i) => `$${i + 1}`).join(',')},$${values.length + 1}) RETURNING *`, [...values, userId]);
      const row = await history(db, userId, rows[0], 'created');
      // Keep retry receipts bounded and independent of sensitive/operator text.
      return { id: row.id, version: row.version, status: row.status };
    });
  });
}
async function updateItem(userId, id, body) {
  p.uuid(id); const value = p.item(body); const version = p.integer(body.version, 1, 2147483646);
  if (body.client_request_id !== undefined) p.fail();
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true);
    const names = Object.keys(value); const values = Object.values(value);
    const { rows } = await db.query(`UPDATE content_items SET ${names.map((name, index) => `${name}=$${index + 1}`).join(',')},
      version=version+1,status='draft',reviewed_by=NULL,reviewed_at=NULL,review_note=NULL,reviewer_qualification=NULL,
      published_at=NULL,updated_at=NOW() WHERE id=$${values.length + 1} AND version=$${values.length + 2} RETURNING *`, [...values, id, version]);
    if (!rows.length) p.fail('This content changed. Refresh before editing.', 409);
    return history(db, userId, rows[0], 'updated');
  });
}
async function lockedItem(db, id, version) {
  const row = (await db.query('SELECT * FROM content_items WHERE id=$1 FOR UPDATE', [p.uuid(id)])).rows[0];
  if (!row) p.fail('Content not found.', 404);
  if (row.version !== p.integer(version, 1, 2147483646)) p.fail('This content changed. Refresh and try again.', 409);
  return row;
}
function assertReviewWindow(row, status = 422) {
  if ((row.source_url || row.media_url) && !row.review_after) p.fail('Externally sourced content needs a future review expiry before approval or publication.', status);
  if (row.review_after && new Date(row.review_after).getTime() <= Date.now()) p.fail('The content review has expired. Set a future review expiry and review again.', status);
}
async function reviewItem(userId, id, body) {
  p.onlyKeys(body, ['version', 'decision', 'review_note', 'reviewer_qualification']);
  const decision = p.enumValue(body.decision, ['approved', 'changes_requested']);
  const note = p.text(body.review_note, 1500, true); const qualification = p.text(body.reviewer_qualification, 300, true);
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true); const current = await lockedItem(db, id, body.version);
    if (current.status === 'archived' || current.status === 'published') p.fail('Withdraw or restore the item to draft before reviewing.', 409);
    p.item(Object.fromEntries(p.CONTENT_KEYS.map((key) => [key, current[key]])));
    if (decision === 'approved') assertReviewWindow(current);
    const { rows } = await db.query(`UPDATE content_items SET status=$2,version=version+1,reviewed_by=$3,reviewed_at=NOW(),review_note=$4,
      reviewer_qualification=$5,updated_at=NOW() WHERE id=$1 RETURNING *`, [id, decision === 'approved' ? 'reviewed' : 'draft', userId, note, qualification]);
    return history(db, userId, rows[0], decision, note);
  });
}
async function publication(userId, id, body) {
  p.onlyKeys(body, ['version', 'published']); const publish = p.bool(body.published);
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true); const current = await lockedItem(db, id, body.version);
    if (publish) {
      if (current.status !== 'reviewed') p.fail('Human review is required before publishing.', 409);
      p.item(Object.fromEntries(p.CONTENT_KEYS.map((key) => [key, current[key]])));
      assertReviewWindow(current, 409);
      await db.query("SELECT pg_advisory_xact_lock(hashtext('hercare-m11-publication'))");
      const count = await db.query("SELECT COUNT(*)::int AS count FROM content_items WHERE status='published'");
      if (count.rows[0].count >= 1000) p.fail('Withdraw an old item before publishing more than 1000 live items.', 422);
    }
    const { rows } = await db.query(`UPDATE content_items SET status=$2,version=version+1,
      published_at=CASE WHEN $3 THEN NOW() ELSE NULL END,updated_at=NOW() WHERE id=$1 RETURNING *`, [id, publish ? 'published' : 'draft', publish]);
    return history(db, userId, rows[0], publish ? 'published' : 'withdrawn');
  });
}
async function archive(userId, id, version) {
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true); await lockedItem(db, id, Number(version));
    const { rows } = await db.query("UPDATE content_items SET status='archived',version=version+1,published_at=NULL,updated_at=NOW() WHERE id=$1 RETURNING *", [id]);
    return history(db, userId, rows[0], 'archived');
  });
}
async function adminPolicy(userId, body = null) {
  return database.withTransaction(async (db) => {
    await actor(userId, db, true, true);
    if (body) {
      p.onlyKeys(body, ['version', 'weights']); ranking.validateWeights(body.weights); p.integer(body.version, 1, 2147483646);
      const result = await db.query(`UPDATE content_catalog_state SET weights=$1,policy_version=policy_version+1,revision=revision+1,updated_at=NOW()
        WHERE singleton AND policy_version=$2 RETURNING revision,policy_version AS version,weights`, [JSON.stringify(body.weights), body.version]);
      if (!result.rows.length) p.fail('The ranking policy changed. Refresh and try again.', 409);
      return result.rows[0];
    }
    const result = await db.query('SELECT revision,policy_version AS version,weights FROM content_catalog_state WHERE singleton');
    return { ...result.rows[0], allowed_media_hosts: p.allowedHosts() };
  });
}

module.exports = { actor, spendQuota, feed, detail, getPreferences, updatePreferences, interaction, adminList, createItem, updateItem, reviewItem,
  publication, archive, adminPolicy, _private: { publicItem, preferencesResponse, contextFor, mutation, lockedItem, assertReviewWindow } };
