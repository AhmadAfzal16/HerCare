process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-at-least-thirty-two-bytes';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-at-least-thirty-two-bytes';

const test = require('node:test');
const assert = require('node:assert/strict');
const { _private } = require('../src/modules/therapy/therapy.service');
const { isKnownActivity } = require('../src/modules/therapy/therapy.catalog');
const { normalizeSession } = require('../src/modules/therapy/therapy.validator');

test('optional breathing participation is distinct from timer completion', () => {
  const base = {
    activity_type: 'breathing', activity_id: 'box_breathing', duration_seconds: 12,
    completed: false, client_request_id: '4bc83dfa-3ca1-46ba-bf88-853337908a29',
  };
  assert.equal(normalizeSession(base).breathing_participation, undefined);
  const withAnswer = normalizeSession({ ...base, breathing_participation: 'some_cues' });
  assert.equal(withAnswer.breathing_participation, 'some_cues');
  assert.equal(withAnswer.completed, false);
  assert.throws(() => normalizeSession({ ...base, breathing_participation: 'camera_verified' }), { statusCode: 422 });
  assert.throws(() => normalizeSession({ ...base, activity_type: 'game', activity_id: 'memory_match',
    breathing_participation: 'some_cues' }), { statusCode: 422 });
});

test('low mood prioritizes grounding without making a clinical claim', () => {
  const value = _private.chooseRecommendation({
    mood: 2, sleepQuality: 4, screenMinutes: 20, lateNightMinutes: 0, safetyPriority: false,
  });
  assert.equal(value.activity_id, 'grounding_54321');
  assert.equal(value.safety_priority, false);
});

test('safety signal always overrides ordinary activity selection', () => {
  const value = _private.chooseRecommendation({
    mood: 5, sleepQuality: 5, screenMinutes: 0, lateNightMinutes: 0, safetyPriority: true,
  });
  assert.equal(value.safety_priority, true);
  assert.equal(value.activity_id, 'breathing_478');
});

test('catalog rejects arbitrary activity identifiers', () => {
  assert.equal(isKnownActivity('game', 'memory_match'), true);
  assert.equal(isKnownActivity('game', 'downloaded_heavy_game'), false);
});

test('M9 history does not replace safety/grounding or fabricate benefit from absent, sparse or negative pairs', () => {
  const signals = { mood: 4, sleepQuality: 2, screenMinutes: 0, lateNightMinutes: 0, safetyPriority: false };
  const row = { activity_type: 'meditation', activity_id: 'mindfulness', paired_mood_sessions: 3, avg_mood_change: 1 };
  for (const history of [[], [{ ...row, paired_mood_sessions: 2 }], [{ ...row, avg_mood_change: 0 }],
    [{ ...row, avg_mood_change: -1 }], [{ ...row, avg_mood_change: 5 }],
    [{ ...row, paired_mood_sessions: 3.5 }], [{ ...row, activity_type: 'game', activity_id: 'memory_match' }]]) {
    const result = _private.rankRecommendation(signals, history, 'body_scan');
    assert.equal(result.activity_id, 'body_scan');
    assert.equal(result.selection_source, 'recent_context_rules');
    assert.equal(result.history_observation, undefined);
    assert.equal(result.clinical_improvement, false);
  }
  assert.equal(_private.rankRecommendation({ ...signals, mood: 2 }, [row], 'grounding_54321').activity_id, 'grounding_54321');
  const safe = _private.rankRecommendation({ ...signals, safetyPriority: true }, [row], 'breathing_478');
  assert.equal(safe.safety_priority, true);
  assert.equal(safe.activity_id, 'breathing_478');
});

test('M9 paired-history preference stays in the context category and is explicitly an optional observation', () => {
  const signals = { mood: 4, sleepQuality: 2, screenMinutes: 0, lateNightMinutes: 0, safetyPriority: false };
  const history = [
    { activity_type: 'meditation', activity_id: 'body_scan', paired_mood_sessions: '3', avg_mood_change: '0.5' },
    { activity_type: 'meditation', activity_id: 'mindfulness', paired_mood_sessions: '3', avg_mood_change: '1' },
    { activity_type: 'game', activity_id: 'memory_match', paired_mood_sessions: '10', avg_mood_change: '4' },
  ];
  const result = _private.rankRecommendation(signals, history, 'mindfulness');
  assert.equal(result.activity_type, 'meditation');
  assert.equal(result.activity_id, 'mindfulness');
  assert.equal(result.selection_source, 'optional_paired_practice_ratings');
  assert.equal(result.history_observation.paired_mood_sessions, 3);
  assert.equal(result.history_observation.avg_mood_change, 1);
  assert.equal(result.history_observation.period_days, 30);
  assert.equal(result.history_observation.practice_verified, false);
  assert.equal(result.clinical_improvement, false);
  assert.match(result.reason, /not proof of treatment benefit/);
  const tied = _private.rankRecommendation(signals, [history[1], { ...history[0], avg_mood_change: '1' }], 'mindfulness');
  assert.equal(tied.activity_id, 'body_scan', 'a tied observation can prefer a different recent practice without claiming efficacy');
});

