const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const policy = require('../src/modules/community/community.policy');

// Authored examples and in-process FastAPI requests only; no listener, database
// writes, private posts, cloud inference or mobile app launch.
test('actual CPU moderation API obeys Node contract in three languages', {
  skip: process.env.RUN_COMMUNITY_MODEL_TEST !== '1',
}, async () => {
  const directory = path.resolve(__dirname, '../../hercare_ml');
  const python = process.env.HERCARE_TEST_PYTHON
    || path.join(directory, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
  const code = [
    'import json, os',
    'from fastapi.testclient import TestClient',
    'from app.main import app',
    'os.environ["ENVIRONMENT"] = "production"',
    'os.environ["ML_SERVICE_TOKEN"] = "synthetic-community-contract-only"',
    'headers = {"Authorization": "Bearer synthetic-community-contract-only"}',
    'with TestClient(app) as client:',
    '    assert client.get("/v1/community/ready").status_code == 401',
    '    probe = client.get("/v1/community/ready", headers=headers)',
    '    assert probe.status_code == 200, probe.text',
    '    output = []',
    '    for text in ["You are not alone. We support you.", "آپ اکیلی نہیں ہیں، ہم آپ کے ساتھ ہیں۔", "Aap akeli nahi hain, hum aap ke saath hain."]:',
    '        response = client.post("/v1/community/moderate", headers=headers, json={"text":text})',
    '        assert response.status_code == 200, response.text',
    '        assert response.headers["cache-control"] == "private, no-store"',
    '        output.append(response.json())',
    '    print(json.dumps({"ready":probe.json(), "results":output}))',
  ].join('\n');
  const result = spawnSync(python, ['-X', 'utf8', '-c', code], {
    cwd: directory, encoding: 'utf8', timeout: 45000, maxBuffer: 64 * 1024,
  });
  assert.equal(result.status, 0, `Private model test failed: ${result.error?.message || result.stderr.slice(-1000)}`);
  const actual = JSON.parse(result.stdout);
  const keys = ['COMMUNITY_MODERATION_URL', 'ML_SERVICE_TOKEN'];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  process.env.COMMUNITY_MODERATION_URL = 'https://private.example/v1/community/moderate';
  process.env.ML_SERVICE_TOKEN = 'synthetic-community-contract-only';
  try {
    const status = await policy.readiness(async () => ({ ok: true, json: async () => actual.ready }));
    assert.equal(status.ready, true);
    assert.equal(status.runtime, 'onnx-cpu');
    assert.equal(status.clinical_validation, false);
    for (const response of actual.results) {
      const checked = await policy.moderate('Authored fixture only', async () => ({ ok: true, json: async () => response }));
      assert.equal(checked.ai, 'available');
      assert.equal(checked.full_text_processed, true);
      assert.deepEqual(Object.keys(checked.scores).sort(), ['bullying', 'medical_advice', 'self_harm', 'spam', 'support']);
    }
  } finally {
    for (const key of keys) {
      if (saved[key] === undefined) delete process.env[key]; else process.env[key] = saved[key];
    }
  }
});
