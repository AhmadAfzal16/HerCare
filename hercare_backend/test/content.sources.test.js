const test = require('node:test');
const assert = require('node:assert/strict');
const sources = require('../src/modules/content/content.sources');
const importer = require('../scripts/content-import');

const ACCOUNT = '15fd0b87-d151-4319-9be5-e1c02cac5846';
const mediaHosts = 'api.alquran.cloud,cdn.islamic.network,alquran.cloud,www.nimh.nih.gov';
const baseItem = { title_en: 'A quiet moment', title_ur: 'سکون کا لمحہ', summary_en: 'Optional time for reflection.',
  summary_ur: 'سوچنے کے لیے ایک اختیاری لمحہ۔', audience: 'both', tags: ['calm'], priority: 5 };
function quranPayload() {
  const values = ['فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا', 'ہاں ہاں مشکل کے ساتھ آسانی بھی ہے',
    'For indeed, with hardship [will be] ease.', "Fa inna ma'al usri yusra", 'فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا'];
  return { code: 200, status: 'OK', data: sources.EDITIONS.map((id, index) => ({ edition: { identifier: id },
    number: 6095, surah: { number: 94 }, numberInSurah: 5, text: values[index],
    ...(id === 'ar.alafasy' ? { audio: 'https://cdn.islamic.network/quran/audio/128/ar.alafasy/6095.mp3' } : {}) })) };
}
function response(data, options = {}) { return new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json' }, ...options }); }
function quranManifest() { return { catalog_id: 'reviewed-collection-v1', items: [{ key: 'quran-94-5', source: { type: 'quran', ayah: '94:5' }, item: { ...baseItem } }] }; }
function activityManifest() {
  return { catalog_id: 'activities-v1', items: [{ key: 'memory-match', item: { ...baseItem,
    category: 'game', format: 'activity', audience: 'mother', is_religious: false, is_music: false, activity_type: 'game', activity_id: 'memory_match' } }] };
}
async function withHosts(run) {
  const previous = process.env.CONTENT_MEDIA_ALLOWED_HOSTS;
  process.env.CONTENT_MEDIA_ALLOWED_HOSTS = mediaHosts;
  try { return await run(); } finally {
    if (previous === undefined) delete process.env.CONTENT_MEDIA_ALLOWED_HOSTS; else process.env.CONTENT_MEDIA_ALLOWED_HOSTS = previous;
  }
}

test('Quran references cannot select hosts, queries, arbitrary editions or out-of-range chapters', () => {
  assert.equal(sources.quranURL('94:5'), 'https://api.alquran.cloud/v1/ayah/94:5/editions/quran-uthmani,ur.jalandhry,en.sahih,en.transliteration,ar.alafasy');
  for (const input of ['https://evil.test', '94:5?url=evil', '094:5', '94:05', '0:1', '115:1', '1:287', '../1', 94]) assert.throws(() => sources.quranURL(input));
});

test('Quran adapter preserves exact source Arabic, named translations, transliteration and recognised CDN address', async () => {
  const payload = quranPayload();
  let request;
  const item = await sources.fetchQuranAyah('94:5', { fetchImpl: async (url, options) => { request = { url, options }; return response(payload); } });
  assert.equal(item.arabic_text, payload.data[0].text);
  assert.equal(item.body_ur, payload.data[1].text);
  assert.equal(item.body_en, payload.data[2].text);
  assert.equal(item.transliteration, payload.data[3].text);
  assert.equal(item.media_url, payload.data[4].audio);
  assert.equal(item.is_music, false);
  assert.equal(item.is_religious, true);
  assert.match(item.attribution, /Fateh Muhammad Jalandhry/);
  assert.match(item.license_name, /rights retained/);
  assert.equal(request.options.redirect, 'error');
  assert.ok(request.options.signal instanceof AbortSignal);
  assert.equal(request.options.headers.Authorization, undefined);
  assert.equal(Object.hasOwn(item, 'status'), false);
  assert.equal(Object.hasOwn(item, 'reviewed_by'), false);
});

test('source mismatch, missing editions, duplicate editions, altered audio hosts and arbitrary response URLs are rejected', async () => {
  const changes = [
    (p) => p.data.pop(), (p) => { p.data[0].edition.identifier = 'ur.jalandhry'; },
    (p) => { p.data[2].numberInSurah = 6; }, (p) => { p.data[1].surah.number = 93; },
    (p) => { p.data[2].number = 6096; }, (p) => { p.data[0].text = 'wrong language'; },
    (p) => { p.data[4].audio = 'https://evil.test/private'; },
    (p) => { p.data[0].text = 'ٱ\u0000'; }, (p) => { p.data[0].text = 'ٱ'.repeat(6001); },
  ];
  for (const change of changes) {
    const payload = quranPayload(); change(payload);
    await assert.rejects(sources.fetchQuranAyah('94:5', { fetchImpl: async () => response(payload) }), /could not be verified/);
  }
  await assert.rejects(sources.fetchQuranAyah('94:5', { fetchImpl: async () => {
    const result = response(quranPayload()); Object.defineProperty(result, 'url', { value: 'https://evil.test/' }); return result;
  } }), /could not be verified/);
  await assert.rejects(sources.fetchQuranAyah('94:5', { fetchImpl: async () => {
    const result = response(quranPayload()); Object.defineProperty(result, 'redirected', { value: true }); return result;
  } }), /could not be verified/);
});

test('source responses are bounded by byte count and declared size and require valid UTF-8 JSON', async () => {
  await assert.rejects(sources.readJSON(new Response('x'.repeat(sources.SOURCE_LIMIT + 1), { headers: { 'content-type': 'application/json' } })), /safe size/);
  await assert.rejects(sources.readJSON(response({}, { headers: { 'content-type': 'application/json', 'content-length': String(sources.SOURCE_LIMIT + 1) } })), /safe size/);
  await assert.rejects(sources.readJSON(new Response('{}', { headers: { 'content-type': 'text/html' } })), /return JSON/);
  await assert.rejects(sources.readJSON(new Response('{broken', { headers: { 'content-type': 'application/json' } })), /invalid JSON/);
  await assert.rejects(sources.readJSON(new Response(new Uint8Array([0xff]), { headers: { 'content-type': 'application/json' } })), /invalid JSON/);
});

test('remote failure details are not leaked from source fetches', async () => {
  await assert.rejects(sources.fetchQuranAyah('94:5', { fetchImpl: async () => { throw new Error('Bearer private-token internal-host'); } }),
    (error) => !error.message.includes('private-token') && !error.message.includes('internal-host'));
  await assert.rejects(sources.fetchQuranAyah('94:5', { fetchImpl: async () => response({ private: 'secret' }, { status: 503 }) }), /could not be verified/);
});

test('catalogs are bounded, reject hidden status and reviewer fields, duplicate keys and source overrides', () => {
  const invalid = [
    { catalog_id: 'valid-v1', items: [] }, { ...quranManifest(), status: 'published' },
    { catalog_id: 'valid-v1', items: Array.from({ length: 101 }, (_, i) => ({ key: `item-${i}`, item: baseItem })) },
    { catalog_id: 'valid-v1', items: [quranManifest().items[0], quranManifest().items[0]] },
  ];
  for (const value of invalid) assert.throws(() => sources.validateManifest(value));
  for (const field of ['status', 'reviewed_by', 'client_request_id', 'version']) {
    const manifest = quranManifest(); manifest.items[0].item[field] = 'published';
    assert.throws(() => sources.validateManifest(manifest));
  }
  for (const field of ['arabic_text', 'media_url', 'transliteration', 'body_ur', 'is_music']) {
    const manifest = quranManifest(); manifest.items[0].item[field] = 'overwrite';
    assert.throws(() => sources.validateManifest(manifest), /override/);
  }
  const unsupported = quranManifest(); unsupported.items[0].source.type = 'website';
  assert.throws(() => sources.validateManifest(unsupported), /unsupported/);
});

test('stable version-8 retry IDs include catalog identity, item key and normalized content, never wall-clock time', () => {
  const first = sources.stableRequestId('catalog-v1', 'one', { b: 2, a: 1 });
  assert.match(first, /^[a-f\d]{8}-[a-f\d]{4}-8[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/);
  assert.equal(first, sources.stableRequestId('catalog-v1', 'one', { a: 1, b: 2 }));
  assert.notEqual(first, sources.stableRequestId('catalog-v2', 'one', { a: 1, b: 2 }));
  assert.notEqual(first, sources.stableRequestId('catalog-v1', 'two', { a: 1, b: 2 }));
  assert.notEqual(first, sources.stableRequestId('catalog-v1', 'one', { a: 2, b: 2 }));
});

test('preparing sources uses the catalog policy and requires explicitly trusted media hosts', async () => {
  const saved = process.env.CONTENT_MEDIA_ALLOWED_HOSTS;
  delete process.env.CONTENT_MEDIA_ALLOWED_HOSTS;
  try { await assert.rejects(sources.prepareCatalog(quranManifest(), { fetchImpl: async () => response(quranPayload()) }), /host is not enabled/); }
  finally { if (saved !== undefined) process.env.CONTENT_MEDIA_ALLOWED_HOSTS = saved; }
  await withHosts(async () => {
    const [item] = await sources.prepareCatalog(quranManifest(), { fetchImpl: async () => response(quranPayload()) });
    assert.equal(item.category, 'quran'); assert.equal(item.key, 'quran-94-5');
    assert.equal(item.verse_reference, '94:5'); assert.ok(item.client_request_id);
    const duplicate = await sources.prepareCatalog(quranManifest(), { fetchImpl: async () => response(quranPayload()) });
    assert.equal(item.client_request_id, duplicate[0].client_request_id);
  });
});

test('operator manifests can refer to real M9 games without duplicated game logic or network calls', async () => {
  const [item] = await sources.prepareCatalog(activityManifest(), { fetchImpl: async () => { throw new Error('Unexpected fetch'); } });
  assert.equal(item.activity_id, 'memory_match');
  const invalid = activityManifest(); invalid.items[0].item.activity_id = 'nonexistent_game';
  await assert.rejects(sources.prepareCatalog(invalid));
});

test('CLI defaults to dry run, refuses token arguments and only accepts HTTPS or development loopback endpoints', () => {
  assert.deepEqual(importer.parseArgs(['--file', 'catalog.json']), { apply: false, file: 'catalog.json' });
  assert.equal(importer.parseArgs(['--file', 'catalog.json', '--apply']).apply, true);
  for (const args of [[], ['--file'], ['--file', 'one', '--file', 'two'], ['--token', 'secret'], ['--file', 'one', '--apply', '--apply']]) assert.throws(() => importer.parseArgs(args));
  assert.equal(importer.adminEndpoint('https://hercare.example/api/v1/'), 'https://hercare.example/api/v1/content/admin/items');
  assert.equal(importer.adminEndpoint('http://localhost:5000/api/v1', 'development'), 'http://localhost:5000/api/v1/content/admin/items');
  for (const url of ['http://hercare.example/api/v1', 'https://user:secret@hercare.example/api/v1', 'https://hercare.example/redirect',
    'https://hercare.example/api/v1?next=evil', 'https://hercare.example/api/v1#fragment']) assert.throws(() => importer.adminEndpoint(url));
  assert.throws(() => importer.adminEndpoint('http://localhost:5000/api/v1', 'production'));
});

test('CLI dry runs perform no authenticated write and display no credentials', async () => {
  const logs = [];
  const result = await importer.execute({ apply: false }, { manifest: activityManifest(), env: { CONTENT_IMPORT_TOKEN: 'private-bearer-token-123456' },
    write: (s) => logs.push(s), fetchImpl: async () => { throw new Error('Unexpected HTTP request'); } });
  assert.deepEqual(result, { applied: false, count: 1 });
  assert.match(logs.join('\n'), /no administrator API requests/);
  assert.equal(logs.join('\n').includes('private-bearer'), false);
});

test('explicit apply only creates drafts and pins requests to the administrator identity with stable retry IDs', async () => {
  const requests = [];
  const logs = [];
  const env = { CONTENT_IMPORT_TOKEN: 'private-bearer-token-123456', CONTENT_IMPORT_ACCOUNT_ID: ACCOUNT, NODE_ENV: 'production' };
  const result = await importer.execute({ apply: true, api: 'https://hercare.example/api/v1' }, { manifest: activityManifest(), env,
    write: (s) => logs.push(s), fetchImpl: async (url, options) => { requests.push({ url, options }); return response({ success: true, data: { status: 'draft' } }); } });
  assert.deepEqual(result, { applied: true, count: 1 });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, 'https://hercare.example/api/v1/content/admin/items');
  assert.equal(requests[0].options.headers['X-Content-Account-Id'], ACCOUNT);
  assert.equal(requests[0].options.headers.Authorization, `Bearer ${env.CONTENT_IMPORT_TOKEN}`);
  assert.equal(requests[0].options.redirect, 'error');
  const body = JSON.parse(requests[0].options.body);
  assert.equal(body.activity_id, 'memory_match'); assert.ok(body.client_request_id);
  assert.equal(Object.hasOwn(body, 'key'), false); assert.equal(Object.hasOwn(body, 'status'), false);
  assert.equal(logs.join('\n').includes(env.CONTENT_IMPORT_TOKEN), false);
});

test('the entire catalog is validated before any draft writes and server error text never reaches operator logs', async () => {
  const invalid = activityManifest(); invalid.items.push({ key: 'broken', item: { ...baseItem } });
  let writes = 0;
  await assert.rejects(importer.execute({ apply: true, api: 'https://hercare.example/api/v1' }, { manifest: invalid,
    fetchImpl: async () => { writes += 1; return response({}); }, write: () => {} }));
  assert.equal(writes, 0);
  await assert.rejects(importer.execute({ apply: true, api: 'https://hercare.example/api/v1' }, { manifest: activityManifest(),
    env: { CONTENT_IMPORT_TOKEN: 'private-bearer-token-123456', CONTENT_IMPORT_ACCOUNT_ID: ACCOUNT }, write: () => {},
    fetchImpl: async () => response({ error: 'Bearer private-bearer-token-123456' }, { status: 401 }) }),
  (error) => /No approval or publication/.test(error.message) && !error.message.includes('private-bearer-token'));
});
