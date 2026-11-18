const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { validateReply } = require('../src/modules/chatbot/chatbot.client');

// A bounded, synthetic real-Python/FastAPI exchange without any running server.
// Does not read accounts, export health records or launch the Flutter app.
test('actual Python chatbot endpoint obeys Node contract in all three languages', {
  skip: process.env.RUN_CHATBOT_PYTHON_TEST !== '1',
}, () => {
  const ml = path.resolve(__dirname, '../../hercare_ml');
  const python = process.env.HERCARE_TEST_PYTHON || path.join(ml, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
  assert.ok(fs.existsSync(python), 'Configure the project Python test environment');
  const code = [
    'import json, os, sys',
    'from fastapi.testclient import TestClient',
    'from app.main import app',
    'os.environ["ENVIRONMENT"] = "production"',
    'os.environ["ML_SERVICE_TOKEN"] = "synthetic-contract-test-only"',
    'os.environ["CHATBOT_GENERATION_ENABLED"] = "false"',
    'context = json.load(open("../hercare_backend/test/chatbot_context.fixture.json"))',
    'client = TestClient(app)',
    'results = []',
    'for language in ["en", "ur", "roman_ur"]:',
    '    r = client.post("/v1/chatbot/reply", json={"message":"I feel alone", "language":language, "context":context}, headers={"Authorization":"Bearer synthetic-contract-test-only"})',
    '    assert r.status_code == 200, r.status_code',
    '    results.append(r.json())',
    'print(json.dumps(results, ensure_ascii=False))',
  ].join('\n');
  const result = spawnSync(python, ['-X', 'utf8', '-c', code], { cwd: ml, encoding: 'utf8', timeout: 60000, maxBuffer: 128 * 1024 });
  assert.equal(result.status, 0, `Private test process failed: ${result.error?.message || result.stderr.slice(-1000)}`);
  const responses = JSON.parse(result.stdout);
  for (const [index, language] of ['en', 'ur', 'roman_ur'].entries()) {
    const reply = validateReply(responses[index], language);
    assert.equal(reply.clinical_validation, false);
    assert.equal(reply.safety.guardian_alert_allowed, false);
    assert.ok(reply.reply.includes('65.0%'), 'Real bounded aggregate fixture must round-trip');
    assert.ok(reply.reply.includes('PHQ9'));
  }
});
