const db = require('../../config/database');
const { randomUUID } = require('node:crypto');
const { AppError } = require('../../middleware/error_handler');
const { encryptTranscript, decryptTranscript, transcriptFingerprint, encryptJournal, buildBlindIndexes, decryptVoice } = require('./journal_crypto');
const { analyzeJournal } = require('./journal_analysis');
const { analyzeText } = require('./text_analysis.service');
const m4Text = require('../risk/m4.text');
const client = require('./transcription.client');
const voice = require('./voice.service');
const push = require('../notifications/notification.service');

async function authorize(connection, motherId) {
  const result = await connection.query(`SELECT u.id FROM users u JOIN onboarding_data od ON od.user_id=u.id
    WHERE u.id=$1 AND u.role='mother' AND u.is_active AND od.consent_tier1 FOR SHARE OF u,od`, [motherId]);
  if (!result.rows[0]) throw new AppError('Active mother account and basic monitoring consent required.', 403);
}
function view(row, motherId) {
  return { journal_id: row.journal_id, status: row.status, revision: row.revision,
    draft: row.status === 'review' && row.draft_encrypted ? decryptTranscript(row.draft_encrypted, motherId, row.journal_id) : null,
    safety_hint: row.status === 'review' && row.draft_safety_hint === true,
    model_version: row.model_version, failure_code: row.failure_code,
    review_required: row.status !== 'confirmed', updated_at: row.updated_at };
}
async function get(motherId, journalId) {
  return db.withTransaction(async (connection) => {
    await authorize(connection, motherId);
    const result = await connection.query(`SELECT t.* FROM journal_voice_transcriptions t JOIN journal_entries j ON j.id=t.journal_id
      WHERE j.id=$1 AND j.mother_id=$2 AND j.entry_type='voice'`, [journalId, motherId]);
    if (!result.rows[0]) throw new AppError('Transcript not found.', 404);
    return view(result.rows[0], motherId);
  });
}
async function request(motherId, journalId) {
  return db.withTransaction(async (connection) => {
    await connection.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [motherId]);
    await authorize(connection, motherId);
    const journal = await connection.query(`SELECT id FROM journal_entries WHERE id=$1 AND mother_id=$2
      AND entry_type='voice' AND (voice_audio_encrypted IS NOT NULL OR voice_object_key IS NOT NULL) FOR UPDATE`, [journalId, motherId]);
    if (!journal.rows[0]) throw new AppError('Voice note not found.', 404);
    const existing = await connection.query('SELECT * FROM journal_voice_transcriptions WHERE journal_id=$1 FOR UPDATE', [journalId]);
    if (existing.rows[0] && !['failed', 'no_speech'].includes(existing.rows[0].status)) return view(existing.rows[0], motherId);
    const pending = await connection.query(`SELECT COUNT(*)::int AS count FROM journal_voice_transcriptions t
      JOIN journal_entries j ON j.id=t.journal_id WHERE j.mother_id=$1 AND t.status IN ('queued','processing')`, [motherId]);
    if (pending.rows[0].count >= 3) throw new AppError('Finish an existing voice transcription before requesting another.', 429);
    const result = await connection.query(`INSERT INTO journal_voice_transcriptions(journal_id) VALUES($1)
      ON CONFLICT(journal_id) DO UPDATE SET status='queued',revision=journal_voice_transcriptions.revision+1,
        attempts=0,draft_encrypted=NULL,draft_safety_hint=FALSE,lease_token=NULL,lease_until=NULL,
        failure_code=NULL,requested_at=NOW(),next_attempt_at=NOW(),updated_at=NOW() RETURNING *`, [journalId]);
    return view(result.rows[0], motherId);
  });
}
async function cancel(motherId, journalId) {
  return db.withTransaction(async (connection) => {
    await authorize(connection, motherId);
    const result = await connection.query(`DELETE FROM journal_voice_transcriptions t USING journal_entries j
      WHERE j.id=t.journal_id AND j.id=$1 AND j.mother_id=$2 AND t.status<>'confirmed' RETURNING t.journal_id`, [journalId, motherId]);
    if (!result.rows[0]) throw new AppError('Draft is unavailable. A confirmed transcript is removed by deleting its journal.', 409);
    return { cancelled: true };
  });
}
function confirmation(body) {
  if (!body || Array.isArray(body) || Object.keys(body).some((key) => !['content', 'revision', 'client_request_id'].includes(key))
      || typeof body.content !== 'string' || !body.content.trim() || body.content.length > 5000
      || !Number.isInteger(body.revision) || body.revision < 1
      || typeof body.client_request_id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.client_request_id)) {
    throw new AppError('Review a transcript of 1–5000 characters before confirming.', 422);
  }
  return { ...body, content: body.content.trim() };
}
async function confirm(motherId, journalId, body) {
  const data = confirmation(body);
  // Verify ownership before inference as well as inside the final transaction.
  await db.withTransaction(async (connection) => {
    await authorize(connection, motherId);
    const found = await connection.query("SELECT id FROM journal_entries WHERE id=$1 AND mother_id=$2 AND entry_type='voice'", [journalId, motherId]);
    if (!found.rows[0]) throw new AppError('Voice note not found.', 404);
  });
  const analysis = await analyzeText(data.content);
  const fingerprint = transcriptFingerprint(data.content, motherId, journalId);
  let createdEvent = false;
  const result = await db.withTransaction(async (connection) => {
    await authorize(connection, motherId);
    const owned = await connection.query(`SELECT j.id FROM journal_entries j WHERE j.id=$1 AND j.mother_id=$2
      AND j.entry_type='voice' FOR UPDATE`, [journalId, motherId]);
    if (!owned.rows[0]) throw new AppError('Voice note not found.', 404);
    const found = await connection.query('SELECT * FROM journal_voice_transcriptions WHERE journal_id=$1 FOR UPDATE', [journalId]);
    const current = found.rows[0];
    if (!current) throw new AppError('Transcript not found.', 404);
    if (current.status === 'confirmed' && current.confirmed_request_id === data.client_request_id
        && current.confirmed_fingerprint === fingerprint) return { confirmed: true, contains_danger: analysis.containsDanger };
    if (current.status !== 'review' || current.revision !== data.revision) throw new AppError('Transcript changed. Reopen it before confirming.', 409);
    await connection.query(`UPDATE journal_entries SET content_encrypted=$3,search_terms=$4,language=$5,processing_status='complete',
      sentiment_label=$6,sentiment_score=$7,distress_score=$8,contains_danger=$9,analysis_version=$10,analysis_metadata=$11::jsonb,updated_at=NOW()
      WHERE id=$1 AND mother_id=$2`, [journalId, motherId, encryptJournal(data.content), buildBlindIndexes(data.content), analysis.language,
      analysis.sentimentLabel, analysis.sentimentScore, analysis.distressScore, analysis.containsDanger, analysis.analysisVersion,
      JSON.stringify({ ...analysis.metadata, input_source: 'mother_confirmed_voice_transcript', asr_model: current.model_version,
        transcript_reviewed: true, clinical_validation: false })]);
    await connection.query(`UPDATE journal_voice_transcriptions SET status='confirmed',revision=revision+1,draft_encrypted=NULL,
      draft_safety_hint=FALSE,confirmed_request_id=$2,confirmed_fingerprint=$3,confirmed_at=NOW(),updated_at=NOW() WHERE journal_id=$1`,
    [journalId, data.client_request_id, fingerprint]);
    await m4Text.capture(connection, motherId, 'journal', journalId, data.content, analysis.containsDanger);
    if (analysis.containsDanger) {
      const event = await connection.query(`INSERT INTO crisis_events(mother_id,source_type,source_id,severity)
        VALUES($1,'voice_journal',$2,'severe') ON CONFLICT(source_type,source_id) DO NOTHING RETURNING id`, [motherId, journalId]);
      if (event.rows[0]) {
        createdEvent = true;
        await connection.query(`INSERT INTO guardian_alerts(mother_id,guardian_id,crisis_event_id,alert_type,message)
          SELECT gl.mother_id,gl.guardian_id,$2,'crisis','URGENT: A serious safety indicator was detected. Please check on her and use the crisis plan.'
          FROM guardian_links gl JOIN onboarding_data od ON od.user_id=gl.mother_id
          WHERE gl.mother_id=$1 AND gl.status='active' AND od.consent_tier2`, [motherId, event.rows[0].id]);
      }
    }
    return { confirmed: true, contains_danger: analysis.containsDanger };
  });
  if (createdEvent) void push.processPendingSafely();
  return result;
}
async function processOne(signal) {
  const lease = randomUUID();
  const claimed = await db.withTransaction(async (connection) => {
    await connection.query(`UPDATE journal_voice_transcriptions t SET status='failed',failure_code='access_or_retry_expired',
      lease_token=NULL,lease_until=NULL,updated_at=NOW() FROM journal_entries j WHERE j.id=t.journal_id
      AND t.status IN ('queued','processing') AND ((t.status='processing' AND t.attempts>=3 AND t.lease_until<NOW())
        OR NOT EXISTS(SELECT 1 FROM users u JOIN onboarding_data od ON od.user_id=u.id
          WHERE u.id=j.mother_id AND u.is_active AND u.role='mother' AND od.consent_tier1))`);
    const result = await connection.query(`SELECT t.journal_id FROM journal_voice_transcriptions t
      JOIN journal_entries j ON j.id=t.journal_id JOIN users u ON u.id=j.mother_id AND u.role='mother' AND u.is_active
      JOIN onboarding_data od ON od.user_id=u.id AND od.consent_tier1
      WHERE ((t.status='queued' AND t.next_attempt_at<=NOW()) OR (t.status='processing' AND t.lease_until<NOW()))
        AND t.attempts<3 ORDER BY t.next_attempt_at,t.journal_id FOR UPDATE OF t SKIP LOCKED LIMIT 1`);
    if (!result.rows[0]) return null;
    const journalId = result.rows[0].journal_id;
    await connection.query(`UPDATE journal_voice_transcriptions SET status='processing',attempts=attempts+1,
      lease_token=$2,lease_until=NOW()+INTERVAL '3 minutes',updated_at=NOW() WHERE journal_id=$1`, [journalId, lease]);
    return journalId;
  });
  if (!claimed) return false;
  try {
    const owned = await db.withTransaction(async (connection) => {
      const rows = await connection.query(`SELECT j.* FROM journal_entries j JOIN journal_voice_transcriptions t ON t.journal_id=j.id
        WHERE j.id=$1 AND t.lease_token=$2 AND t.status='processing'`, [claimed, lease]);
      if (!rows.rows[0]) return null;
      await authorize(connection, rows.rows[0].mother_id);
      return rows.rows[0];
    });
    if (!owned) return true;
    const audio = owned.voice_audio_encrypted ? decryptVoice(owned.voice_audio_encrypted, owned.mother_id, claimed)
      : await voice.downloadVerifiedAudio(owned.voice_object_key, owned.voice_size_bytes);
    const response = await client.transcribe(audio, owned.voice_content_type, owned.language === 'en' ? 'en' : 'ur', signal);
    await db.withTransaction(async (connection) => {
      await authorize(connection, owned.mother_id);
      await connection.query(`UPDATE journal_voice_transcriptions SET status=$3,draft_encrypted=$4,draft_safety_hint=$5,
        model_version=$6,lease_token=NULL,lease_until=NULL,failure_code=NULL,updated_at=NOW()
        WHERE journal_id=$1 AND lease_token=$2 AND status='processing'`, [claimed, lease,
        response.status === 'draft' ? 'review' : 'no_speech', response.text ? encryptTranscript(response.text, owned.mother_id, claimed) : null,
        response.text ? analyzeJournal(response.text).containsDanger : false, response.model_version]);
    });
  } catch (error) {
    const terminal = [403, 422].includes(error.statusCode);
    await db.query(`UPDATE journal_voice_transcriptions SET status=CASE WHEN attempts>=3 OR $3 THEN 'failed' ELSE 'queued' END,
      next_attempt_at=NOW()+make_interval(secs=>30*attempts),lease_token=NULL,lease_until=NULL,
      failure_code=$4,updated_at=NOW() WHERE journal_id=$1 AND lease_token=$2 AND status='processing'`,
    [claimed, lease, terminal, error.statusCode === 422 ? 'unsupported_clip' : error.statusCode === 403 ? 'access_unavailable' : 'service_unavailable']);
  }
  return true;
}
module.exports = { authorize, request, get, confirm, cancel, processOne, confirmation };
