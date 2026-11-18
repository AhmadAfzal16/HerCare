const { withTransaction } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { ensureSchedule } = require('../screening/screening.schedule');

async function completeOnboarding(userId, data) {
  return withTransaction(async (client) => {
    const { rows: users } = await client.query(
      'SELECT role, onboarding_complete FROM users WHERE id = $1 FOR UPDATE',
      [userId],
    );
    const user = users[0];
    if (!user) throw new AppError('User not found.', 404);
    if (user.role !== 'mother') {
      throw new AppError('Mother onboarding is not available to guardian accounts.', 403);
    }

    const { rows } = await client.query(
      `INSERT INTO onboarding_data (
         user_id, full_name, age, education_level, city, months_since_birth,
         delivery_method, parity, baby_gender, has_preeclampsia,
         has_postpartum_hemorrhage, has_preterm_birth,
         has_gestational_diabetes, household_type, income_range,
         primary_support, consent_tier1, consent_tier2, consent_tier3,
         months_since_birth_recorded_at, updated_at
       ) VALUES (
         $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,NOW(),NOW()
       )
       ON CONFLICT (user_id) DO UPDATE SET
         full_name = EXCLUDED.full_name,
         age = EXCLUDED.age,
         education_level = EXCLUDED.education_level,
         city = EXCLUDED.city,
         months_since_birth = EXCLUDED.months_since_birth,
         months_since_birth_recorded_at = NOW(),
         delivery_method = EXCLUDED.delivery_method,
         parity = EXCLUDED.parity,
         baby_gender = EXCLUDED.baby_gender,
         has_preeclampsia = EXCLUDED.has_preeclampsia,
         has_postpartum_hemorrhage = EXCLUDED.has_postpartum_hemorrhage,
         has_preterm_birth = EXCLUDED.has_preterm_birth,
         has_gestational_diabetes = EXCLUDED.has_gestational_diabetes,
         household_type = EXCLUDED.household_type,
         income_range = EXCLUDED.income_range,
         primary_support = EXCLUDED.primary_support,
         consent_tier1 = EXCLUDED.consent_tier1,
         consent_tier2 = EXCLUDED.consent_tier2,
         consent_tier3 = EXCLUDED.consent_tier3,
         updated_at = NOW()
       RETURNING user_id, consent_tier1, consent_tier2, consent_tier3, updated_at`,
      [
        userId,
        data.full_name,
        data.age,
        data.education_level,
        data.city,
        data.months_since_birth,
        data.delivery_method,
        data.parity,
        data.baby_gender,
        data.has_preeclampsia,
        data.has_postpartum_hemorrhage,
        data.has_preterm_birth,
        data.has_gestational_diabetes,
        data.household_type,
        data.income_range,
        data.primary_support,
        data.consent_tier1,
        data.consent_tier2,
        data.consent_tier3,
      ],
    );

    await client.query(
      'UPDATE users SET onboarding_complete = TRUE, updated_at = NOW() WHERE id = $1',
      [userId],
    );
    await ensureSchedule(userId, client);
    return rows[0];
  });
}

async function getConsent(userId) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(`SELECT od.consent_tier1, od.consent_tier2, od.consent_tier3
      FROM onboarding_data od JOIN users u ON u.id=od.user_id
      WHERE u.id=$1 AND u.role='mother' AND u.is_active AND u.onboarding_complete`, [userId]);
    if (!rows[0]) throw new AppError('Privacy settings are unavailable for this account.', 403);
    return rows[0];
  });
}

async function updateConsent(userId, data) {
  const keys = Object.keys(data || {});
  if (keys.length !== 1 || !['consent_tier2', 'consent_tier3'].includes(keys[0]) ||
      typeof data[keys[0]] !== 'boolean') {
    throw new AppError('Choose one optional sharing permission to update.', 422);
  }
  // The identifier is selected exclusively from the fixed allow-list above.
  // Partial updates cannot overwrite another device's unrelated choice or any
  // clinical profile field. Research consent is separate and never changed here.
  return withTransaction(async (client) => {
    const { rows } = await client.query(`UPDATE onboarding_data od
      SET ${keys[0]}=$2, updated_at=NOW() FROM users u
      WHERE u.id=od.user_id AND u.id=$1 AND u.role='mother' AND u.is_active
        AND u.onboarding_complete
      RETURNING od.consent_tier1, od.consent_tier2, od.consent_tier3`, [userId, data[keys[0]]]);
    if (!rows[0]) throw new AppError('Privacy settings are unavailable for this account.', 403);
    return rows[0];
  });
}

module.exports = { completeOnboarding, getConsent, updateConsent };
