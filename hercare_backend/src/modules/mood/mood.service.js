const { randomUUID: uuidv4 } = require('node:crypto');
const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const {
  encryptJournal,
  decryptJournal,
  encryptVoice,
  decryptVoice,
  buildBlindIndexes,
} = require('./journal_crypto');
const { analyzeText } = require('./text_analysis.service');
const m4Text = require('../risk/m4.text');
const voiceService = require('./voice.service');
const pushNotifications = require('../notifications/notification.service');

function compositeScore(data) {
  const values = [
    [data.mood_rating, 0.4],
    [data.energy_level, 0.2],
    [data.sleep_quality, 0.2],
    [data.social_support, 0.2],
  ].filter(([value]) => value !== null && value !== undefined);
  const weight = values.reduce((sum, [, contribution]) => sum + contribution, 0);
  return Number((values.reduce((sum, [value, contribution]) => (
    sum + Number(value) * contribution
  ), 0) / weight).toFixed(2));
}

function publicCheckin(row) {
  if (!row) return null;
  return {
    ...row,
    mood_rating: Number(row.mood_rating),
    energy_level: row.energy_level == null ? null : Number(row.energy_level),
    sleep_quality: row.sleep_quality == null ? null : Number(row.sleep_quality),
    social_support: row.social_support == null ? null : Number(row.social_support),
    composite_score: Number(row.composite_score),
  };
}

function utcDate(value) {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime())) throw new AppError('Invalid entry date.', 422);
  return parsed;
}

function formatDate(value) {
  return value.toISOString().slice(0, 10);
}

function periodBounds(type, anchorDate) {
  const start = utcDate(anchorDate);
  const end = new Date(start);
  if (type === 'weekly') {
    const offset = start.getUTCDay() === 0 ? 6 : start.getUTCDay() - 1;
    start.setUTCDate(start.getUTCDate() - offset);
    end.setTime(start.getTime());
    end.setUTCDate(end.getUTCDate() + 6);
  } else if (type === 'monthly') {
    start.setUTCDate(1);
    end.setUTCFullYear(start.getUTCFullYear(), start.getUTCMonth() + 1, 0);
  } else if (type !== 'daily') {
    throw new AppError('Unsupported summary period.', 422);
  }
  return { start: formatDate(start), end: formatDate(end) };
}

async function refreshReport(motherId, periodType, anchorDate) {
  const bounds = periodBounds(periodType, anchorDate);
  const { rows } = await query(
    `SELECT entry_date, mood_rating
     FROM mood_checkins
     WHERE mother_id = $1 AND entry_date BETWEEN $2 AND $3
     ORDER BY entry_date`,
    [motherId, bounds.start, bounds.end],
  );
  const values = rows.map((row) => Number(row.mood_rating));
  const average = values.length === 0
    ? null
    : Number((values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(1));
  const reportData = {
    status: values.length === 0 ? 'insufficient_data' : 'available',
    mood_trend: values,
    mood_scale: { minimum: 1, maximum: 5 },
    generated_by: 'mood_module',
    generated_at: new Date().toISOString(),
  };
  await query(
    `INSERT INTO health_reports
       (mother_id, period_type, period_start, period_end, avg_mood, mood_entries, report_data)
     VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
     ON CONFLICT (mother_id, period_type, period_start, period_end)
     DO UPDATE SET avg_mood = EXCLUDED.avg_mood,
                   mood_entries = EXCLUDED.mood_entries,
                   report_data = health_reports.report_data || EXCLUDED.report_data,
                   updated_at = NOW()`,
    [motherId, periodType, bounds.start, bounds.end, average, values.length, JSON.stringify(reportData)],
  );
  return { ...bounds, average, entries: values.length, mood_trend: values };
}

async function refreshAllReports(motherId, anchorDate) {
  await Promise.all(['daily', 'weekly', 'monthly']
    .map((type) => refreshReport(motherId, type, anchorDate)));
}

async function saveCheckin(motherId, entryDate, data) {
  const score = compositeScore(data);
  const row = await withTransaction(async (client) => {
    const duplicate = await client.query(
      'SELECT * FROM mood_checkins WHERE mother_id = $1 AND client_request_id = $2',
      [motherId, data.client_request_id],
    );
    if (duplicate.rows[0]) return duplicate.rows[0];

    const result = await client.query(
      `INSERT INTO mood_checkins
         (mother_id, entry_date, mood_rating, energy_level, sleep_quality,
          social_support, composite_score, client_request_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (mother_id, entry_date) DO UPDATE SET
         mood_rating = EXCLUDED.mood_rating,
         energy_level = EXCLUDED.energy_level,
         sleep_quality = EXCLUDED.sleep_quality,
         social_support = EXCLUDED.social_support,
         composite_score = EXCLUDED.composite_score,
         client_request_id = EXCLUDED.client_request_id,
         updated_at = NOW()
       RETURNING *`,
      [
        motherId,
        entryDate,
        data.mood_rating,
        data.energy_level ?? null,
        data.sleep_quality ?? null,
        data.social_support ?? null,
        score,
        data.client_request_id,
      ],
    );
    return result.rows[0];
  });
  require('../sleep/sleep.service').invalidate(motherId);
  await refreshAllReports(motherId, entryDate);
  return publicCheckin(row);
}

async function getCheckin(motherId, entryDate) {
  const { rows } = await query(
    'SELECT * FROM mood_checkins WHERE mother_id = $1 AND entry_date = $2',
    [motherId, entryDate],
  );
  return publicCheckin(rows[0]);
}

async function getHistory(motherId, { from, to, limit }) {
  const values = [motherId];
  const filters = ['mother_id = $1'];
  if (from) {
    values.push(from);
    filters.push(`entry_date >= $${values.length}`);
  }
  if (to) {
    values.push(to);
    filters.push(`entry_date <= $${values.length}`);
  }
  values.push(limit);
  const { rows } = await query(
    `SELECT * FROM mood_checkins WHERE ${filters.join(' AND ')}
     ORDER BY entry_date DESC LIMIT $${values.length}`,
    values,
  );
  return rows.map(publicCheckin);
}

async function getSummary(motherId, periodType, anchorDate) {
  return refreshReport(motherId, periodType, anchorDate);
}

function publicJournal(row) {
  return {
    analysis_metadata: row.analysis_metadata || {
      sentiment_source: row.entry_type === 'voice' && !row.content_encrypted ? 'not_analyzed' : 'rules',
      clinical_validation: false,
    },
    id: row.id,
    checkin_id: row.checkin_id,
    entry_type: row.entry_type,
    has_audio: row.entry_type === 'voice'
      && Boolean(row.has_audio_blob || row.voice_audio_encrypted || row.voice_object_key),
    voice_content_type: row.voice_content_type || null,
    language: row.language,
    content: row.content_encrypted ? decryptJournal(row.content_encrypted) : null,
    processing_status: row.processing_status,
    sentiment_label: row.sentiment_label,
    sentiment_score: row.sentiment_score == null ? null : Number(row.sentiment_score),
    distress_score: row.distress_score == null ? null : Number(row.distress_score),
    contains_danger: row.contains_danger,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

const JOURNAL_LIST_COLUMNS = `id, checkin_id, entry_type, language,
  content_encrypted, voice_object_key, voice_content_type,
  voice_audio_encrypted IS NOT NULL AS has_audio_blob,
  processing_status, sentiment_label, sentiment_score, distress_score,
  contains_danger, analysis_metadata, created_at, updated_at`;

const MAX_VOICE_BYTES = 4 * 1024 * 1024;
const MAX_MOTHER_VOICE_BYTES = 100 * 1024 * 1024;

async function checkinBelongsToMother(connection, motherId, checkinId) {
  if (!checkinId) return;
  const result = await connection.query('SELECT id FROM mood_checkins WHERE id=$1 AND mother_id=$2', [checkinId, motherId]);
  if (!result.rows[0]) throw new AppError('Check-in not found for this account.', 422);
}

function detectAudioMime(audio) {
  if (!Buffer.isBuffer(audio) || audio.length < 12) return null;
  if (audio.toString('ascii', 0, 4) === 'RIFF'
      && audio.toString('ascii', 8, 12) === 'WAVE') return 'audio/wav';
  if (audio.toString('ascii', 4, 8) === 'ftyp') return 'audio/mp4';
  if (audio.toString('ascii', 0, 3) === 'ID3'
      || (audio[0] === 0xff && (audio[1] & 0xe0) === 0xe0)) return 'audio/mpeg';
  return null;
}

async function savePrivateVoiceJournal(motherId, audio, data) {
  if (!Buffer.isBuffer(audio) || audio.length < 1 || audio.length > MAX_VOICE_BYTES) {
    throw new AppError('Voice note must be between 1 byte and 4 MB.', 422);
  }
  const detectedMime = detectAudioMime(audio);
  if (!detectedMime || detectedMime !== data.contentType) {
    throw new AppError('Use a WAV, M4A, or MP3 audio file.', 422);
  }
  const id = uuidv4();
  const row = await withTransaction(async (client) => {
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [motherId]);
    await checkinBelongsToMother(client, motherId, data.checkinId);
    const duplicate = await client.query(
      'SELECT * FROM journal_entries WHERE mother_id = $1 AND client_request_id = $2',
      [motherId, data.clientRequestId],
    );
    if (duplicate.rows[0]) return duplicate.rows[0];
    const usage = await client.query(
      `SELECT COALESCE(SUM(voice_size_bytes), 0)::bigint AS bytes
       FROM journal_entries WHERE mother_id = $1 AND voice_audio_encrypted IS NOT NULL`,
      [motherId],
    );
    if (Number(usage.rows[0].bytes) + audio.length > MAX_MOTHER_VOICE_BYTES) {
      throw new AppError('Private voice storage is full. Delete an old note to add another.', 413);
    }
    const inserted = await client.query(
      `INSERT INTO journal_entries
         (id, mother_id, checkin_id, entry_type, language,
          voice_audio_encrypted, voice_content_type, voice_size_bytes,
          processing_status, client_request_id)
       VALUES ($1,$2,$3,'voice',$4,$5,$6,$7,'complete',$8)
       RETURNING id, checkin_id, entry_type, language, voice_object_key,
         voice_content_type,
         voice_audio_encrypted IS NOT NULL AS has_audio_blob,
         processing_status, sentiment_label, sentiment_score, distress_score,
         contains_danger, created_at, updated_at`,
      [id, motherId, data.checkinId || null, data.language,
        encryptVoice(audio, motherId, id), detectedMime, audio.length,
        data.clientRequestId],
    );
    return inserted.rows[0];
  });
  return publicJournal(row);
}

async function getPrivateVoiceAudio(motherId, journalId) {
  const { rows } = await query(
    `SELECT voice_audio_encrypted, voice_object_key, voice_content_type,
            voice_size_bytes
     FROM journal_entries
     WHERE id = $1 AND mother_id = $2 AND entry_type = 'voice'`,
    [journalId, motherId],
  );
  const row = rows[0];
  if (!row) throw new AppError('Voice note not found.', 404);
  if (row.voice_audio_encrypted) {
    return {
      audio: decryptVoice(row.voice_audio_encrypted, motherId, journalId),
      contentType: row.voice_content_type,
    };
  }
  if (row.voice_object_key) {
    return {
      audio: await voiceService.downloadVerifiedAudio(row.voice_object_key, row.voice_size_bytes),
      contentType: row.voice_content_type,
    };
  }
  throw new AppError('Voice note is unavailable.', 404);
}

async function createTextJournal(motherId, data) {
  const analysis = await analyzeText(data.content);
  const id = uuidv4();
  const row = await withTransaction(async (client) => {
    await checkinBelongsToMother(client, motherId, data.checkin_id);
    const duplicate = await client.query(
      'SELECT * FROM journal_entries WHERE mother_id = $1 AND client_request_id = $2',
      [motherId, data.client_request_id],
    );
    if (duplicate.rows[0]) return duplicate.rows[0];

    const inserted = await client.query(
      `INSERT INTO journal_entries
         (id, mother_id, checkin_id, entry_type, language, content_encrypted,
          search_terms, sentiment_label, sentiment_score, distress_score,
          contains_danger, analysis_version, client_request_id, analysis_metadata)
       VALUES ($1,$2,$3,'text',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb)
       RETURNING *`,
      [
        id,
        motherId,
        data.checkin_id || null,
        analysis.language,
        encryptJournal(data.content),
        buildBlindIndexes(data.content),
        analysis.sentimentLabel,
        analysis.sentimentScore,
        analysis.distressScore,
        analysis.containsDanger,
        analysis.analysisVersion,
        data.client_request_id,
        JSON.stringify(analysis.metadata),
      ],
    );

    await m4Text.capture(client, motherId, 'journal', id, data.content, analysis.containsDanger);
    if (analysis.containsDanger) {
      const event = await client.query(
        `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
         VALUES ($1, 'journal', $2, 'severe')
         ON CONFLICT (source_type, source_id) DO NOTHING RETURNING id`,
        [motherId, id],
      );
      if (event.rows[0]) {
        await client.query(
          `INSERT INTO guardian_alerts
             (mother_id, guardian_id, crisis_event_id, alert_type, message)
           SELECT gl.mother_id, gl.guardian_id, $2, 'crisis',
             'URGENT: A serious safety indicator was detected. Please check on her immediately and use the crisis plan.'
           FROM guardian_links gl
           JOIN onboarding_data od ON od.user_id = gl.mother_id
           WHERE gl.mother_id = $1 AND gl.status = 'active'
             AND od.consent_tier2 = TRUE`,
          [motherId, event.rows[0].id],
        );
      }
    }
    return inserted.rows[0];
  });
  if (analysis.containsDanger) {
    await pushNotifications.processPendingSafely();
  }
  return publicJournal(row);
}

async function listJournals(motherId, limit) {
  const { rows } = await query(
    `SELECT ${JOURNAL_LIST_COLUMNS} FROM journal_entries WHERE mother_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [motherId, limit],
  );
  return rows.map(publicJournal);
}

async function searchJournals(motherId, search, limit) {
  const terms = buildBlindIndexes(search);
  if (terms.length === 0) return [];
  const { rows } = await query(
    `SELECT ${JOURNAL_LIST_COLUMNS} FROM journal_entries
     WHERE mother_id = $1 AND search_terms @> $2::text[]
     ORDER BY created_at DESC LIMIT $3`,
    [motherId, terms, limit],
  );
  return rows.map(publicJournal);
}

async function deleteJournal(motherId, journalId) {
  const { rows } = await query(
    'SELECT voice_object_key FROM journal_entries WHERE id = $1 AND mother_id = $2',
    [journalId, motherId],
  );
  if (!rows[0]) throw new AppError('Journal entry not found.', 404);
  if (rows[0].voice_object_key) {
    await voiceService.deleteAudio(rows[0].voice_object_key);
  }
  await query(
    'DELETE FROM journal_entries WHERE id = $1 AND mother_id = $2',
    [journalId, motherId],
  );
}

async function initializeVoiceJournal(motherId, data) {
  await checkinBelongsToMother({ query }, motherId, data.checkin_id);
  const journalId = uuidv4();
  const upload = await voiceService.createUploadUrl({
    motherId,
    journalId,
    contentLength: data.size_bytes,
  });
  const { rows } = await query(
    `INSERT INTO journal_entries
       (id, mother_id, checkin_id, entry_type, language, voice_object_key,
        voice_content_type, voice_size_bytes, processing_status, client_request_id)
     VALUES ($1,$2,$3,'voice',$4,$5,'audio/wav',$6,'uploading',$7)
     RETURNING id, processing_status, created_at`,
    [
      journalId,
      motherId,
      data.checkin_id || null,
      data.language,
      upload.objectKey,
      data.size_bytes,
      data.client_request_id,
    ],
  );
  return { ...rows[0], ...upload };
}

async function completeVoiceJournal(motherId, journalId) {
  const transcription = require('./transcription.service');
  const state = await transcription.request(motherId, journalId);
  void require('./transcription.worker').processPendingSafely();
  const result = await query('SELECT * FROM journal_entries WHERE id=$1 AND mother_id=$2', [journalId, motherId]);
  if (!result.rows[0]) throw new AppError('Voice note not found.', 404);
  return { ...publicJournal(result.rows[0]), transcription_status: state.status };
}

module.exports = {
  compositeScore,
  publicCheckin,
  saveCheckin,
  getCheckin,
  getHistory,
  getSummary,
  createTextJournal,
  savePrivateVoiceJournal,
  getPrivateVoiceAudio,
  listJournals,
  searchJournals,
  deleteJournal,
  initializeVoiceJournal,
  completeVoiceJournal,
  _private: { periodBounds, detectAudioMime },
};
