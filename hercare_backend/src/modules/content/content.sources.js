const { createHash } = require('node:crypto');
const policy = require('./content.policy');

const SOURCE_LIMIT = 256 * 1024;
const SOURCE_TIMEOUT_MS = 8000;
const EDITIONS = Object.freeze(['quran-uthmani', 'ur.jalandhry', 'en.sahih', 'en.transliteration', 'ar.alafasy']);
const GENERATED_QURAN_KEYS = Object.freeze(['category', 'format', 'is_religious', 'is_music', 'media_url',
  'source_url', 'source_name', 'license_name', 'attribution', 'arabic_text', 'transliteration', 'verse_reference',
  'body_en', 'body_ur', 'activity_id', 'activity_type']);

function fail(message) { throw new Error(message); }
function plainObject(value) { return value && typeof value === 'object' && !Array.isArray(value); }
function exactKeys(value, allowed) {
  if (!plainObject(value) || Object.keys(value).some((key) => !allowed.includes(key))) fail('Check the catalog manifest fields.');
}
function identifier(value) {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,79}$/.test(value)) fail('Use a short, stable catalog and item identifier.');
  return value;
}
function ayahReference(value) {
  if (typeof value !== 'string' || !/^[1-9]\d{0,2}:[1-9]\d{0,2}$/.test(value)) fail('Use a Quran reference such as 94:5.');
  const [surah, ayah] = value.split(':').map(Number);
  if (surah > 114 || ayah > 286) fail('The Quran reference is outside the supported range.');
  return { reference: value, surah, ayah };
}
function quranURL(reference) {
  return `https://api.alquran.cloud/v1/ayah/${ayahReference(reference).reference}/editions/${EDITIONS.join(',')}`;
}

// This reader bounds decoded response bytes too, not just a possibly missing Content-Length.
async function readJSON(response, limit = SOURCE_LIMIT) {
  const length = response.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > limit)) fail('The source response exceeded the safe size limit.');
  if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') || '')) fail('The source did not return JSON.');
  if (!response.body || typeof response.body.getReader !== 'function') fail('The source response is incomplete.');
  const reader = response.body.getReader();
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        fail('The source response exceeded the safe size limit.');
      }
      chunks.push(Buffer.from(value));
    }
  } finally { reader.releaseLock(); }
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { fail('The source returned invalid JSON.'); }
}

function sourceText(value) {
  if (typeof value !== 'string' || !value.trim() || value.length > 6000
      || [...value].some((character) => {
        const code = character.codePointAt(0);
        return (code < 32 && ![9, 10, 13].includes(code)) || code === 127;
      })) fail('The Quran source text is incomplete.');
  return value; // Deliberately do not rewrite Arabic, normalize diacritics or machine-translate.
}
function parseQuran(payload, reference) {
  const expected = ayahReference(reference);
  if (!plainObject(payload) || payload.code !== 200 || !Array.isArray(payload.data) || payload.data.length !== EDITIONS.length) {
    fail('The Quran source did not return all required editions.');
  }
  const editions = new Map();
  let globalNumber;
  for (const row of payload.data) {
    if (!plainObject(row) || !plainObject(row.edition) || !EDITIONS.includes(row.edition.identifier)
        || editions.has(row.edition.identifier) || row.surah?.number !== expected.surah || row.numberInSurah !== expected.ayah
        || !Number.isSafeInteger(row.number) || row.number < 1 || row.number > 6236
        || (globalNumber !== undefined && row.number !== globalNumber)) fail('The Quran source editions did not match the requested verse.');
    globalNumber = row.number;
    sourceText(row.text);
    editions.set(row.edition.identifier, row);
  }
  const arabic = editions.get('quran-uthmani').text;
  if (!/\p{Script=Arabic}/u.test(arabic)) fail('The Quran source Arabic text is missing.');
  const audio = `https://cdn.islamic.network/quran/audio/128/ar.alafasy/${globalNumber}.mp3`;
  if (editions.get('ar.alafasy').audio !== audio) fail('The Quran source audio address was not recognised.');
  return {
    category: 'quran', format: 'audio', is_religious: true, is_music: false,
    arabic_text: arabic, body_en: editions.get('en.sahih').text, body_ur: editions.get('ur.jalandhry').text,
    transliteration: editions.get('en.transliteration').text, verse_reference: expected.reference,
    media_url: audio, source_url: quranURL(reference), source_name: 'Al Quran Cloud / Islamic Network',
    license_name: 'Educational/non-commercial streaming; reciter and translator rights retained. See Al Quran Cloud terms.',
    attribution: 'Arabic: Uthmani text via Al Quran Cloud. Urdu: Fateh Muhammad Jalandhry. English: Saheeh International. '
      + 'Transliteration: Al Quran Cloud English Transliteration. Recitation: Mishary Rashid Alafasy. '
      + 'Source and usage terms: https://alquran.cloud/terms-and-conditions. Faith support is optional, not a replacement for health care.',
  };
}

async function fetchQuranAyah(reference, { fetchImpl = globalThis.fetch } = {}) {
  const address = quranURL(reference); // No caller-controlled host, redirect target, edition or query.
  let response;
  try {
    response = await fetchImpl(address, { method: 'GET', redirect: 'error',
      signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS), headers: { Accept: 'application/json' } });
    if (!response.ok || response.redirected || (response.url && response.url !== address)) fail('Quran source unavailable.');
    return parseQuran(await readJSON(response), reference);
  } catch {
    // Do not expose response bodies, URLs supplied by a remote service, or network exception text.
    fail('The Quran source could not be verified. No imported item was approved or published.');
  } finally {
    if (response?.body && !response.body.locked) await response.body.cancel().catch(() => {});
  }
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (plainObject(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}
function stableRequestId(catalogId, key, item) {
  identifier(catalogId); identifier(key);
  const digest = createHash('sha256').update(`hercare-content-import-v1\0${catalogId}\0${key}\0${canonical(item)}`).digest();
  // RFC 9562 version 8 UUID: a deterministic application-defined SHA-256 identifier.
  digest[6] = (digest[6] & 0x0f) | 0x80;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = digest.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
function validateManifest(manifest) {
  exactKeys(manifest, ['catalog_id', 'items']);
  identifier(manifest.catalog_id);
  if (!Array.isArray(manifest.items) || !manifest.items.length || manifest.items.length > 100) fail('A catalog must contain between 1 and 100 items.');
  const seen = new Set();
  for (const entry of manifest.items) {
    exactKeys(entry, ['key', 'source', 'item']);
    identifier(entry.key);
    if (seen.has(entry.key)) fail('Catalog item identifiers must be unique.');
    seen.add(entry.key);
    if (!plainObject(entry.item)) fail('Each catalog entry needs an item object.');
    if (entry.source !== undefined) {
      exactKeys(entry.source, ['type', 'ayah']);
      if (entry.source.type !== 'quran') fail('The catalog contains an unsupported source adapter.');
      ayahReference(entry.source.ayah);
      if (Object.keys(entry.item).some((key) => GENERATED_QURAN_KEYS.includes(key))) fail('Do not override verified Quran source fields.');
    }
    if (Object.keys(entry.item).some((key) => !policy.CONTENT_KEYS.includes(key))) fail('Catalog items may not set IDs, status, approvals or publication fields.');
  }
  return manifest;
}
async function prepareCatalog(manifest, options = {}) {
  validateManifest(manifest);
  const prepared = [];
  // Resolve and validate the entire batch before any administrator request can write a draft.
  for (const entry of manifest.items) {
    const source = entry.source ? await fetchQuranAyah(entry.source.ayah, options) : {};
    const item = policy.item({ ...entry.item, ...source });
    prepared.push({ key: entry.key, ...item, client_request_id: stableRequestId(manifest.catalog_id, entry.key, item) });
  }
  return prepared;
}

module.exports = { SOURCE_LIMIT, SOURCE_TIMEOUT_MS, EDITIONS, quranURL, parseQuran, fetchQuranAyah,
  readJSON, stableRequestId, validateManifest, prepareCatalog };
