const { query } = require('../../config/database');
const { AppError } = require('../../middleware/error_handler');
const { createReadThroughCache } = require('../../utils/read_through_cache');

const instrumentCache = createReadThroughCache({ maxEntries: 16 });
const ACTIVE_TTL_MS = 30_000;
const VERSION_TTL_MS = 10 * 60_000;

function validateDefinition(definition, type, version) {
  const expectedCount = type === 'epds' ? 10 : 9;
  const expectedMax = expectedCount * 3;
  if (!definition || definition.type !== type || definition.version !== version
      || !Array.isArray(definition.questions) || definition.questions.length !== expectedCount
      || definition.max_score !== expectedMax
      || !Number.isInteger(definition.crisis_question)
      || definition.crisis_question < 1 || definition.crisis_question > expectedCount
      || !Number.isInteger(definition.timeframe_days) || definition.timeframe_days < 1
      || typeof definition.name !== 'string'
      || typeof definition.scoring_version !== 'string') {
    throw new AppError('Screening questionnaire configuration is invalid.', 503);
  }
  for (const [questionIndex, question] of definition.questions.entries()) {
    if (question.number !== questionIndex + 1
        || typeof question.text_en !== 'string' || !question.text_en.trim()
        || typeof question.text_ur !== 'string' || !question.text_ur.trim()
        || !Array.isArray(question.options) || question.options.length !== 4) {
      throw new AppError('Screening questionnaire configuration is invalid.', 503);
    }
    for (const [optionIndex, option] of question.options.entries()) {
      if (option.index !== optionIndex
          || typeof option.text_en !== 'string' || !option.text_en.trim()
          || typeof option.text_ur !== 'string' || !option.text_ur.trim()
          || !Number.isInteger(option.score) || option.score < 0 || option.score > 3) {
        throw new AppError('Screening questionnaire configuration is invalid.', 503);
      }
    }
    if (new Set(question.options.map((option) => option.score)).size !== 4) {
      throw new AppError('Screening questionnaire configuration is invalid.', 503);
    }
  }
  return definition;
}

function freezeDefinition(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freezeDefinition);
    Object.freeze(value);
  }
  return value;
}

async function readInstrument(type, version, db) {
  const { rows } = await db.query(
    `SELECT version, definition FROM screening_instruments
     WHERE instrument_type = $1 AND ${version ? 'version = $2' : 'is_active = TRUE'}
     LIMIT 1`,
    version ? [type, version] : [type],
  );
  if (!rows[0]) return null;
  return freezeDefinition(validateDefinition(rows[0].definition, type, rows[0].version));
}

async function getInstrument(type, version, db) {
  if (type !== 'epds' && type !== 'phq9') return null;
  // Transaction callers bypass process cache to preserve database isolation.
  if (db) return readInstrument(type, version, db);
  return instrumentCache.get(
    `${type}:${version || 'active'}`,
    version ? VERSION_TTL_MS : ACTIVE_TTL_MS,
    () => readInstrument(type, version, { query }),
  );
}

module.exports = { getInstrument, validateDefinition };
