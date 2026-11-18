const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { validateRecoveryResponse } = require('../src/modules/risk/recovery.response');

test('actual private Python recovery response obeys the Node monitoring contract', {
  skip: process.env.RUN_RECOVERY_PYTHON_TEST !== '1',
}, () => {
  const ml = path.resolve(__dirname, '../../hercare_ml');
  const python = process.env.HERCARE_TEST_PYTHON || path.join(ml, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
  assert.ok(fs.existsSync(python), 'Configure the project Python test environment');
  const code = [
    'import json, os',
    'from fastapi.testclient import TestClient',
    'from app.main import app',
    'os.environ["ENVIRONMENT"] = "production"',
    'os.environ["ML_SERVICE_TOKEN"] = "synthetic-recovery-contract-only"',
    'client = TestClient(app)',
    'assert client.post("/v1/recovery", json={"as_of":"2026-10-09"}).status_code == 401',
    'results = []',
    'for language in ["en", "ur"]:',
    '    body = {"as_of":"2026-10-09", "observations":[{"entry_date":"2026-10-08","mood_rating":3},{"entry_date":"2026-10-09","mood_rating":4}], "screenings":[], "sleep_observations":[{"entry_date":"2026-10-08","sleep_minutes":400,"quality":3,"awakenings":2,"bedtime_minute":1435,"wake_minute":420},{"entry_date":"2026-10-09","sleep_minutes":420,"quality":4,"awakenings":1,"bedtime_minute":5,"wake_minute":425}]}',
    '    for instrument, previous_date in [("epds","2026-10-02"),("phq9","2026-09-25")]:',
    '        body["screenings"] += [{"instrument":instrument,"version":"synthetic-v1","language":language,"completed_date":previous_date,"score":18,"safety_positive":instrument=="epds"},{"instrument":instrument,"version":"synthetic-v1","language":language,"completed_date":"2026-10-09","score":12}]',
    '    r = client.post("/v1/recovery", json=body, headers={"Authorization":"Bearer synthetic-recovery-contract-only"})',
    '    assert r.status_code == 200, r.text',
    '    results.append(r.json())',
    '    body["as_of"] = "2026-10-30"',
    '    r = client.post("/v1/recovery", json=body, headers={"Authorization":"Bearer synthetic-recovery-contract-only"})',
    '    assert r.status_code == 200, r.text',
    '    results.append(r.json())',
    'print(json.dumps(results, ensure_ascii=False, allow_nan=False))',
  ].join('\n');
  const result = spawnSync(python, ['-X', 'utf8', '-c', code], {
    cwd: ml, encoding: 'utf8', timeout: 60000, maxBuffer: 192 * 1024,
  });
  assert.equal(result.status, 0, `Private test process failed: ${result.error?.message || result.stderr.slice(-1500)}`);
  const responses = JSON.parse(result.stdout);
  assert.equal(responses.length, 4);
  for (const [index, raw] of responses.entries()) {
    const response = validateRecoveryResponse(raw);
    const monitoring = response.depression_monitoring;
    assert.equal(monitoring.future_outlook.probability, null);
    assert.equal(monitoring.future_outlook.status, 'not_trained');
    assert.equal(monitoring.requires_safety_review, true);
    assert.equal(monitoring.safety_history.resolution_known, false);
    for (const trend of monitoring.screening_trends) {
      assert.equal(trend.language, index < 2 ? 'en' : 'ur');
      if (index % 2 === 0) {
        assert.equal(trend.direction, 'lower_recorded_symptoms');
        assert.equal(trend.score_change_points, -6);
      } else {
        assert.equal(trend.direction, 'insufficient_data');
        assert.equal(trend.stale, true);
      }
    }
  }
});
