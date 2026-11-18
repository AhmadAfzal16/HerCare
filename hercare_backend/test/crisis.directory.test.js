const test = require('node:test');
const assert = require('node:assert/strict');
const directory = require('../src/modules/crisis/crisis.directory');

// Synthetic schema fixtures only, not provider listings or clinical records.
function fixture() {
  return { version: 'test-directory-v1', checked_on: '2026-10-12', review_due_on: '2027-01-10',
    notice: 'Source pages were checked. Availability is unknown.', notice_ur: 'دستیابی کی تصدیق نہیں۔',
    facilities: [{ id: 'fixture_facility', name: 'Synthetic institution', name_ur: 'فرضی ادارہ', region: 'sindh',
      city: 'Synthetic city', city_ur: 'فرضی شہر', address: 'Synthetic public address', address_ur: 'فرضی پتہ',
      phone: '+922112345678', service: 'Synthetic public department', service_ur: 'فرضی شعبہ',
      source_urls: ['https://hospitals.aku.edu/example'], checked_on: '2026-10-12', review_due_on: '2027-01-10',
      verification_status: 'official_source_checked', clinical_approval: false, availability: 'unknown',
      latitude: null, longitude: null, coordinates_source_url: null, coordinate_kind: null }] };
}

test('M10 directory has bounded immutable-copy public fields and no clinical/live-service claims', () => {
  assert.deepEqual(require('../src/modules/crisis/facilities.json'),
    require('../../hercare_flutter/assets/care_facilities.json'), 'Online and offline care catalogs must match');
  const original = fixture();
  const checked = directory.validateCatalog(original);
  checked.facilities[0].name = 'Changed request';
  assert.equal(original.facilities[0].name, 'Synthetic institution');
  assert.equal(Object.isFrozen(directory.APPROVED_DOMAINS), true);
  assert.throws(() => directory.APPROVED_DOMAINS.push('unreviewed.example'));
  const invalid = [
    (x) => { x.private_mother_id = 'sensitive'; },
    (x) => { x.facilities[0].journal = 'sensitive'; },
    (x) => { x.facilities[0].clinical_approval = true; },
    (x) => { x.facilities[0].availability = 'open_now'; },
    (x) => { x.facilities[0].verification_status = 'best_doctor'; },
    (x) => { x.facilities[0].phone = 'tel:+922112345678'; },
    (x) => { x.facilities[0].region = 'anywhere'; },
    (x) => { x.facilities[0].address += '\nHidden'; },
    (x) => { x.facilities.push(structuredClone(x.facilities[0])); },
    (x) => { x.facilities = Array.from({ length: 31 }, (_, i) => ({ ...x.facilities[0], id: `fixture_${i}` })); },
    (x) => { x.facilities = []; },
    (x) => { x.facilities[0].name = 'x'.repeat(161); },
  ];
  for (const mutate of invalid) {
    const value = fixture(); mutate(value);
    assert.throws(() => directory.validateCatalog(value), /catalog is invalid/);
  }
});

test('M10 source URLs require explicit reviewed HTTPS institutions, never user-supplied providers', () => {
  for (const url of ['http://hospitals.aku.edu/example', 'https://hospitals.aku.edu:8443/example',
    'https://password@hospitals.aku.edu/example', 'https://hospitals.aku.edu.attacker.example/',
    'https://localhost/example', 'https://127.0.0.1/', 'https://maps.google.com/', 'file:///private',
    'https://hospitals.aku.edu/example?search=private', 'https://bipbs.gob.pk/?page_id=-1',
    'https://bipbs.gob.pk/?page_id=1906&private=journal', 'https://bipbs.gob.pk/?page_id=1906&page_id=1907']) {
    const value = fixture(); value.facilities[0].source_urls = [url];
    assert.throws(() => directory.validateCatalog(value), /catalog is invalid/);
  }
  const value = fixture(); value.facilities[0].source_urls = Array(4).fill('https://hospitals.aku.edu/example');
  assert.throws(() => directory.validateCatalog(value), /source_urls/);
  const bipbs = fixture(); bipbs.facilities[0].source_urls = ['https://bipbs.gob.pk/?page_id=1906'];
  assert.equal(directory.validateCatalog(bipbs).facilities[0].source_urls[0], 'https://bipbs.gob.pk/?page_id=1906');
});

test('M10 source-review age never implies current availability; expired/future checks visibly degrade', () => {
  const raw = fixture();
  const current = directory.snapshot(raw, new Date('2026-10-12T18:00:00Z'));
  assert.equal(current.review_status, 'current');
  assert.equal(current.stale, false);
  assert.equal(current.facilities[0].availability, 'unknown');
  assert.equal(current.facilities[0].clinical_approval, false);
  assert.deepEqual(current.approved_domains, [...directory.APPROVED_DOMAINS]);
  const dueDay = directory.snapshot(raw, new Date('2027-01-10T23:59:59Z'));
  assert.equal(dueDay.stale, false);
  const stale = directory.snapshot(raw, new Date('2027-01-11T00:00:00Z'));
  assert.equal(stale.review_status, 'review_due');
  assert.equal(stale.facilities[0].review_status, 'review_due');
  assert.equal(stale.facilities.length, 1, 'Stale public help must not disappear silently');
  assert.equal(stale.facilities[0].stale, true);
  const individuallyStale = fixture();
  individuallyStale.facilities[0].review_due_on = '2026-10-13';
  const partialReview = directory.snapshot(individuallyStale, new Date('2026-10-14T00:00:00Z'));
  assert.equal(partialReview.review_status, 'review_due', 'Catalog warns when even one facility needs review');
  const future = directory.snapshot(raw, new Date('2026-10-11T18:00:00Z'));
  assert.equal(future.review_status, 'date_unconfirmed');
  assert.equal(future.facilities[0].stale, true);
  for (const [checked, due] of [['2026-02-30', '2026-04-01'], ['2026-10-12', '2026-10-11'],
    ['2026-10-12', '2027-10-12'], ['2026-10-12T00:00:00Z', '2027-01-10']]) {
    const value = fixture(); value.checked_on = checked; value.review_due_on = due;
    assert.throws(() => directory.validateCatalog(value), /catalog is invalid/);
  }
  const value = fixture(); value.facilities[0].checked_on = '2026-10-13';
  assert.throws(() => directory.validateCatalog(value), /facility_checked_after_catalog/);
});

test('M10 public facility coordinates are paired, bounded and separately provenance-reviewed', () => {
  const raw = fixture();
  raw.facilities[0].latitude = 24.9;
  raw.facilities[0].longitude = 67.1;
  raw.facilities[0].coordinates_source_url = 'https://www.google.com/maps/place/Synthetic/@24.9,67.1,15z';
  raw.facilities[0].coordinate_kind = 'official_map_view_center';
  assert.equal(directory.validateCatalog(raw).facilities[0].latitude, 24.9);
  for (const patch of [{ longitude: null }, { latitude: 91 }, { longitude: -181 }, { latitude: '24.9' },
    { longitude: NaN }, { coordinates_source_url: null }, { coordinates_source_url: 'https://www.google.com/search?q=private' },
    { coordinates_source_url: 'https://unreviewed.example/maps' }, { coordinates_source_url: 'http://maps.google.com/' },
    { coordinate_kind: 'surveyed_entrance' }, { coordinate_kind: 'official_geo_point' }]) {
    const value = structuredClone(raw); Object.assign(value.facilities[0], patch);
    assert.throws(() => directory.validateCatalog(value), /catalog is invalid/);
  }
  const explicit = structuredClone(raw);
  explicit.facilities[0].coordinates_source_url = 'https://hospitals.aku.edu/example';
  explicit.facilities[0].coordinate_kind = 'official_geo_point';
  assert.equal(directory.validateCatalog(explicit).facilities[0].coordinate_kind, 'official_geo_point');
});

test('M10 server accepts no location/account/search query and its published response is ETag-stable', () => {
  directory.validateQuery({});
  assert.throws(() => directory.validateQuery({}, '/api/v1/crisis/facilities?__proto__[latitude]=private'), { statusCode: 422 });
  for (const query of [{ city: 'Lahore' }, { latitude: '31.5', longitude: '74.3' }, { mother_id: 'private' },
    { search: 'journal' }, { limit: '100000' }, { '__proto__': null, nested: { location: 'private' } }]) {
    assert.throws(() => directory.validateQuery(query), { statusCode: 422 });
  }
  const first = directory.getResponse(new Date('2026-10-12T12:00:00Z'));
  const second = directory.getResponse(new Date('2026-10-12T23:59:59Z'));
  assert.equal(first.etag, second.etag);
  assert.equal(first.body, second.body);
  assert.match(first.etag, /^"[a-f0-9]{64}"$/);
  const data = JSON.parse(first.body).data;
  assert.ok(data.facilities.length >= 1 && data.facilities.length <= 30);
  assert.ok(data.facilities.every((item) => item.clinical_approval === false && item.availability === 'unknown'));
  const afterReview = directory.getResponse(new Date(new Date(`${data.review_due_on}T00:00:00Z`).valueOf() + 86400000));
  assert.notEqual(afterReview.etag, first.etag);
  assert.equal(JSON.parse(afterReview.body).data.stale, true);
});
