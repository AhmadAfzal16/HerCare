const { Router } = require('express');
const rateLimit = require('express-rate-limit');
const { authenticate } = require('../../middleware/auth');
const { query, withTransaction } = require('../../config/database');
const { _private: { periodBounds } } = require('../mood/mood.service');
const { AppError } = require('../../middleware/error_handler');
const { validateSleep, summarize } = require('./sleep.logic');

const router = Router();
router.use(authenticate);
router.use(async (req, _res, next) => {
  try {
    if (req.user.role !== 'mother') throw new AppError('Sleep records are private to mother accounts.', 403);
    const { rows } = await query(
      `SELECT u.id FROM users u JOIN onboarding_data od ON od.user_id = u.id
       WHERE u.id = $1 AND u.is_active = TRUE AND od.consent_tier1 = TRUE`, [req.user.userId],
    );
    if (!rows.length) throw new AppError('Active account and basic monitoring consent required.', 403);
    next();
  } catch (error) { next(error); }
});
router.get('/', async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT sleep_date::text, bedtime, wake_time, awake_minutes, quality, awakenings,
        timezone_offset_minutes,
        EXTRACT(EPOCH FROM (wake_time - bedtime))/60 - awake_minutes AS sleep_minutes
       FROM sleep_records WHERE mother_id = $1 ORDER BY sleep_date DESC LIMIT 30`, [req.user.userId],
    );
    res.json({ success: true, data: { records: rows, summary: summarize(rows) } });
  } catch (error) { next(error); }
});
router.put('/', rateLimit({ windowMs: 900000, max: 60, standardHeaders: true, legacyHeaders: false }), async (req, res, next) => {
  try {
    const data = validateSleep(req.body);
    await withTransaction(async (client) => {
    // Serialize same-account updates so overlapping saves cannot leave stale averages.
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [req.user.userId]);
    await client.query(
      `INSERT INTO sleep_records (mother_id, sleep_date, bedtime, wake_time, awake_minutes,
       quality, awakenings, timezone_offset_minutes) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (mother_id, sleep_date) DO UPDATE SET bedtime = EXCLUDED.bedtime,
       wake_time = EXCLUDED.wake_time, awake_minutes = EXCLUDED.awake_minutes,
       quality = EXCLUDED.quality, awakenings = EXCLUDED.awakenings,
       timezone_offset_minutes = EXCLUDED.timezone_offset_minutes, updated_at = NOW()`,
      [req.user.userId, data.sleep_date, data.bedtime, data.wake_time, data.awake_minutes,
        data.quality, data.awakenings, data.timezone_offset_minutes],
    );
    const consent = await client.query('SELECT consent_tier2 FROM onboarding_data WHERE user_id = $1', [req.user.userId]);
    if (consent.rows[0]?.consent_tier2) {
      for (const type of ['daily', 'weekly', 'monthly']) {
        const bounds = periodBounds(type, data.sleep_date);
        await client.query(
          `INSERT INTO health_reports (mother_id, period_type, period_start, period_end, sleep_avg_h, report_data)
           SELECT $1, $2, $3::date, $4::date,
             ROUND(AVG(EXTRACT(EPOCH FROM (wake_time - bedtime))/3600 - awake_minutes/60.0), 2),
             jsonb_build_object('status', 'available', 'sleep_source', 'self_reported', 'sleep_nights', COUNT(*))
           FROM sleep_records WHERE mother_id = $1 AND sleep_date BETWEEN $3::date AND $4::date
           ON CONFLICT (mother_id, period_type, period_start, period_end) DO UPDATE SET
             sleep_avg_h = EXCLUDED.sleep_avg_h,
             report_data = health_reports.report_data || EXCLUDED.report_data, updated_at = NOW()`,
          [req.user.userId, type, bounds.start, bounds.end],
        );
      }
    }
    });
    res.json({ success: true });
  } catch (error) { next(error); }
});
module.exports = router;
