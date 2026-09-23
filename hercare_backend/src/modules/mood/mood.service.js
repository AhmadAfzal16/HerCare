const { v4: uuidv4 } = require('uuid');
const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const {
  encryptJournal,
  decryptJournal,
  buildBlindIndexes,
} = require('./journal_crypto');
const { analyzeJournal } = require('./journal_analysis');
const voiceService = require('./voice.service');

function compositeScore(data) {
  return Number((
    data.mood_rating * 0.4
    + data.energy_level * 0.2
    + data.sleep_quality * 0.2
    + data.social_support * 0.2
  ).toFixed(2));
}

function publicCheckin(row) {
  if (!row) return null;
  return {
    ...row,
    mood_rating: Number(row.mood_rating),
    energy_level: Number(row.energy_level),
    sleep_quality: Number(row.sleep_quality),
    social_support: Number(row.social_support),
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
    `SELECT entry_date, composite_score::float AS composite_score
     FROM mood_checkins
     WHERE mother_id = $1 AND entry_date BETWEEN $2 AND $3
     ORDER BY entry_date`,
    [motherId, bounds.start, bounds.end],
  );
  const values = rows.map((row) => Number(row.composite_score));
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
        data.energy_level,
        data.sleep_quality,
        data.social_support,
        score,
        data.client_request_id,
      ],
    );
    return result.rows[0];
  });
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
    id: row.id,
    checkin_id: row.checkin_id,
    entry_type: row.entry_type,
    language: row.language,
    content: row.content_encrypted ? decryptJournal(row.content_encrypted) : null,
    processing_status: row.processing_status,
    sentiment_label: row.sentiment_label,
    sentiment_score: row.sentiment_score === null ? null : Number(row.sentiment_score),
    distress_score: row.distress_score === null ? null : Number(row.distress_score),
    contains_danger: row.contains_danger,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function createTextJournal(motherId, data) {
  const analysis = analyzeJournal(data.content);
  const id = uuidv4();
  const row = await withTransaction(async (client) => {
    const duplicate = await client.query(
      'SELECT * FROM journal_entries WHERE mother_id = $1 AND client_request_id = $2',
      [motherId, data.client_request_id],
    );
    if (duplicate.rows[0]) return duplicate.rows[0];

    const inserted = await client.query(
      `INSERT INTO journal_entries
         (id, mother_id, checkin_id, entry_type, language, content_encrypted,
          search_terms, sentiment_label, sentiment_score, distress_score,
          contains_danger, analysis_version, client_request_id)
       VALUES ($1,$2,$3,'text',$4,$5,$6,$7,$8,$9,$10,$11,$12)
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
      ],
    );

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
             (mother_id, guardian_id, alert_type, message)
           SELECT gl.mother_id, gl.guardian_id, 'crisis',
             'URGENT: A serious safety indicator was detected. Please check on her immediately and use the crisis plan.'
           FROM guardian_links gl
           JOIN onboarding_data od ON od.user_id = gl.mother_id
           WHERE gl.mother_id = $1 AND gl.status = 'active'
             AND od.consent_tier2 = TRUE`,
          [motherId],
        );
      }
    }
    return inserted.rows[0];
  });
  return publicJournal(row);
}

async function listJournals(motherId, limit) {
  const { rows } = await query(
    `SELECT * FROM journal_entries WHERE mother_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [motherId, limit],
  );
  return rows.map(publicJournal);
}

async function searchJournals(motherId, search, limit) {
  const terms = buildBlindIndexes(search);
  if (terms.length === 0) return [];
  const { rows } = await query(
    `SELECT * FROM journal_entries
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
  const { rows } = await query(
    `UPDATE journal_entries SET processing_status = 'processing'
     WHERE id = $1 AND mother_id = $2 AND entry_type = 'voice'
       AND processing_status IN ('uploading', 'pending', 'failed')
     RETURNING *`,
    [journalId, motherId],
  );
  const journal = rows[0];
  if (!journal) {
    const existing = await query(
      'SELECT * FROM journal_entries WHERE id = $1 AND mother_id = $2',
      [journalId, motherId],
    );
    if (existing.rows[0]?.processing_status === 'complete') {
      return publicJournal(existing.rows[0]);
    }
    throw new AppError('Voice journal entry is unavailable.', 404);
  }

  try {
    const audio = await voiceService.downloadVerifiedAudio(
      journal.voice_object_key,
      journal.voice_size_bytes,
    );
    const transcript = await voiceService.transcribeAudio(audio, journal.language);
    if (!transcript) throw new AppError('No speech could be transcribed.', 422);
    const analysis = analyzeJournal(transcript);
    const updated = await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE journal_entries SET
           language = $1, content_encrypted = $2, search_terms = $3,
           processing_status = 'complete', sentiment_label = $4,
           sentiment_score = $5, distress_score = $6, contains_danger = $7,
           analysis_version = $8, updated_at = NOW()
         WHERE id = $9 AND mother_id = $10 RETURNING *`,
        [
          analysis.language,
          encryptJournal(transcript),
          buildBlindIndexes(transcript),
          analysis.sentimentLabel,
          analysis.sentimentScore,
          analysis.distressScore,
          analysis.containsDanger,
          analysis.analysisVersion,
          journalId,
          motherId,
        ],
      );
      if (analysis.containsDanger) {
        const event = await client.query(
          `INSERT INTO crisis_events (mother_id, source_type, source_id, severity)
           VALUES ($1, 'voice_journal', $2, 'severe')
           ON CONFLICT (source_type, source_id) DO NOTHING RETURNING id`,
          [motherId, journalId],
        );
        if (event.rows[0]) {
          await client.query(
            `INSERT INTO guardian_alerts
               (mother_id, guardian_id, alert_type, message)
             SELECT gl.mother_id, gl.guardian_id, 'crisis',
               'URGENT: A serious safety indicator was detected. Please check on her immediately and use the crisis plan.'
             FROM guardian_links gl
             JOIN onboarding_data od ON od.user_id = gl.mother_id
             WHERE gl.mother_id = $1 AND gl.status = 'active'
               AND od.consent_tier2 = TRUE`,
            [motherId],
          );
        }
      }
      return result.rows[0];
    });
    return publicJournal(updated);
  } catch (error) {
    await query(
      `UPDATE journal_entries SET processing_status = 'failed', updated_at = NOW()
       WHERE id = $1 AND mother_id = $2`,
      [journalId, motherId],
    );
    throw error;
  }
}

module.exports = {
  compositeScore,
  publicCheckin,
  saveCheckin,
  getCheckin,
  getHistory,
  getSummary,
  createTextJournal,
  listJournals,
  searchJournals,
  deleteJournal,
  initializeVoiceJournal,
  completeVoiceJournal,
  _private: { periodBounds },
};
