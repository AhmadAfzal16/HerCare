const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const p = require('../src/modules/content/content.policy');
const r = require('../src/modules/content/content.ranking');

const { item, payload, weights, preferences } = require('./helpers/content.fixture');
const rank = (items, extra = {}) => r.rank(items, { userId: 'account', day: '2026-10-15', role: 'mother', preferences,
  context: {}, weights, now: Date.parse('2026-10-15T12:00:00Z'), limit: 30, ...extra });

test('M11 defaults do not infer a religious or music preference and context is optional', () => {
  const rows = [item(), item({ category: 'islamic', is_religious: true }), item({ category: 'soothing', is_music: true })];
  assert.equal(rank(rows).length, 1);
  assert.equal(rank(rows, { preferences: { ...preferences, religious_enabled: true } }).length, 2);
  assert.equal(rank(rows, { preferences: { ...preferences, music_enabled: true } }).length, 2);
  assert.equal(rank(rows, { preferences: { ...preferences, disabled_categories: ['psychoeducation'] } }).length, 0);
  assert.deepEqual(r.contextTags({}, 'mother'), []);
});
test('M11 unresolved safety state always suppresses feed, saved content and all context ranking', () => {
  const rows = [item({ priority: 100, saved: true, feedback: 'helpful' })];
  assert.deepEqual(rank(rows, { context: { safetyPriority: true, mood: 1 } }), []);
  assert.deepEqual(rank(rows, { context: { safetyPriority: true }, savedOnly: true }), []);
});
test('M11 only current published audience-appropriate reviewed content can be ranked', () => {
  const rows = [item(), item({ status: 'draft' }), item({ status: 'reviewed' }), item({ status: 'archived' }),
    item({ audience: 'guardian' }), item({ available_from: '2026-10-16T00:00:00Z' }),
    item({ available_until: '2026-10-15T00:00:00Z' }), item({ review_after: '2026-10-14T00:00:00Z' })];
  assert.equal(rank(rows).length, 1);
  assert.equal(rank(rows, { role: 'guardian' }).length, 2);
});
test('M11 transparent fresh context, feedback and exercise observations affect ranking without clinical claims', () => {
  const general = item(); const mood = item({ tags: ['low_mood'] }); const sleep = item({ tags: ['sleep_support'] });
  assert.equal(rank([general, mood], { context: { mood: 1 } })[0].row.id, mood.id);
  assert.equal(rank([general, sleep], { context: { sleepMinutes: 300 } })[0].row.id, sleep.id);
  assert.equal(rank([general, sleep], { context: { lateNightMinutes: 40 } })[0].row.id, sleep.id);
  const helpful = item({ feedback: 'helpful' });
  assert.equal(rank([general, helpful])[0].reasons[0], 'helpful');
  const practice = item({ category: 'activity', activity_type: 'breathing', activity_id: 'box_breathing' });
  const result = rank([practice], { context: { practice: [{ activity_type: 'breathing', activity_id: 'box_breathing', pairs: '3', improvement: '0.2' }] } });
  assert.ok(result[0].reasons.includes('practice'));
  assert.match(r.REASONS.practice[0], /does not prove treatment benefit/);
  assert.deepEqual(r.contextTags({ mood: 1, sleepMinutes: 100 }, 'guardian'), ['guardian', 'education']);
});
test('M11 dismiss hides routine content, saved retrieval preserves explicit saved selection, rotation is stable per day', () => {
  const row = item({ feedback: 'dismissed', saved: true });
  assert.equal(rank([row]).length, 0);
  assert.equal(rank([row], { savedOnly: true }).length, 1);
  assert.equal(rank([item()], { savedOnly: true }).length, 0);
  assert.equal(r.rotation('a', '2026-10-15', 'item'), r.rotation('a', '2026-10-15', 'item'));
  assert.notEqual(r.rotation('a', '2026-10-15', 'item'), r.rotation('a', '2026-10-16', 'item'));
});
test('M11 the daily verse advances each UTC day independently of feed score, feedback and input ordering', () => {
  const verses = [item({ priority: 100, saved: true }), item(), item()];
  const first = r.dailyVerse(verses, 'account', '2026-10-15');
  assert.equal(r.dailyVerse([...verses].reverse(), 'account', '2026-10-15').id, first.id);
  const second = r.dailyVerse(verses, 'account', '2026-10-16');
  const third = r.dailyVerse(verses, 'account', '2026-10-17');
  assert.equal(new Set([first.id, second.id, third.id]).size, 3);
  assert.equal(r.dailyVerse(verses, 'account', '2026-10-18').id, first.id);
  assert.equal(r.dailyVerse([], 'account', '2026-10-15'), null);
});
test('M11 category diversification does not discard useful options from a small catalog', () => {
  const rows = Array.from({ length: 6 }, () => item({ category: 'soothing', priority: 10 }));
  rows.push(item({ category: 'bonding' }));
  const ranked = rank(rows);
  assert.equal(ranked.length, 7);
  assert.equal(ranked[3].row.category, 'bonding');
});
test('M11 weights and bounded request validation reject malformed values rather than manufacturing signals', () => {
  for (const bad of [null, {}, { ...weights, context: Infinity }, { ...weights, not_helpful: 1 },
    { ...weights, category_cap: 0 }, { ...weights, extra: 1 }, { ...weights, saved: -1 }]) assert.throws(() => r.validateWeights(bad));
  for (const query of [{ limit: '31' }, { limit: '-1' }, { limit: '1.5' }, { language: 'xx' }, { raw_journal: 'text' }]) assert.throws(() => p.listQuery(query));
  assert.equal(p.listQuery({ limit: '100' }, false, 100).limit, 100);
  assert.throws(() => p.preferences({ version: 0, religious_enabled: 'false', music_enabled: false, disabled_categories: [] }));
  assert.throws(() => p.preferences({ version: 0, religious_enabled: false, music_enabled: false, disabled_categories: ['fake'] }));
});
test('M11 media links are exact HTTPS allowlisted, stripped of user data, and revoked when configuration changes', () => {
  const original = process.env.CONTENT_MEDIA_ALLOWED_HOSTS;
  process.env.CONTENT_MEDIA_ALLOWED_HOSTS = 'www.youtube.com,cdn.islamic.network,127.0.0.1,localhost,bad.internal';
  try {
    assert.equal(p.url('https://www.youtube.com/watch?v=abcdefg1234'), 'https://www.youtube.com/watch?v=abcdefg1234');
    for (const bad of ['http://www.youtube.com/watch?v=a', 'https://www.youtube.com.evil.test/watch?v=a',
      'https://www.youtube.com@evil.test/', 'https://user:pass@www.youtube.com/', 'https://www.youtube.com:444/',
      'https://127.0.0.1/', 'https://www.youtube.com/watch?v=a&user_id=secret', 'https://www.youtube.com/watch?v=a&redirect=https://evil.test/',
      'https://www.youtube.com/#token', 'file:///tmp/movie', 'javascript:alert(1)', 'https:\\www.youtube.com\\watch']) assert.throws(() => p.url(bad), bad);
    const row = item({ media_url: 'https://www.youtube.com/watch?v=abcdefg1234' });
    assert.equal(rank([row]).length, 1);
    process.env.CONTENT_MEDIA_ALLOWED_HOSTS = '';
    assert.equal(rank([row]).length, 0);
  } finally {
    if (original === undefined) delete process.env.CONTENT_MEDIA_ALLOWED_HOSTS; else process.env.CONTENT_MEDIA_ALLOWED_HOSTS = original;
  }
});
test('M11 catalog validation preserves Quran spelling/diacritics and prevents religious preference bypass', () => {
  const arabic = 'فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا';
  const data = payload({ category: 'quran', is_religious: true, arabic_text: arabic,
    transliteration: "Fa inna ma'al usri yusra", verse_reference: '94:5' });
  assert.equal(p.item(data).arabic_text, arabic);
  assert.equal(p.item(data).transliteration, "Fa inna ma'al usri yusra");
  assert.throws(() => p.item({ ...data, is_religious: false }));
  assert.throws(() => p.item({ ...data, arabic_text: null }));
  assert.throws(() => p.item({ ...data, is_music: true }));
});
test('M11 catalog validates bounded plain bilingual text, rights, local activities and unknown keys', () => {
  assert.equal(p.item(payload()).format, 'article');
  const future = new Date('2030-01-01T00:00:00Z');
  assert.equal(p.item(payload({ review_after: future })).review_after, future.toISOString());
  for (const patch of [{ title_ur: '' }, { body_en: null }, { body_en: '<script>alert(1)</script>' }, { title_en: 'a'.repeat(181) },
    { body_en: 'a\u0000b' }, { duration_seconds: 99999 }, { tags: ['<html>'] }, { tags: Array(21).fill('low_mood') },
    { category: 'islamic', is_religious: false }, { format: 'audio', media_url: null }]) assert.throws(() => p.item(payload(patch)));
  assert.throws(() => p.item({ ...payload(), patient_id: randomUUID() }));
  const local = payload({ category: 'game', format: 'activity', audience: 'mother', activity_type: 'game', activity_id: 'memory_match', body_en: null, body_ur: null });
  assert.equal(p.item(local).activity_id, 'memory_match');
  assert.throws(() => p.item({ ...local, activity_id: 'remote_download' }));
  assert.throws(() => p.item({ ...local, activity_type: 'breathing', activity_id: 'box_breathing' }));
  assert.throws(() => p.item({ ...local, audience: 'guardian' }));
  assert.throws(() => p.item({ ...local, category: 'soothing' }));
});
test('M11 availability and review timestamps require explicit valid calendar dates, times and bounded UTC offsets', () => {
  const fields = ['available_from', 'available_until', 'review_after'];
  const invalid = ['2026-02-30T00:00:00Z', '2026-02-29T00:00:00Z', '1900-02-29T00:00:00Z',
    '2026-04-31T00:00:00Z', '2026-00-01T00:00:00Z', '2026-13-01T00:00:00Z', '2026-01-00T00:00:00Z',
    '2026-10-15T24:00:00Z', '2026-10-15T12:60:00Z', '2026-10-15T12:00:60Z',
    '2026-10-15T12:00:00', '2026-10-15', '2026-10-15T12:00:00+15:00',
    '2026-10-15T12:00:00-14:01', '2026-10-15T12:00:00+05:60', '2026-10-15T12:00:00+25:00',
    '2026-10-15T12:00:00+0500', '2026-10-15T12:00:00Zjunk', '0000-01-01T00:00:00Z'];
  for (const field of fields) for (const value of invalid) assert.throws(() => p.item(payload({ [field]: value })), `${field}: ${value}`);
  for (const value of ['2024-02-29T12:30:00Z', '2000-02-29T12:30:00.123456Z', '2026-10-15T12:00:00+05:00',
    '2026-10-15T12:00:00+14:00', '2026-10-15T12:00:00-14:00']) {
    assert.equal(p.item(payload({ review_after: value })).review_after, new Date(value).toISOString());
  }
  assert.equal(p.item(payload({ review_after: new Date('2030-01-01T00:00:00Z') })).review_after, '2030-01-01T00:00:00.000Z');
  assert.throws(() => p.item(payload({ review_after: new Date('invalid') })));
});
