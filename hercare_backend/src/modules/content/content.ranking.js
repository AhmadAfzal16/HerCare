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
  mood_declining: ['A gentle option because your mood check-ins have dipped this week.', 'اس ہفتے آپ کے مزاج کی ریٹنگ کچھ کم رہی، اس لیے ایک نرم انتخاب۔'],
  stage: ['Chosen for where you are in the months after birth.', 'زچگی کے بعد آپ کے موجودہ مرحلے کے مطابق منتخب کیا گیا۔'],
  recovery: ['Chosen for the birth and recovery details you shared.', 'آپ کی بتائی گئی زچگی اور صحت یابی کی معلومات کے مطابق۔'],
  support: ['Chosen for the family support situation you shared.', 'آپ کے بتائے گئے خاندانی تعاون کے حالات کے مطابق۔'],
  interest: ['Matches a topic you chose in your preferences.', 'آپ کی پسند میں چنے گئے موضوع کے مطابق۔'],
  affinity: ['Similar to content you watched, listened to or read before.', 'اس مواد سے ملتا جلتا جو آپ نے پہلے دیکھا، سنا یا پڑھا۔'],
  explore: ['Something different to try, in case it helps.', 'کچھ نیا آزمانے کے لیے، شاید مددگار ہو۔'],
});

// Topics she can pick herself. Each maps to catalog tags/categories; `music` and `faith`
// still require the separate music/religious opt-ins, which `eligible` enforces first.
const INTERESTS = Object.freeze({
  sleep: { tags: ['sleep_support', 'sleep', 'baby_sleep'] },
  calm: { tags: ['relaxation', 'calm', 'breathing', 'meditation'], categories: ['soothing'] },
  music: { music: true },
  low_mood: { tags: ['low_mood', 'mood_declining'] },
  anxiety: { tags: ['anxiety'] },
  feeding: { tags: ['feeding', 'breastfeeding'] },
  body_recovery: { tags: ['cesarean_recovery', 'physical_recovery', 'recovery', 'postnatal_exercise'] },
  baby_bonding: { tags: ['bonding', 'baby_care'], categories: ['bonding'] },
  relationships: { tags: ['relationships', 'partner', 'joint_family', 'low_support'] },
  faith: { categories: ['islamic', 'quran'] },
  learning: { tags: ['education'], categories: ['psychoeducation'] },
});
const FORMATS = Object.freeze(['article', 'audio', 'video', 'activity']);
const AFFINITY_HALF_LIFE_DAYS = 21;

// Profile tags come from onboarding, not today's state, so they use the separate `profile` weight.
const STAGE_TAGS = Object.freeze(['stage_0_6w', 'stage_6w_3m', 'stage_3_6m', 'stage_6_12m', 'stage_12m_plus']);
const PROFILE_REASON = Object.freeze({
  ...Object.fromEntries(STAGE_TAGS.map((tag) => [tag, 'stage'])),
  cesarean_recovery: 'recovery', physical_recovery: 'recovery', preterm_baby: 'recovery', health_followup: 'recovery',
  low_support: 'support', joint_family: 'support',
});
const OPTIONAL_WEIGHTS = Object.freeze({ profile: 20, repeat: -8, novelty: 4, affinity: 15, interest: 25, format: 8, explore_slots: 1 });
const REPEAT_WINDOW_DAYS = 14;

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
// Returns the weights with Phase 1 keys defaulted, so rows saved before migration 024 keep working.
function validateWeights(input) {
  const required = ['context', 'helpful', 'not_helpful', 'practice', 'saved', 'rotation', 'category_cap'];
  const keys = [...required, ...Object.keys(OPTIONAL_WEIGHTS)];
  const weights = input && typeof input === 'object' ? { ...OPTIONAL_WEIGHTS, ...input } : null;
  const negative = ['not_helpful', 'repeat'];
  if (!weights || keys.some((key) => !Number.isFinite(weights[key]))
      || Object.keys(input).some((key) => !keys.includes(key))
      || keys.filter((key) => ![...negative, 'category_cap'].includes(key)).some((key) => weights[key] < 0 || weights[key] > 100)
      || negative.some((key) => weights[key] > 0 || weights[key] < -100) || !Number.isInteger(weights.category_cap)
      || weights.category_cap < 1 || weights.category_cap > 10
      || !Number.isInteger(weights.explore_slots) || weights.explore_slots > 3) policy.fail('Content ranking configuration needs review.', 503);
  return weights;
}
// Interests she picked herself that this item matches.
function interestMatches(row, interests = []) {
  return interests.filter((key) => {
    const rule = INTERESTS[key];
    if (!rule) return false;
    return rule.music && row.is_music || (rule.tags || []).some((tag) => (row.tags || []).includes(tag))
      || (rule.categories || []).includes(row.category);
  });
}
// How strongly she engaged with one item, decayed so last month's habits fade.
// Dismissing hides an item but is not read as dislike of its whole topic.
function engagementStrength(row, now) {
  let strength = Math.min(Number(row.view_count || 0), 5) + 2 * Math.min(Number(row.media_opens || 0), 5)
    + 3 * Math.min(Number(row.completions || 0), 5) + (row.saved ? 2 : 0);
  if (row.feedback === 'helpful') strength += 4;
  if (row.feedback === 'not_helpful') strength -= 4;
  if (!strength) return 0;
  const last = row.last_engaged_at || row.last_viewed_at;
  const days = last ? Math.max((now - new Date(last).getTime()) / 86400000, 0) : AFFINITY_HALF_LIFE_DAYS;
  return Number.isFinite(days) ? strength * 0.5 ** (days / AFFINITY_HALF_LIFE_DAYS) : 0;
}
const affinityKeys = (row) => [...new Set([...(row.tags || []).filter((tag) => !STAGE_TAGS.includes(tag)), `category:${row.category}`])];
// Per-account topic profile learned from the candidate rows themselves (no extra query).
function affinityModel(rows, now) {
  const totals = new Map(); const strengths = new Map(); const engagedCategories = new Set();
  for (const row of rows) {
    const strength = engagementStrength(row, now);
    if (!strength) continue;
    strengths.set(row.id, strength);
    if (strength > 0) engagedCategories.add(row.category);
    for (const key of affinityKeys(row)) totals.set(key, (totals.get(key) || 0) + strength);
  }
  const max = Math.max(0, ...totals.values());
  return { totals, strengths, max, engagedCategories };
}
// Strength needed before learned taste counts fully (about 3 finished videos, or a
// few opens plus a "helpful"). One tap must not reshape the whole feed.
const AFFINITY_CONFIDENCE = 10;
// -1..1: how much this item's topics match what she engaged with, excluding the item's own history.
function affinityScore(row, model) {
  if (!model.max) return 0;
  const scale = Math.max(model.max, AFFINITY_CONFIDENCE);
  const own = model.strengths.get(row.id) || 0;
  let best = 0;
  for (const key of affinityKeys(row)) {
    const value = (model.totals.get(key) || 0) - own;
    if (Math.abs(value) > Math.abs(best)) best = value;
  }
  return Math.max(-1, Math.min(1, best / scale));
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
  // 7-day trends: a run of low days matters even when today's single check-in looks fine.
  const mood = context.moodTrend;
  if (mood && mood.days >= 3 && mood.average != null && mood.average <= 2.5) tags.push('low_mood');
  if (mood && mood.recent != null && mood.earlier != null && mood.recent - mood.earlier <= -1) tags.push('mood_declining', 'low_mood');
  const sleep = context.sleepTrend;
  if (sleep && sleep.nights >= 3 && (sleep.averageMinutes != null && sleep.averageMinutes < 360
      || sleep.averageQuality != null && sleep.averageQuality <= 2)) tags.push('sleep_support');
  return [...new Set(tags)];
}
function stageTag(months) {
  if (months == null || !Number.isFinite(months) || months < 0) return null;
  if (months < 1.5) return 'stage_0_6w';
  if (months < 3) return 'stage_6w_3m';
  if (months < 6) return 'stage_3_6m';
  if (months <= 12) return 'stage_6_12m';
  return 'stage_12m_plus';
}
function profileTags(profile, role) {
  if (role === 'guardian' || !profile) return [];
  const months = profile.monthsPostpartum;
  const early = months != null && months < 3;
  const firstYear = months != null && months <= 12;
  const tags = [stageTag(months)];
  if (early && profile.deliveryMethod === 'cesarean') tags.push('cesarean_recovery');
  if (early && (profile.hemorrhage || profile.preeclampsia)) tags.push('physical_recovery');
  if (firstYear && profile.pretermBirth) tags.push('preterm_baby');
  if (firstYear && (profile.preeclampsia || profile.gestationalDiabetes)) tags.push('health_followup');
  if (profile.primarySupport === 'none') tags.push('low_support');
  if (profile.householdType === 'joint') tags.push('joint_family');
  return [...new Set(tags.filter(Boolean))];
}
// Opened recently → gently push down so the feed rotates; never-opened → small boost.
// Activities are practices meant to be repeated, and helpful/saved items are her choice, so they are exempt.
function repeatAdjustment(row, weights, now) {
  const views = Number(row.view_count || 0);
  if (!views) return row.saved ? 0 : weights.novelty;
  if (row.format === 'activity' || row.saved || row.feedback === 'helpful' || !row.last_viewed_at) return 0;
  const days = (now - new Date(row.last_viewed_at).getTime()) / 86400000;
  if (!Number.isFinite(days) || days >= REPEAT_WINDOW_DAYS) return 0;
  return weights.repeat * Math.min(views, 3) * (1 - Math.max(days, 0) / REPEAT_WINDOW_DAYS);
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
function rank(rows, { userId, day, role, preferences, context, weights, limit = 20, savedOnly = false, now = Date.now(), language = 'en' }) {
  weights = validateWeights(weights);
  if (context.safetyPriority) return [];
  const activeTags = contextTags(context, role);
  const activeProfile = profileTags(context.profile, role);
  const interests = preferences.interests || [];
  const formats = preferences.preferred_formats || [];
  const model = affinityModel(rows, now);
  const ranked = rows.filter((row) => eligible(row, preferences, role, now) && (savedOnly ? row.saved : row.feedback !== 'dismissed'))
    .map((row) => {
      const matched = activeTags.filter((tag) => row.tags.includes(tag));
      const profileMatched = activeProfile.filter((tag) => row.tags.includes(tag));
      const chosen = interestMatches(row, interests);
      const affinity = affinityScore(row, model);
      // Today's state explains the card first, then her own choices, then profile, then learned taste.
      const reasons = [...matched.filter((tag) => tag !== 'low_mood' || !matched.includes('mood_declining')),
        ...(chosen.length ? ['interest'] : []), ...new Set(profileMatched.map((tag) => PROFILE_REASON[tag])),
        ...(affinity >= 0.5 ? ['affinity'] : [])];
      // One bonus for any chosen topic (plus a little per extra match), so chips cannot swamp today's state.
      let score = Number(row.priority || 0) + matched.length * weights.context + profileMatched.length * weights.profile
        + (chosen.length ? weights.interest * (1 + 0.2 * (chosen.length - 1)) : 0)
        + (formats.includes(row.format) ? weights.format : 0) + affinity * weights.affinity
        // Spoken-Urdu media is easier to follow when she reads the app in Urdu.
        + (language === 'ur' && row.tags.includes('urdu') ? weights.format : 0)
        + rotation(userId, day, row.id) * weights.rotation + (row.saved ? weights.saved : 0)
        + (savedOnly ? 0 : repeatAdjustment(row, weights, now));
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
  return explore([...result, ...overflow], model, weights.explore_slots).slice(0, limit);
}
// Keep the feed from narrowing: move the best item from a category she has not engaged with
// into slots 3 and 7. Only once she has some history; before that everything is new anyway.
const EXPLORE_POSITIONS = [2, 6, 10];
function explore(list, model, slots) {
  if (!slots || !model.engagedCategories.size || list.length < 4) return list;
  const picks = [];
  for (const candidate of list.slice(EXPLORE_POSITIONS[0])) {
    if (picks.length >= slots) break;
    const { row } = candidate;
    if (model.engagedCategories.has(row.category) || row.feedback === 'not_helpful' || model.strengths.has(row.id)
        || picks.some((pick) => pick.row.category === row.category)) continue;
    picks.push(candidate);
  }
  if (!picks.length) return list;
  const rest = list.filter((candidate) => !picks.includes(candidate));
  picks.forEach((pick, index) => {
    if (['general', 'guardian'].includes(pick.reasons[0])) pick.reasons = ['explore'];
    rest.splice(Math.min(EXPLORE_POSITIONS[index], rest.length), 0, pick);
  });
  return rest;
}

module.exports = { rank, eligible, rotation, dailyVerse, contextTags, profileTags, stageTag, repeatAdjustment, validateWeights,
  interestMatches, engagementStrength, affinityModel, affinityScore, explore,
  REASONS, STAGE_TAGS, PROFILE_REASON, INTERESTS, FORMATS };
