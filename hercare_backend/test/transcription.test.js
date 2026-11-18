const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { encryptTranscript, decryptTranscript, transcriptFingerprint } = require('../src/modules/mood/journal_crypto');
const { validateResult } = require('../src/modules/mood/transcription.client');
const { confirmation } = require('../src/modules/mood/transcription.service');

test('M5 transcript encryption binds mother and journal; fingerprints are keyed', () => {
  const owner = randomUUID(), journal = randomUUID();
  const text = 'میں آج اداس ہوں';
  const encrypted = encryptTranscript(text, owner, journal);
  assert.equal(encrypted.includes(text), false);
  assert.equal(decryptTranscript(encrypted, owner, journal), text);
  assert.throws(() => decryptTranscript(encrypted, randomUUID(), journal));
  assert.throws(() => decryptTranscript(encrypted, owner, randomUUID()));
  assert.notEqual(transcriptFingerprint(text, owner, journal), transcriptFingerprint(text, randomUUID(), journal));
});
test('M5 accepts only bounded, explicitly unreviewed ASR results', () => {
  const valid = { status: 'draft', text: 'I feel tired', language: 'en', model_version: 'test-only', review_required: true };
  assert.equal(validateResult(valid).text, valid.text);
  for (const change of [{ review_required: false }, { text: 'x'.repeat(5001) }, { status: 'confirmed' }, { language: 'ar' }]) {
    assert.throws(() => validateResult({ ...valid, ...change }));
  }
  assert.equal(validateResult({ ...valid, status: 'no_speech', text: '' }).text, '');
  assert.throws(() => validateResult({ ...valid, status: 'no_speech' }));
});
test('M5 confirmations are bounded and cannot smuggle guardian destinations or model scores', () => {
  const value = { content: ' My actual words ', revision: 1, client_request_id: randomUUID() };
  assert.equal(confirmation(value).content, 'My actual words');
  for (const change of [{ content: '' }, { revision: 0 }, { revision: '1' }, { guardian_id: randomUUID() }, { probability: .9 }]) {
    assert.throws(() => confirmation({ ...value, ...change }));
  }
});
