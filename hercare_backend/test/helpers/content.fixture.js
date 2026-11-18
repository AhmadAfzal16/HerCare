const { randomUUID } = require('node:crypto');
const p = require('../../src/modules/content/content.policy');

const weights = { context: 30, helpful: 18, not_helpful: -25, practice: 12, saved: 5, rotation: 6, category_cap: 3 };
const preferences = { religious_enabled: false, music_enabled: false, disabled_categories: [], version: 0 };
function item(extra = {}) {
  return { id: randomUUID(), version: 1, status: 'published', title_en: 'A short pause', title_ur: 'مختصر وقفہ',
    summary_en: 'Take a gentle pause.', summary_ur: 'تھوڑا آرام کریں۔', body_en: 'Notice your surroundings.', body_ur: 'اپنے اردگرد کو دیکھیں۔',
    category: 'psychoeducation', format: 'article', audience: 'both', is_religious: false, is_music: false,
    tags: [], priority: 0, saved: false, feedback: null, ...extra };
}
function payload(extra = {}) {
  const value = item(extra);
  return Object.fromEntries(p.CONTENT_KEYS.map((key) => [key, value[key] ?? null]));
}
module.exports = { item, payload, weights, preferences };
