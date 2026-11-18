const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { getCatalog } = require('../src/modules/crisis/crisis.contacts');

test('M10 online and offline contact catalogs match, with scoped coverage and source limitations', () => {
  const mobile = JSON.parse(fs.readFileSync(path.join(__dirname, '../../hercare_flutter/assets/crisis_contacts.json'), 'utf8'));
  const catalog = getCatalog();
  assert.deepEqual(catalog, mobile);
  assert.equal(catalog.regions.find((region) => region.id === 'unspecified').emergency_number, null);
  assert.equal(catalog.regions.find((region) => region.id === 'other').emergency_number, null);
  assert.ok(catalog.contacts.every((contact) => /^\+\d{10,15}$/.test(contact.phone) && contact.source_url.startsWith('https://')));
  assert.equal(catalog.contacts.find((contact) => contact.id === 'umang').verification_status, 'limited_provider_listing');
  catalog.contacts[0].phone = 'unsafe-mutation';
  assert.notEqual(getCatalog().contacts[0].phone, 'unsafe-mutation');
});
