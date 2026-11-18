const { createHash } = require('node:crypto');
const policy = require('./content.policy');

const REASONS = Object.freeze({
  general: ['A reviewed option to explore at your own pace.', 'اپنی سہولت سے دیکھنے کے لیے جائزہ شدہ مواد۔'],
  low_mood: ['A gentle option based on your recent mood check-in.', 'حالیہ مزاج کی بنیاد پر ایک نرم سرگرمی۔'],
  positive_mood: ['A positive everyday activity based on your recent check-in.', 'حالیہ مزاج کی بنیاد پر روزمرہ کی مثبت سرگرمی۔'],
  sleep_support: ['A short wind-down option based on recent sleep information.', 'حالیہ نیند کی معلومات کی بنیاد پر آرام کا مختصر انتخاب۔'],
  screen_break: ['A low-stimulation option after recent device use.', 'حالیہ موبائل استعمال کے بعد کم تحریک والا انتخاب۔'],
  education: ['Reviewed information to support understanding, not a diagnosis.', 'سمجھنے میں مدد کے لیے جائزہ شدہ معلومات، تشخیص نہیں۔'],
  guardian: ['Information for supporting a postpartum partner.', 'زچگی کے بعد شریکِ حیات کی مدد کے لیے معلومات۔'],
  helpful: ['You previously marked this content as helpful.', 'آپ نے پہلے اس مواد کو مفید کہا تھا۔'],
  practice: ['Your optional practice ratings favored this activity; this does not prove treatment benefit.', 'آپ کی اختیاری ریٹنگ میں یہ مشق بہتر رہی؛ یہ علاج کے فائدے کا ثبوت نہیں۔'],
});

function rotation(userId, day, id) {
  return createHash('sha256').update(`${userId}|${day}|${id}`).digest().readUInt32BE(0) / 0x100000000;
}
function dailyVerse(rows, userId, day) {
  if (!rows.length) return null;
  const ordered = [...rows].sort((a, b) => a.id.localeCompare(b.id));
  const dayNumber = Math.floor(Date.parse(`${day}T00:00:00Z`) / 86400000);
  const accountOffset = Math.floor(rotation(userId, 'daily-verse', 'offset') * ordered.length);
  // Stable for a UTC day, advances one reviewed verse per day while the eligible set is unchanged.
  return ordered[(dayNumber + accountOffset) % ordered.length];
}
function validateWeights(weights) {
  const keys = ['context', 'helpful', 'not_helpful', 'practice', 'saved', 'rotation', 'category_cap'];
  if (!weights || keys.some((key) => !Number.isFinite(weights[key]))
      || Object.keys(weights).some((key) => !keys.includes(key))
      || keys.filter((key) => !['not_helpful', 'category_cap'].includes(key)).some((key) => weights[key] < 0 || weights[key] > 100)
      || weights.not_helpful > 0 || weights.not_helpful < -100 || !Number.isInteger(weights.category_cap)
      || weights.category_cap < 1 || weights.category_cap > 10) policy.fail('Content ranking configuration needs review.', 503);
  return weights;
}
function contextTags(context, role) {
  if (role === 'guardian') return ['guardian', 'education'];
  const tags = [];
  if (context.mood != null && context.mood <= 2) tags.push('low_mood');
  if (context.mood != null && context.mood >= 4) tags.push('positive_mood');
  if (context.sleepQuality != null && context.sleepQuality <= 2 || context.sleepMinutes != null && context.sleepMinutes < 360
      || context.lateNightMinutes != null && context.lateNightMinutes >= 30) tags.push('sleep_support');
  if (context.screenMinutes != null && context.screenMinutes >= 300) tags.push('screen_break');
  if (context.screeningRisk && ['high', 'severe'].includes(context.screeningRisk)) tags.push('education', 'low_mood');
  return [...new Set(tags)];
}
function eligible(row, preferences, role, now = Date.now()) {
  if (row.status !== 'published' || !['both', role].includes(row.audience)
      || row.is_religious && !preferences.religious_enabled || row.is_music && !preferences.music_enabled
      || preferences.disabled_categories.includes(row.category)
      || row.available_from && Date.parse(row.available_from) > now
      || row.available_until && Date.parse(row.available_until) <= now
      || row.review_after && Date.parse(row.review_after) <= now) return false;
  // Revalidate at read time: operator allowlist changes revoke existing links immediately.
  try {
    if (row.media_url) policy.url(row.media_url);
    if (row.source_url) policy.url(row.source_url);
  } catch { return false; }
  return true;
}
function rank(rows, { userId, day, role, preferences, context, weights, limit = 20, savedOnly = false, now = Date.now() }) {
  validateWeights(weights);
  if (context.safetyPriority) return [];
  const activeTags = contextTags(context, role);
  const ranked = rows.filter((row) => eligible(row, preferences, role, now) && (savedOnly ? row.saved : row.feedback !== 'dismissed'))
    .map((row) => {
      const matched = activeTags.filter((tag) => row.tags.includes(tag));
      const reasons = [...matched];
      let score = Number(row.priority || 0) + matched.length * weights.context
        + rotation(userId, day, row.id) * weights.rotation + (row.saved ? weights.saved : 0);
      if (row.feedback === 'helpful') { score += weights.helpful; reasons.unshift('helpful'); }
      if (row.feedback === 'not_helpful') score += weights.not_helpful;
      const practice = context.practice?.find((item) => item.activity_type === row.activity_type && item.activity_id === row.activity_id
        && Number(item.pairs) >= 3 && Number(item.improvement) > 0);
      if (practice) { score += weights.practice; reasons.push('practice'); }
      if (!reasons.length) reasons.push(role === 'guardian' ? 'guardian' : 'general');
      return { row, score, reasons };
    }).sort((a, b) => b.score - a.score || a.row.id.localeCompare(b.row.id));
  if (savedOnly) return ranked.slice(0, limit);
  const counts = new Map(); const result = []; const overflow = [];
  for (const candidate of ranked) {
    const count = counts.get(candidate.row.category) || 0;
    if (count < weights.category_cap) { result.push(candidate); counts.set(candidate.row.category, count + 1); }
    else overflow.push(candidate);
  }
  return [...result, ...overflow].slice(0, limit);
}

module.exports = { rank, eligible, rotation, dailyVerse, contextTags, validateWeights, REASONS };
