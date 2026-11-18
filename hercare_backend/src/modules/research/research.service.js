const crypto = require('crypto');
const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const POLICY_VERSION = 'research-aggregate-v1';

function validateConsent(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AppError('Consent must be an object.', 422);
  if (Object.keys(body).some((key) => !['enabled', 'policy_version', 'timezone'].includes(key))
      || typeof body.enabled !== 'boolean' || body.policy_version !== POLICY_VERSION
      || !['Asia/Karachi', 'UTC'].includes(body.timezone || 'Asia/Karachi')) {
    throw new AppError('Invalid research consent or policy version.', 422);
  }
  return { enabled: body.enabled, timezone: body.timezone || 'Asia/Karachi' };
}
async function status(motherId) {
  const { rows } = await query(`SELECT r.enabled,r.granted_at,r.timezone,o.age,o.months_since_birth
    FROM onboarding_data o LEFT JOIN research_consents r ON r.mother_id=o.user_id WHERE o.user_id=$1`, [motherId]);
  const row = rows[0];
  return { enabled: row?.enabled === true, eligible: !!row && row.age >= 18 && row.months_since_birth <= 12
      && process.env.RESEARCH_COLLECTION_ENABLED === 'true' && !!process.env.RESEARCH_STUDY_ID,
    timezone: row?.timezone || 'Asia/Karachi', granted_at: row?.granted_at || null, policy_version: POLICY_VERSION,
    collection: 'Future aggregate measurements only; no private journals, chat, audio or notification content.' };
}
async function setConsent(motherId, body) {
  const data = validateConsent(body);
  if (data.enabled && (process.env.RESEARCH_COLLECTION_ENABLED !== 'true' || !process.env.RESEARCH_STUDY_ID)) {
    throw new AppError('Research gathering is awaiting an approved study configuration.', 503);
  }
  await withTransaction(async (client) => {
    const { rows } = await client.query(`SELECT u.id,o.age,o.months_since_birth,o.consent_tier1
      FROM users u JOIN onboarding_data o ON o.user_id=u.id WHERE u.id=$1 AND u.is_active AND u.role='mother' FOR UPDATE OF u`, [motherId]);
    if (!rows[0] || (data.enabled && (rows[0].age < 18 || !rows[0].consent_tier1 || rows[0].months_since_birth > 12))) {
      throw new AppError('Research participation requires an active adult mother account and basic consent.', 403);
    }
    const previous = await client.query('SELECT enabled,study_id,policy_version,timezone FROM research_consents WHERE mother_id=$1 FOR UPDATE', [motherId]);
    const consent = previous.rows[0];
    if (data.enabled && consent?.enabled && consent.study_id !== process.env.RESEARCH_STUDY_ID) {
      throw new AppError('Withdraw the previous research consent before joining a different study.', 409);
    }
    if (data.enabled && consent?.enabled && consent.policy_version === POLICY_VERSION && consent.timezone === data.timezone) {
      return; // Repeated opt-in must not duplicate baseline snapshots or reset its timestamp.
    }
    await client.query(`INSERT INTO research_consents(mother_id,enabled,policy_version,timezone,granted_at,revoked_at,study_id)
      VALUES($1,$2,$3,$4,CASE WHEN $2 THEN NOW() ELSE NULL END,CASE WHEN $2 THEN NULL ELSE NOW() END,$5)
      ON CONFLICT(mother_id) DO UPDATE SET enabled=EXCLUDED.enabled,policy_version=EXCLUDED.policy_version,
        timezone=EXCLUDED.timezone,study_id=EXCLUDED.study_id,granted_at=CASE WHEN EXCLUDED.enabled AND NOT research_consents.enabled
          THEN NOW() ELSE research_consents.granted_at END,
        revoked_at=CASE WHEN EXCLUDED.enabled THEN NULL ELSE NOW() END,updated_at=NOW()`,
    [motherId, data.enabled, POLICY_VERSION, data.timezone, process.env.RESEARCH_STUDY_ID || null]);
    if (!data.enabled) await client.query('DELETE FROM research_observations WHERE mother_id=$1', [motherId]);
    // Capture profile/context at opt-in time, not backdated mood or future labels.
    if (data.enabled) {
      await client.query('UPDATE onboarding_data SET updated_at=updated_at WHERE user_id=$1', [motherId]);
      await client.query('UPDATE risk_context SET updated_at=updated_at WHERE mother_id=$1', [motherId]);
    }
  });
  return status(motherId);
}
function exportOptions(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AppError('Export options must be an object.', 422);
  if (Object.keys(body).some((key) => !['from', 'to', 'purpose', 'limit', 'after'].includes(key))) throw new AppError('Unknown export option.', 422);
  const from = new Date(`${body.from}T00:00:00Z`);
  const to = new Date(`${body.to}T00:00:00Z`);
  const validDate = (value, parsed) => /^\d{4}-\d{2}-\d{2}$/.test(value || '')
    && Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
  if (!validDate(body.from, from) || !validDate(body.to, to) || to < from
      || (to - from) / 86400000 > 90 || to > new Date()
      || !['fyp_model_development', 'external_validation'].includes(body.purpose)
      || !Number.isInteger(body.limit ?? 20) || (body.limit ?? 20) < 1 || (body.limit ?? 20) > 100
      || (body.after !== undefined && (!Number.isSafeInteger(body.after) || body.after < 0))) {
    throw new AppError('Export requires a past range of at most 90 days, a purpose and a bounded limit.', 422);
  }
  return { ...body, limit: body.limit ?? 20, after: body.after ?? 0 };
}
function pseudonym(secret, kind, id) {
  return crypto.createHmac('sha256', secret).update(`${kind}:${id}`).digest('hex');
}
async function exportData(actorId, body) {
  const options = exportOptions(body);
  const secret = process.env.RESEARCH_PSEUDONYM_KEY || '';
  if (process.env.RESEARCH_EXPORT_ENABLED !== 'true' || secret.length < 32) throw new AppError('Research export is not configured.', 503);
  return withTransaction(async (client) => {
    const admin = await client.query("SELECT id FROM users WHERE id=$1 AND role='admin' AND is_active=TRUE", [actorId]);
    if (!admin.rows.length) throw new AppError('Active administrator account required.', 403);
    // Numeric observation cursor contains no original participant UUID.
    const people = await client.query(`SELECT r.mother_id,r.timezone,r.granted_at,MIN(s.id)::text AS cursor_id
      FROM research_consents r JOIN research_observations s ON s.mother_id=r.mother_id
      JOIN users u ON u.id=r.mother_id JOIN onboarding_data o ON o.user_id=u.id
      WHERE r.enabled AND r.study_id=$5 AND u.is_active AND u.role='mother' AND o.consent_tier1
        AND s.available_at >= ($1::date::timestamp AT TIME ZONE 'UTC')
        AND s.available_at < (($2::date + INTERVAL '1 day') AT TIME ZONE 'UTC')
      GROUP BY r.mother_id,r.timezone,r.granted_at HAVING MIN(s.id)>$3 ORDER BY MIN(s.id) LIMIT $4`,
    [options.from, options.to, options.after, options.limit + 1, process.env.RESEARCH_STUDY_ID]);
    let selected = people.rows.slice(0, options.limit);
    let ids = selected.map((row) => row.mother_id);
    if (ids.length) {
      const locked = await client.query('SELECT mother_id FROM research_consents WHERE mother_id=ANY($1::uuid[]) AND enabled AND study_id=$2 FOR SHARE', [ids, process.env.RESEARCH_STUDY_ID]);
      const permitted = new Set(locked.rows.map((row) => row.mother_id));
      selected = selected.filter((row) => permitted.has(row.mother_id));
      ids = selected.map((row) => row.mother_id);
    }
    const observations = ids.length ? await client.query(`SELECT s.*,s.local_date::text AS local_date FROM research_observations s
      JOIN research_consents r ON r.mother_id=s.mother_id AND r.enabled
      WHERE s.mother_id=ANY($1::uuid[])
        AND s.available_at >= ($2::date::timestamp AT TIME ZONE 'UTC')
        AND s.available_at < (($3::date + INTERVAL '1 day') AT TIME ZONE 'UTC')
      ORDER BY s.available_at,s.id LIMIT 20001`, [ids, options.from, options.to]) : { rows: [] };
    if (observations.rows.length > 20000) throw new AppError('Export page too large; reduce date range or participant limit.', 422);
    const audit = await client.query(`INSERT INTO research_export_audit(actor_id,purpose,participant_count,observation_count)
      VALUES($1,$2,$3,$4) RETURNING id`, [actorId, options.purpose, ids.length, observations.rows.length]);
    return { schema_version: 2, data_kind: 'real_consented_source_events', export_id: audit.rows[0].id,
      policy_version: POLICY_VERSION, from: options.from, to: options.to,
      study_id: process.env.RESEARCH_STUDY_ID,
      next_cursor: people.rows.length > options.limit ? Number(people.rows[options.limit - 1].cursor_id) : null,
      participants: selected.map((row) => ({ participant_id: pseudonym(secret, 'participant', row.mother_id),
        research_consent: true, timezone: row.timezone, granted_at: row.granted_at })),
      events: observations.rows.map((row) => ({ participant_id: pseudonym(secret, 'participant', row.mother_id),
        source_record_id: pseudonym(secret, row.source_type, row.source_id), type: row.source_type,
        date: row.local_date ? new Date(row.local_date).toISOString().slice(0, 10) : null,
        performed_at: row.occurred_at, available_at: row.available_at, values: row.payload })),
      limitations: ['Prospective opt-in aggregate measurements, not diagnoses or proof of treatment effectiveness.',
        'No text/audio; original questionnaires and safety outcomes retain their own definitions.',
        'Withdrawal removes server research copies; already exported files and backups require controlled deletion procedures.'] };
  });
}
module.exports = { POLICY_VERSION, validateConsent, status, setConsent, exportOptions, exportData, pseudonym };
