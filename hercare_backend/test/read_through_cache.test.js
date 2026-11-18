const test = require('node:test');
const assert = require('node:assert/strict');
const { createReadThroughCache } = require('../src/utils/read_through_cache');

test('cache coalesces concurrent reads and refreshes after TTL', async () => {
  let time = 100;
  let reads = 0;
  const cache = createReadThroughCache({ maxEntries: 2, now: () => time });
  const load = async () => { reads += 1; return { value: reads }; };
  const first = await Promise.all([
    cache.get('epds', 30, load), cache.get('epds', 30, load),
  ]);
  assert.equal(reads, 1);
  assert.deepEqual(first, [{ value: 1 }, { value: 1 }]);
  time = 129;
  assert.deepEqual(await cache.get('epds', 30, load), { value: 1 });
  time = 130;
  assert.deepEqual(await cache.get('epds', 30, load), { value: 2 });
  assert.equal(reads, 2);
});

test('cache is bounded and does not retain absent or failed loads', async () => {
  const cache = createReadThroughCache({ maxEntries: 1 });
  let reads = 0;
  const load = async () => { reads += 1; return reads; };
  await cache.get('epds', 1000, load);
  await cache.get('phq9', 1000, load);
  assert.equal(await cache.get('epds', 1000, load), 3);
  assert.equal(await cache.get('missing', 1000, async () => null), null);
  assert.equal(await cache.get('missing', 1000, async () => 4), 4);
  await assert.rejects(cache.get('error', 1000, async () => {
    throw new Error('database unavailable');
  }), /database unavailable/);
  assert.equal(await cache.get('error', 1000, async () => 5), 5);
});
