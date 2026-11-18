const { createHash } = require('node:crypto');
const { AppError } = require('../../middleware/error_handler');

// Only operator-reviewed institution-owned pages belong here. Adding another
// host requires a source review and a catalog release, not an HTTP query.
const APPROVED_DOMAINS = Object.freeze([
  'pimh.punjab.gov.pk', 'pims.gov.pk', 'www.pims.gov.pk', 'www.jpmc.edu.pk',
  'hospitals.aku.edu', 'www.aku.edu', 'kth.edu.pk', 'www.mayohospital.gop.pk',
  'www.lrh.edu.pk', 'bipbs.gob.pk',
]);
const SOURCE_HOSTS = new Set(APPROVED_DOMAINS);
const REGIONS = new Set(['punjab', 'sindh', 'islamabad', 'khyber_pakhtunkhwa',
  'balochistan', 'gilgit_baltistan', 'azad_kashmir']);
const TOP_FIELDS = ['version', 'checked_on', 'review_due_on', 'notice', 'notice_ur', 'facilities'];
const FACILITY_FIELDS = ['id', 'name', 'name_ur', 'region', 'city', 'city_ur', 'address', 'address_ur',
  'phone', 'service', 'service_ur', 'source_urls', 'checked_on', 'review_due_on',
  'verification_status', 'clinical_approval', 'availability', 'latitude', 'longitude', 'coordinates_source_url', 'coordinate_kind'];
const DAY_MS = 86400000;
let validatedCatalog;
let cachedResponse;

function fail(field) { throw new Error(`Care directory catalog is invalid: ${field}.`); }
function object(value, fields, field) {
  if (!value || Array.isArray(value) || typeof value !== 'object' ||
      Object.keys(value).length !== fields.length || fields.some((key) => !Object.hasOwn(value, key)) ||
      Object.keys(value).some((key) => !fields.includes(key))) fail(field);
}
function text(value, max, field) {
  if (typeof value !== 'string' || !value.trim() || value !== value.trim() ||
      value.length > max || [...value].some((character) => character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127)) fail(field);
}
function date(value, field) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(field);
  const result = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(result.getTime()) || result.toISOString().slice(0, 10) !== value) fail(field);
  return result.getTime();
}
function reviewDates(value, prefix) {
  const checked = date(value.checked_on, `${prefix}.checked_on`);
  const due = date(value.review_due_on, `${prefix}.review_due_on`);
  if (due < checked || due - checked > 180 * DAY_MS) fail(`${prefix}.review_interval`);
}
function source(value) {
  text(value, 700, 'source_url');
  let url;
  try { url = new URL(value); } catch { fail('source_url'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port ||
      !SOURCE_HOSTS.has(url.hostname.toLowerCase())) fail('institutional_source_host');
  if (url.search) {
    const keys = [...url.searchParams.keys()];
    if (url.hostname !== 'bipbs.gob.pk' || keys.length !== 1 || keys[0] !== 'page_id' ||
        !/^[1-9]\d{0,9}$/.test(url.searchParams.get('page_id'))) fail('institutional_source_query');
  }
}
function coordinates(item) {
  if (item.latitude === null && item.longitude === null && item.coordinates_source_url === null && item.coordinate_kind === null) return;
  if (typeof item.latitude !== 'number' || !Number.isFinite(item.latitude) || item.latitude < -90 || item.latitude > 90 ||
      typeof item.longitude !== 'number' || !Number.isFinite(item.longitude) || item.longitude < -180 || item.longitude > 180) fail('coordinates');
  text(item.coordinates_source_url, 700, 'coordinates_source_url');
  let url;
  try { url = new URL(item.coordinates_source_url); } catch { fail('coordinates_source_url'); }
  const institutional = SOURCE_HOSTS.has(url.hostname.toLowerCase());
  const linkedMap = (url.hostname === 'www.google.com' && url.pathname.startsWith('/maps')) ||
    url.hostname === 'maps.google.com' || url.hostname === 'maps.app.goo.gl' ||
    (url.hostname === 'goo.gl' && url.pathname.startsWith('/maps/'));
  if (url.protocol !== 'https:' || url.username || url.password || url.port || !(institutional || linkedMap)) fail('coordinates_source_host');
  if (!['official_geo_point', 'official_map_view_center'].includes(item.coordinate_kind) ||
      (item.coordinate_kind === 'official_geo_point' && !institutional)) fail('coordinate_kind');
  if (institutional) source(item.coordinates_source_url);
}

function validateCatalog(raw) {
  if (Buffer.byteLength(JSON.stringify(raw) || '') > 128 * 1024) fail('size');
  object(raw, TOP_FIELDS, 'fields');
  if (typeof raw.version !== 'string' || !/^[a-z0-9-]{8,80}$/.test(raw.version)) fail('version');
  text(raw.notice, 1500, 'notice');
  text(raw.notice_ur, 1500, 'notice_ur');
  reviewDates(raw, 'catalog');
  if (!Array.isArray(raw.facilities) || raw.facilities.length < 1 || raw.facilities.length > 30) fail('facility_count');
  const ids = new Set();
  for (const item of raw.facilities) {
    object(item, FACILITY_FIELDS, 'facility_fields');
    if (typeof item.id !== 'string' || !/^[a-z0-9_]{3,60}$/.test(item.id) || ids.has(item.id)) fail('facility_id');
    ids.add(item.id);
    for (const key of ['name', 'name_ur', 'city', 'city_ur']) text(item[key], 160, key);
    for (const key of ['address', 'address_ur', 'service', 'service_ur']) text(item[key], 700, key);
    if (!REGIONS.has(item.region)) fail('region');
    if (typeof item.phone !== 'string' || !/^\+[1-9]\d{7,14}$/.test(item.phone)) fail('phone');
    if (!Array.isArray(item.source_urls) || item.source_urls.length < 1 || item.source_urls.length > 3 ||
        new Set(item.source_urls).size !== item.source_urls.length) fail('source_urls');
    item.source_urls.forEach(source);
    coordinates(item);
    reviewDates(item, 'facility');
    if (item.checked_on > raw.checked_on) fail('facility_checked_after_catalog');
    if (item.verification_status !== 'official_source_checked' || item.clinical_approval !== false ||
        item.availability !== 'unknown') fail('unverified_claim');
  }
  return structuredClone(raw);
}

function currentDay(now) {
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) fail('clock');
  return now.toISOString().slice(0, 10);
}
function snapshot(raw, now = new Date()) {
  const catalog = validateCatalog(raw);
  const day = currentDay(now);
  // Future-dated checks must not be described as verified, even if an operator
  // or a misconfigured server clock caused the date mismatch.
  const status = (entry) => entry.checked_on > day ? 'date_unconfirmed' :
    entry.review_due_on < day ? 'review_due' : 'current';
  catalog.facilities = catalog.facilities.map((item) => {
    const reviewStatus = status(item);
    return { ...item, review_status: reviewStatus, stale: reviewStatus !== 'current' };
  });
  catalog.review_status = status(catalog);
  if (catalog.review_status === 'current' && catalog.facilities.some((item) => item.stale)) {
    catalog.review_status = catalog.facilities.some((item) => item.review_status === 'date_unconfirmed') ? 'date_unconfirmed' : 'review_due';
  }
  catalog.stale = catalog.review_status !== 'current';
  catalog.approved_domains = [...APPROVED_DOMAINS];
  return catalog;
}
function load() {
  if (!validatedCatalog) validatedCatalog = validateCatalog(require('./facilities.json'));
  return validatedCatalog;
}
function getCatalog(now = new Date()) { return snapshot(load(), now); }

// Hash the exact success-envelope bytes. The ETag changes when a review becomes
// overdue; caching cannot turn a stale entry back into a verified current one.
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}
function getResponse(now = new Date()) {
  const day = currentDay(now);
  if (!cachedResponse || cachedResponse.day !== day) {
    const body = JSON.stringify(canonical({ success: true, data: getCatalog(now) }));
    cachedResponse = { day, body, etag: `"${createHash('sha256').update(body).digest('hex')}"` };
  }
  return { body: cachedResponse.body, etag: cachedResponse.etag };
}
function validateQuery(query, requestUrl = '') {
  // Inspect the raw presence too: Express deliberately drops prototype-like
  // query keys, but they still must not become accepted location input.
  if (!query || Object.keys(query).length !== 0 || requestUrl.includes('?')) {
    throw new AppError('The public directory does not accept location, account or search parameters. Filter it on your device.', 422);
  }
}

module.exports = { APPROVED_DOMAINS, validateCatalog, snapshot, getCatalog, getResponse, validateQuery };

// Release gate: no network calls, database access or private data. Existing
// stale listings stay visible with warnings at runtime; a new catalog release
// must pass this stricter operator check first.
if (require.main === module) {
  try {
    if (process.argv.slice(2).join(' ') !== '--check') throw new Error('Usage: node src/modules/crisis/crisis.directory.js --check');
    const catalog = getCatalog();
    const pending = catalog.facilities.filter((item) => item.stale).length;
    console.log(`${catalog.version}: ${catalog.facilities.length} institutional listings; review due ${catalog.review_due_on}.`);
    if (catalog.stale || pending) throw new Error(`Catalog review required: ${pending} listings are not current.`);
    console.log('Directory release checks passed. Source-page checks do not confirm live service availability or clinical approval.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
