// Explicit opt-in. Every synthetic row and catalog revision is rolled back.
const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const { payload } = require('./helpers/content.fixture');

test('M11 real PostgreSQL catalog/consent/review/retry/safety lifecycle (rollback only)', {
  skip: process.env.RUN_CONTENT_DB_TESTS !== '1',
}, async () => {
  const pool = database.pool;
  const client = await pool.connect();
  const original = { query: database.query, transaction: database.withTransaction };
  database.query = client.query.bind(client);
  database.withTransaction = async (fn) => {
    const savepoint = `m11_${randomUUID().replaceAll('-', '')}`;
    await client.query(`SAVEPOINT ${savepoint}`);
    try { const result = await fn(client); await client.query(`RELEASE SAVEPOINT ${savepoint}`); return result; }
    catch (error) { await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`); await client.query(`RELEASE SAVEPOINT ${savepoint}`); throw error; }
  };
  await client.query('BEGIN');
  try {
    const exists = await client.query("SELECT to_regclass('content_items') AS table_name");
    if (!exists.rows[0].table_name) {
      await client.query(readFileSync(join(__dirname, '../migrations/021_content_recommendations.sql'), 'utf8'));
    }
    const admin = randomUUID(); const mother = randomUUID(); const guardian = randomUUID();
    for (const [id, role] of [[admin, 'admin'], [mother, 'mother'], [guardian, 'guardian']]) {
      await client.query(`INSERT INTO users(id,phone,password_hash,role,onboarding_complete) VALUES($1,$2,'synthetic-no-login',$3,TRUE)`,
        [id, `m11${id.replaceAll('-', '').slice(0, 12)}`, role]);
    }
    await client.query('INSERT INTO onboarding_data(user_id,consent_tier1,consent_tier2) VALUES($1,TRUE,FALSE)', [mother]);
    const body = { ...payload({ tags: ['low_mood', 'education'], review_after: new Date(Date.now() + 90 * 86400000).toISOString() }), client_request_id: randomUUID() };
    const created = await service.createItem(admin, body);
    assert.equal(created.status, 'draft');
    assert.deepEqual(await service.createItem(admin, body), created);
    await assert.rejects(service.createItem(admin, { ...body, title_en: 'Changed request' }), { statusCode: 409 });
    assert.equal((await service.feed(mother)).items.some((row) => row.id === created.id), false);
    await assert.rejects(service.publication(admin, created.id, { version: 1, published: true }), { statusCode: 409 });
    const reviewed = await service.reviewItem(admin, created.id, { version: created.version, decision: 'approved',
      review_note: 'Synthetic integration check; not a real clinical review.', reviewer_qualification: 'Synthetic test reviewer' });
    const published = await service.publication(admin, created.id, { version: reviewed.version, published: true });
    assert.equal(published.status, 'published');
    let feed = await service.feed(mother);
    assert.ok(feed.items.some((row) => row.id === created.id));
    const beforeRevision = BigInt(feed.catalog_revision);
    const save = { client_request_id: randomUUID(), saved: true };
    assert.deepEqual(await service.interaction(mother, created.id, save, 'saved'), { content_id: created.id, saved: true });
    assert.deepEqual(await service.interaction(mother, created.id, save, 'saved'), { content_id: created.id, saved: true });
    await assert.rejects(service.interaction(mother, created.id, { ...save, saved: false }, 'saved'), { statusCode: 409 });
    assert.ok((await service.feed(mother, { limit: '100' }, true)).items.some((row) => row.id === created.id));
    await service.interaction(mother, created.id, { client_request_id: randomUUID(), value: 'helpful' }, 'feedback');
    assert.equal((await service.detail(mother, created.id)).feedback, 'helpful');
    const pref = await service.updatePreferences(mother, { version: 0, religious_enabled: false, music_enabled: false, disabled_categories: ['psychoeducation'] });
    assert.equal(pref.version, 1);
    assert.equal((await service.feed(mother)).items.some((row) => row.id === created.id), false);
    await assert.rejects(service.detail(mother, created.id), { statusCode: 404 });
    await assert.rejects(service.updatePreferences(mother, { version: 0, religious_enabled: true, music_enabled: true, disabled_categories: [] }), { statusCode: 409 });
    const gp = (await service.feed(guardian)).preferences;
    assert.deepEqual(gp.disabled_categories, []);
    await service.updatePreferences(mother, { ...pref, disabled_categories: [] });
    await client.query(`INSERT INTO crisis_events(mother_id,source_type,source_id,severity,status) VALUES($1,'manual',$2,'severe','open')`, [mother, randomUUID()]);
    feed = await service.feed(mother);
    assert.equal(feed.safety_priority, true); assert.equal(feed.items.length, 0);
    await assert.rejects(service.detail(mother, created.id), { statusCode: 409 });
    assert.deepEqual(await service.interaction(mother, created.id, { client_request_id: randomUUID(), saved: false }, 'saved'), { content_id: created.id, saved: false });
    await client.query("UPDATE crisis_events SET status='resolved' WHERE mother_id=$1", [mother]);
    await service.publication(admin, created.id, { version: published.version, published: false });
    feed = await service.feed(mother);
    assert.equal(feed.items.some((row) => row.id === created.id), false);
    assert.ok(BigInt(feed.catalog_revision) > beforeRevision);
    await client.query('UPDATE onboarding_data SET consent_tier1=FALSE WHERE user_id=$1', [mother]);
    await assert.rejects(service.feed(mother), { statusCode: 403 });
    await assert.rejects(service.createItem(guardian, { ...body, client_request_id: randomUUID() }), { statusCode: 403 });
  } finally {
    await client.query('ROLLBACK'); client.release(); await pool.end();
    database.query = original.query; database.withTransaction = original.transaction;
  }
});
