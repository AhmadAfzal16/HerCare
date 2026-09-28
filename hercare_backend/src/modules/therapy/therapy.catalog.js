const ACTIVITIES = Object.freeze({
  breathing: new Set(['breathing_478', 'box_breathing', 'diaphragmatic']),
  meditation: new Set(['body_scan', 'muscle_relaxation', 'mindfulness']),
  cbt: new Set(['thought_challenge', 'behavior_plan', 'worry_time', 'grounding_54321']),
  game: new Set(['memory_match', 'breathing_bubbles', 'color_calm']),
});

function isKnownActivity(type, id) {
  return ACTIVITIES[type]?.has(id) === true;
}

module.exports = { ACTIVITIES, isKnownActivity };

