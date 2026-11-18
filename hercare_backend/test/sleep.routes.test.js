const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('M8 mother-only endpoints, old-account guard, no-store and private validation logs', async () => {
  process.env.NODE_ENV = 'test';
  process.env.JWT_ACCESS_SECRET ||= randomUUID();
  process.env.JWT_REFRESH_SECRET ||= randomUUID();
  const express = require('express');
  const service = require('../src/modules/sleep/sleep.service');
  const { dashboardQuery, validateSleep } = require('../src/modules/sleep/sleep.logic');
  const { errorHandler } = require('../src/middleware/error_handler');
  const { signAccessToken } = require('../src/utils/jwt');
  const logger = require('../src/utils/logger');
  const previous = { dashboard: service.dashboard, save: service.save, error: logger.error };
  const logs = [];
  let reads = 0;
  let writes = 0;
  let server;
  try {
    logger.error = (...args) => logs.push(args);
    service.dashboard = async (_id, query) => { dashboardQuery(query); reads++; return { records: [] }; };
    service.save = async (_id, body) => { validateSleep(body); writes++; return { saved: true }; };
    const app = express();
    app.use(express.json());
    app.use('/api/v1/sleep', require('../src/modules/sleep/sleep.routes'));
    app.use(errorHandler);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    const url = 'http://127.0.0.1:' + server.address().port + '/api/v1/sleep';
    const id = randomUUID();
    const headers = (role = 'mother', account = id) => ({ 'Content-Type': 'application/json',
      Authorization: 'Bearer ' + signAccessToken({ userId: id, role }), 'X-Sleep-Account-Id': account });
    for (const [head, status] of [[undefined, 401], [headers('guardian'), 403], [headers('mother', randomUUID()), 409]]) {
      const response = await fetch(url, { headers: head });
      assert.equal(response.status, status);
      assert.equal(response.headers.get('cache-control'), 'no-store');
    }
    assert.equal(reads, 0);
    const response = await fetch(url, { headers: headers() });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(url + '?unexpected=true', { headers: headers() })).status, 422);
    const wake = new Date(Date.now() - 3600000);
    const data = { sleep_date: wake.toISOString().slice(0, 10), bedtime: new Date(wake.getTime() - 8 * 3600000).toISOString(),
      wake_time: wake.toISOString(), awake_minutes: 0, timezone_offset_minutes: 0 };
    assert.equal((await fetch(url, { method: 'PUT', headers: headers(), body: JSON.stringify(data) })).status, 200);
    assert.equal((await fetch(url, { method: 'PUT', headers: headers('mother', randomUUID()), body: JSON.stringify(data) })).status, 409);
    assert.equal(writes, 1);
    assert.equal((await fetch(url, { method: 'PUT', headers: headers(),
      body: JSON.stringify({ ...data, quality: 'PRIVATE_SLEEP_VALUE', unexpected: 'PRIVATE_EXTRA' }) })).status, 422);
    assert.equal(JSON.stringify(logs).includes('PRIVATE_SLEEP_VALUE'), false);
    assert.equal(JSON.stringify(logs).includes('PRIVATE_EXTRA'), false);
    assert.equal(JSON.stringify(logs).includes(data.bedtime), false);
  } finally {
    Object.assign(service, { dashboard: previous.dashboard, save: previous.save });
    logger.error = previous.error;
    if (server) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
  }
});
