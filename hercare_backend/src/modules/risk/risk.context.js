const { query } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');

function validateContext(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AppError('Model context must be an object.', 422);
  const fields = ['number_of_children', 'basic_needs_affordable', 'mother_in_law_relationship'];
  if (Object.keys(body).some((key) => !fields.includes(key))) throw new AppError('Unknown model-context field.', 422);
  const children = body.number_of_children ?? null;
  const affordable = body.basic_needs_affordable ?? null;
  const relationship = body.mother_in_law_relationship ?? null;
  if (children !== null && (!Number.isInteger(children) || children < 0 || children > 20)) throw new AppError('Invalid child count.', 422);
  if (affordable !== null && typeof affordable !== 'boolean') throw new AppError('Affordability must be yes, no or unknown.', 422);
  if (relationship !== null && !['poor', 'moderate', 'good'].includes(relationship)) throw new AppError('Invalid relationship response.', 422);
  return { number_of_children: children, basic_needs_affordable: affordable, mother_in_law_relationship: relationship };
}
async function getContext(motherId) {
  const { rows } = await query('SELECT number_of_children,basic_needs_affordable,mother_in_law_relationship FROM risk_context WHERE mother_id=$1', [motherId]);
  return rows[0] || validateContext({});
}
async function saveContext(motherId, body) {
  const data = validateContext(body);
  const { rows } = await query(`INSERT INTO risk_context(mother_id,number_of_children,basic_needs_affordable,mother_in_law_relationship)
    SELECT $1,$2,$3,$4 FROM users u JOIN onboarding_data o ON o.user_id=u.id
      WHERE u.id=$1 AND u.is_active AND u.role='mother' AND o.consent_tier1
    ON CONFLICT(mother_id) DO UPDATE SET number_of_children=EXCLUDED.number_of_children,
      basic_needs_affordable=EXCLUDED.basic_needs_affordable,mother_in_law_relationship=EXCLUDED.mother_in_law_relationship,updated_at=NOW()
    RETURNING number_of_children,basic_needs_affordable,mother_in_law_relationship`,
  [motherId, data.number_of_children, data.basic_needs_affordable, data.mother_in_law_relationship]);
  if (!rows[0]) throw new AppError('Active mother account and basic consent required.', 403);
  return rows[0];
}
module.exports = { validateContext, getContext, saveContext };
