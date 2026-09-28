const crypto = require('crypto');
const { query, withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const logger = require('../../utils/logger');
const pushNotifications = require('../notifications/notification.service');

const INVITE_TTL_HOURS = 24;
const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateSecureCode() {
  const bytes = crypto.randomBytes(12);
  let code = '';
  for (let i = 0; i < bytes.length; i += 1) {
    code += INVITE_ALPHABET[bytes[i] % INVITE_ALPHABET.length];
  }
  return code;
}

function epdsToRisk(score) {
  if (score === null || score === undefined) return null;
  if (score <= 8) return 'low';
  if (score <= 12) return 'moderate';
  if (score <= 18) return 'high';
  return 'severe';
}

function getGuardianRecommendations(riskLevel, lang = 'en') {
  const tips = {
    unknown: {
      en: [
        'Check in with her and listen without judgment.',
        'Encourage her to complete her next wellbeing check-in.',
        'Seek professional help if you are concerned about her safety.',
      ],
      ur: [
        'ان سے بات کریں اور بغیر تنقید کے سنیں۔',
        'انہیں اگلا صحت کا جائزہ مکمل کرنے کی ترغیب دیں۔',
        'اگر ان کی حفاظت کے بارے میں فکر ہو تو پیشہ ورانہ مدد حاصل کریں۔',
      ],
    },
    low: {
      en: [
        'Keep daily check-ins with her and ask how she is feeling.',
        'Help with household tasks to reduce her workload.',
        'Celebrate small wins and acknowledge her effort.',
      ],
      ur: [
        'روزانہ ان سے پوچھیں کہ وہ کیسا محسوس کر رہی ہیں۔',
        'گھر کے کاموں میں مدد کریں تاکہ ان کا بوجھ کم ہو۔',
        'چھوٹی کامیابیوں کو سراہیں اور ان کی کوشش تسلیم کریں۔',
      ],
    },
    moderate: {
      en: [
        'Spend time with her and listen without judgment.',
        'Encourage regular HerCare check-ins.',
        'Offer to care for the baby so she can rest.',
        'Consider arranging a counsellor appointment together.',
      ],
      ur: [
        'ان کے ساتھ وقت گزاریں اور بغیر تنقید کے سنیں۔',
        'انہیں HerCare میں باقاعدگی سے صحت کا جائزہ لینے کی ترغیب دیں۔',
        'بچے کی دیکھ بھال کریں تاکہ وہ آرام کر سکیں۔',
        'ایک کونسلر سے ملنے کا انتظام کرنے پر غور کریں۔',
      ],
    },
    high: {
      en: [
        'Do not leave her alone for long periods.',
        'Arrange an urgent doctor or mental health appointment.',
        'Limit access to potentially harmful objects if you are concerned.',
        'Reassure her that postpartum depression is treatable.',
      ],
      ur: [
        'انہیں زیادہ دیر تنہا نہ چھوڑیں۔',
        'فوری طور پر ڈاکٹر یا ذہنی صحت کے ماہر سے وقت لیں۔',
        'اگر فکر ہو تو ممکنہ نقصان دہ اشیاء تک رسائی محدود کریں۔',
        'انہیں یقین دلائیں کہ زچگی کے بعد کا ڈیپریشن قابل علاج ہے۔',
      ],
    },
    severe: {
      en: [
        'URGENT: Stay with her and assess immediate safety.',
        'Use the verified crisis contacts shown in the HerCare crisis screen.',
        'Take her to the nearest emergency or psychiatric facility now.',
        'Activate her crisis plan in HerCare.',
      ],
      ur: [
        'فوری: ان کے ساتھ رہیں اور فوری حفاظت کا جائزہ لیں۔',
        'HerCare کی کرائسس اسکرین پر تصدیق شدہ رابطے استعمال کریں۔',
        'انہیں فوری طور پر قریبی ایمرجنسی یا نفسیاتی مرکز لے جائیں۔',
        'HerCare میں ان کا کرائسس پلان فعال کریں۔',
      ],
    },
  };
  const safeLang = lang === 'ur' ? 'ur' : 'en';
  return (tips[riskLevel] || tips.unknown)[safeLang];
}

function formatUtcDate(date) {
  return date.toISOString().slice(0, 10);
}

function getCanonicalPeriod(periodType, anchorDate = new Date()) {
  const anchor = typeof anchorDate === 'string'
    ? new Date(`${anchorDate}T00:00:00.000Z`)
    : new Date(anchorDate);
  if (Number.isNaN(anchor.getTime())) {
    throw new AppError('Invalid report anchor date.', 422);
  }

  const start = new Date(Date.UTC(
    anchor.getUTCFullYear(), anchor.getUTCMonth(), anchor.getUTCDate(),
  ));
  const end = new Date(start);

  if (periodType === 'weekly') {
    const mondayOffset = start.getUTCDay() === 0 ? 6 : start.getUTCDay() - 1;
    start.setUTCDate(start.getUTCDate() - mondayOffset);
    end.setTime(start.getTime());
    end.setUTCDate(end.getUTCDate() + 6);
  } else if (periodType === 'monthly') {
    start.setUTCDate(1);
    end.setUTCFullYear(start.getUTCFullYear(), start.getUTCMonth() + 1, 0);
  } else if (periodType !== 'daily') {
    throw new AppError('Unsupported report period.', 422);
  }
  return { periodStart: formatUtcDate(start), periodEnd: formatUtcDate(end) };
}

async function assertGuardianConsent(db, motherId) {
  const { rows } = await db.query(
    'SELECT consent_tier2 FROM onboarding_data WHERE user_id = $1',
    [motherId],
  );
  if (!rows[0]?.consent_tier2) {
    throw new AppError('Guardian report sharing consent is required.', 403);
  }
}

async function generateInvite(motherId) {
  return withTransaction(async (client) => {
    const { rows: users } = await client.query(
      'SELECT role FROM users WHERE id = $1 AND is_active = TRUE FOR UPDATE',
      [motherId],
    );
    if (users[0]?.role !== 'mother') {
      throw new AppError('Only mothers can generate invite codes.', 403);
    }
    await assertGuardianConsent(client, motherId);

    const active = await client.query(
      "SELECT id FROM guardian_links WHERE mother_id = $1 AND status = 'active' LIMIT 1",
      [motherId],
    );
    if (active.rowCount > 0) {
      throw new AppError('You already have a linked guardian. Revoke it first.', 409);
    }

    await client.query(
      `UPDATE guardian_links SET status = 'revoked', revoked_at = NOW()
       WHERE mother_id = $1 AND status = 'pending'`,
      [motherId],
    );

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const code = generateSecureCode();
      try {
        const { rows } = await client.query(
          `INSERT INTO guardian_links (mother_id, invite_code, status, expires_at)
           VALUES ($1, $2, 'pending', NOW() + ($3 * INTERVAL '1 hour'))
           RETURNING id, invite_code, created_at, expires_at`,
          [motherId, code, INVITE_TTL_HOURS],
        );
        logger.info(`Guardian invite generated for mother ${motherId}`);
        return rows[0];
      } catch (error) {
        if (error.code !== '23505') throw error;
      }
    }
    throw new AppError('Could not generate an invite code. Please retry.', 503);
  });
}

async function getPendingInvite(motherId) {
  await query(
    `UPDATE guardian_links SET status = 'revoked', revoked_at = NOW()
     WHERE mother_id = $1 AND status = 'pending' AND expires_at <= NOW()`,
    [motherId],
  );
  const { rows } = await query(
    `SELECT invite_code, created_at, expires_at FROM guardian_links
     WHERE mother_id = $1 AND status = 'pending' AND expires_at > NOW()
     ORDER BY created_at DESC LIMIT 1`,
    [motherId],
  );
  return rows[0] || null;
}

async function acceptInvite(guardianId, inviteCode, guardianName, relationship) {
  const result = await withTransaction(async (client) => {
    const guardian = await client.query(
      'SELECT role FROM users WHERE id = $1 AND is_active = TRUE FOR UPDATE',
      [guardianId],
    );
    if (guardian.rows[0]?.role !== 'guardian') {
      throw new AppError('Only guardian accounts can accept invite codes.', 403);
    }

    const { rows: links } = await client.query(
      `SELECT id, mother_id, expires_at FROM guardian_links
       WHERE invite_code = $1 AND status = 'pending' FOR UPDATE`,
      [inviteCode.toUpperCase()],
    );
    if (!links[0]) throw new AppError('Invalid or expired invite code.', 404);

    const link = links[0];
    if (!link.expires_at || new Date(link.expires_at) <= new Date()) {
      await client.query(
        "UPDATE guardian_links SET status = 'revoked', revoked_at = NOW() WHERE id = $1",
        [link.id],
      );
      return { expired: true };
    }
    if (link.mother_id === guardianId) {
      throw new AppError('You cannot link to your own account.', 422);
    }
    await assertGuardianConsent(client, link.mother_id);

    const existing = await client.query(
      "SELECT id FROM guardian_links WHERE guardian_id = $1 AND status = 'active' LIMIT 1",
      [guardianId],
    );
    if (existing.rowCount > 0) {
      throw new AppError('This guardian account is already linked.', 409);
    }

    const { rows } = await client.query(
      `UPDATE guardian_links
       SET guardian_id = $1, guardian_name = $2, relationship = $3,
           status = 'active', accepted_at = NOW(), invite_code = NULL
       WHERE id = $4 AND status = 'pending'
       RETURNING id, mother_id, guardian_id, guardian_name, relationship,
                 status, accepted_at`,
      [guardianId, guardianName.trim(), relationship, link.id],
    );
    if (!rows[0]) throw new AppError('Invite code was already used.', 409);
    return rows[0];
  });

  if (result.expired) throw new AppError('This invite code has expired.', 410);
  logger.info(`Guardian ${guardianId} linked to mother ${result.mother_id}`);
  return result;
}

async function getLink(userId, role) {
  let sql;
  if (role === 'mother') {
    sql = `SELECT gl.id, gl.guardian_id, gl.guardian_name, gl.relationship,
                  gl.status, gl.accepted_at, u.phone AS guardian_phone
           FROM guardian_links gl
           JOIN users u ON u.id = gl.guardian_id AND u.is_active = TRUE
           WHERE gl.mother_id = $1 AND gl.status = 'active'
           ORDER BY gl.accepted_at DESC LIMIT 1`;
  } else if (role === 'guardian') {
    sql = `SELECT gl.id, gl.mother_id, gl.guardian_name, gl.relationship,
                  gl.status, gl.accepted_at, u.phone AS mother_phone
           FROM guardian_links gl
           JOIN users u ON u.id = gl.mother_id AND u.is_active = TRUE
           WHERE gl.guardian_id = $1 AND gl.status = 'active'
           ORDER BY gl.accepted_at DESC LIMIT 1`;
  } else {
    throw new AppError('This account cannot use guardian links.', 403);
  }
  const { rows } = await query(sql, [userId]);
  return rows[0] || null;
}

async function revokeLink(motherId) {
  const { rowCount } = await query(
    `UPDATE guardian_links
     SET status = 'revoked', revoked_at = NOW(), invite_code = NULL
     WHERE mother_id = $1 AND status = 'active'`,
    [motherId],
  );
  if (rowCount === 0) throw new AppError('No active guardian link found.', 404);
  logger.info(`Guardian link revoked by mother ${motherId}`);
  return { revoked: true };
}

async function getDashboard(guardianId, lang = 'en') {
  const link = await getLink(guardianId, 'guardian');
  if (!link) throw new AppError('You are not linked to a mother account.', 403);
  await assertGuardianConsent({ query }, link.mother_id);

  const { rows: reports } = await query(
    `SELECT id, period_type, period_start, period_end, avg_mood, epds_score,
            risk_level, sleep_avg_h, mood_entries, report_data, created_at
     FROM health_reports WHERE mother_id = $1
     ORDER BY period_end DESC, updated_at DESC LIMIT 1`,
    [link.mother_id],
  );
  const latestReport = reports[0] || null;
  const riskLevel = latestReport?.risk_level || null;
  const moodTrend = Array.isArray(latestReport?.report_data?.mood_trend)
    ? latestReport.report_data.mood_trend
    : [];

  const alerts = await getAlerts(guardianId, 5);
  return {
    mother_id: link.mother_id,
    link_status: 'active',
    linked_since: link.accepted_at,
    risk_level: riskLevel,
    epds_score: latestReport?.epds_score ?? null,
    avg_mood: latestReport?.avg_mood ?? null,
    mood_trend: moodTrend,
    recommendations: getGuardianRecommendations(riskLevel, lang),
    alerts,
    last_updated: latestReport?.created_at || null,
    data_status: latestReport?.report_data?.status || 'insufficient_data',
  };
}

async function resolveMotherId(userId, role) {
  if (role === 'mother') return userId;
  if (role !== 'guardian') throw new AppError('Not authorized.', 403);
  const link = await getLink(userId, 'guardian');
  if (!link) throw new AppError('You are not linked to a mother account.', 403);
  await assertGuardianConsent({ query }, link.mother_id);
  return link.mother_id;
}

async function getReports(userId, role, periodType = 'weekly', limit = 7) {
  const motherId = await resolveMotherId(userId, role);
  const { rows } = await query(
    `SELECT id, period_type, period_start, period_end, avg_mood, epds_score,
            risk_level, sleep_avg_h, mood_entries,
            report_data->>'status' AS data_status, created_at, updated_at
     FROM health_reports WHERE mother_id = $1 AND period_type = $2
     ORDER BY period_start DESC LIMIT $3`,
    [motherId, periodType, limit],
  );
  return rows;
}

async function getReportById(userId, role, reportId) {
  const motherId = await resolveMotherId(userId, role);
  const { rows } = await query(
    'SELECT * FROM health_reports WHERE id = $1 AND mother_id = $2',
    [reportId, motherId],
  );
  if (!rows[0]) throw new AppError('Report not found.', 404);
  return rows[0];
}

async function generateReport(motherId, periodType, anchorDate) {
  await assertGuardianConsent({ query }, motherId);
  const { periodStart, periodEnd } = getCanonicalPeriod(periodType, anchorDate);
  const reportData = {
    status: 'insufficient_data',
    generated_by: 'system',
    generated_at: new Date().toISOString(),
    note: 'Clinical metrics will populate when screening, mood, and sleep modules record data.',
  };
  const { rows } = await query(
    `INSERT INTO health_reports
       (mother_id, period_type, period_start, period_end, mood_entries, report_data)
     VALUES ($1, $2, $3, $4, 0, $5::jsonb)
     ON CONFLICT (mother_id, period_type, period_start, period_end)
     DO UPDATE SET updated_at = NOW()
     RETURNING *`,
    [motherId, periodType, periodStart, periodEnd, JSON.stringify(reportData)],
  );
  return rows[0];
}

async function notifyGuardian(motherId, riskLevel, reportId = null) {
  if (!['high', 'severe'].includes(riskLevel)) return;
  const { rows: links } = await query(
    `SELECT gl.guardian_id FROM guardian_links gl
     JOIN onboarding_data od ON od.user_id = gl.mother_id
     WHERE gl.mother_id = $1 AND gl.status = 'active'
       AND od.consent_tier2 = TRUE LIMIT 1`,
    [motherId],
  );
  if (!links[0]) return;

  const alertType = riskLevel === 'severe' ? 'risk_severe' : 'risk_high';
  const message = riskLevel === 'severe'
    ? 'URGENT: A severe risk indicator was detected. Please check on her immediately and use the crisis plan.'
    : 'A high risk indicator was detected. Please check on her and help arrange professional support.';
  await query(
    `INSERT INTO guardian_alerts
       (mother_id, guardian_id, report_id, alert_type, message)
     VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`,
    [motherId, links[0].guardian_id, reportId, alertType, message],
  );
  await pushNotifications.processPendingSafely();
  logger.warn(`Guardian risk alert created for guardian ${links[0].guardian_id}`);
}

async function getAlerts(guardianId, limit = 20) {
  const { rows } = await query(
    `SELECT ga.id, ga.alert_type, ga.message, ga.is_read, ga.triggered_at
     FROM guardian_alerts ga
     WHERE ga.guardian_id = $1 AND EXISTS (
       SELECT 1 FROM guardian_links gl
       JOIN onboarding_data od ON od.user_id = gl.mother_id
       JOIN users u ON u.id = gl.mother_id AND u.is_active = TRUE
       WHERE gl.guardian_id = ga.guardian_id AND gl.mother_id = ga.mother_id
         AND gl.status = 'active' AND od.consent_tier2 = TRUE
     )
     ORDER BY ga.triggered_at DESC LIMIT $2`,
    [guardianId, limit],
  );
  return rows;
}

async function markAlertsRead(guardianId, alertIds = []) {
  const params = [guardianId];
  let filter = '';
  if (alertIds.length > 0) {
    params.push(alertIds);
    filter = ' AND id = ANY($2::uuid[])';
  }
  const { rowCount } = await query(
    `UPDATE guardian_alerts SET is_read = TRUE
     WHERE guardian_id = $1 AND is_read = FALSE${filter}`,
    params,
  );
  return { updated: rowCount };
}

module.exports = {
  generateInvite,
  acceptInvite,
  getLink,
  revokeLink,
  getDashboard,
  getReports,
  getReportById,
  generateReport,
  notifyGuardian,
  getAlerts,
  markAlertsRead,
  getPendingInvite,
  getGuardianRecommendations,
  _private: { generateSecureCode, epdsToRisk, getCanonicalPeriod },
};
