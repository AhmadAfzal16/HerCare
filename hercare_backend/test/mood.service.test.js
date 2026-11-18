const test = require('node:test');
const assert = require('node:assert/strict');

const { analyzeJournal, detectLanguage } = require('../src/modules/mood/journal_analysis');
const {
  encryptJournal,
  decryptJournal,
  encryptVoice,
  decryptVoice,
  buildBlindIndexes,
} = require('../src/modules/mood/journal_crypto');
const {
  compositeScore,
  publicCheckin,
  _private: { periodBounds, detectAudioMime },
} = require('../src/modules/mood/mood.service');

test('private voice encryption authenticates the owner and resists tampering', () => {
  const audio = Buffer.from('RIFF1234WAVEprivate voice');
  const owner = 'c565e5ca-12bd-48e5-80dd-56cc513ef3d1';
  const journal = 'e58677c5-2a5c-42ba-9e75-7c414f363bd0';
  const encrypted = encryptVoice(audio, owner, journal);
  assert.equal(encrypted.includes(audio), false);
  assert.deepEqual(decryptVoice(encrypted, owner, journal), audio);
  assert.throws(() => decryptVoice(encrypted, 'other-user', journal));
  encrypted[encrypted.length - 1] ^= 1;
  assert.throws(() => decryptVoice(encrypted, owner, journal));
});

test('voice signatures distinguish supported audio from disguised files', () => {
  assert.equal(detectAudioMime(Buffer.from('RIFF1234WAVEdata')), 'audio/wav');
  assert.equal(detectAudioMime(Buffer.from('0000ftypM4A data')), 'audio/mp4');
  assert.equal(detectAudioMime(Buffer.from('ID3some mp3 data')), 'audio/mpeg');
  assert.equal(detectAudioMime(Buffer.from('%PDF-1.5 fake.wav')), null);
});
const { checkinValidation, validate } = require('../src/modules/mood/mood.validator');

test('mood-only check-in validates without optional observations', async () => {
  const req = {
    params: { entryDate: '2026-09-24' },
    body: {
      mood_rating: 4,
      client_request_id: 'c832ba98-7f98-4cab-b306-352871195231',
    },
  };
  for (const rule of checkinValidation) await rule.run(req);
  let accepted = false;
  validate(req, { status: () => ({ json: () => {} }) }, () => { accepted = true; });
  assert.equal(accepted, true);
});

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
  assert.equal(compositeScore({ mood_rating: 4 }), 4);
  assert.equal(compositeScore({ mood_rating: 4, energy_level: 2 }), 3.33);
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
  const brief = publicCheckin({
    mood_rating: 4,
    energy_level: null,
    sleep_quality: null,
    social_support: null,
    composite_score: '4.00',
  });
  assert.equal(brief.energy_level, null);
  assert.equal(brief.sleep_quality, null);
  assert.equal(brief.social_support, null);
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
