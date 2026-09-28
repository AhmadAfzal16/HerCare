const test = require('node:test');
const assert = require('node:assert/strict');

const { analyzeJournal, detectLanguage } = require('../src/modules/mood/journal_analysis');
const {
  encryptJournal,
  decryptJournal,
  buildBlindIndexes,
} = require('../src/modules/mood/journal_crypto');
const {
  compositeScore,
  publicCheckin,
  _private: { periodBounds },
} = require('../src/modules/mood/mood.service');

test('journal encryption round-trips without storing plaintext', () => {
  const plaintext = 'میں آج بہتر محسوس کر رہی ہوں';
  const encrypted = encryptJournal(plaintext);
  assert.notEqual(encrypted, plaintext);
  assert.equal(encrypted.includes(plaintext), false);
  assert.equal(decryptJournal(encrypted), plaintext);
});

test('blind search indexes are deterministic and do not expose words', () => {
  const first = buildBlindIndexes('Feeling calm and supported');
  const second = buildBlindIndexes('calm');
  assert.equal(first.includes(second[0]), true);
  assert.equal(first.includes('calm'), false);
});

test('danger language is detected in English, Urdu, and Roman Urdu', () => {
  assert.equal(analyzeJournal('I want to hurt myself').containsDanger, true);
  assert.equal(analyzeJournal('میں خود کشی کرنا چاہتی ہوں').containsDanger, true);
  assert.equal(analyzeJournal('main khudkushi karna chahti hun').containsDanger, true);
});

test('language detection distinguishes English, Urdu, and mixed text', () => {
  assert.equal(detectLanguage('I feel calm'), 'en');
  assert.equal(detectLanguage('میں بہتر ہوں'), 'ur');
  assert.equal(detectLanguage('آج I feel better'), 'mixed');
});

test('composite mood score uses transparent configured weights', () => {
  assert.equal(compositeScore({
    mood_rating: 5,
    energy_level: 4,
    sleep_quality: 3,
    social_support: 2,
  }), 3.8);
});

test('check-in API output normalizes PostgreSQL numeric strings', () => {
  const result = publicCheckin({
    id: 'checkin-id',
    mood_rating: 5,
    energy_level: 4,
    sleep_quality: 3,
    social_support: 2,
    composite_score: '3.80',
  });
  assert.equal(result.composite_score, 3.8);
  assert.equal(typeof result.composite_score, 'number');
});

test('summary periods use canonical calendar boundaries', () => {
  assert.deepEqual(periodBounds('weekly', '2026-09-23'), {
    start: '2026-09-21',
    end: '2026-09-27',
  });
  assert.deepEqual(periodBounds('monthly', '2026-02-10'), {
    start: '2026-02-01',
    end: '2026-02-28',
  });
});
