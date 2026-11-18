const test = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const database = require('../src/config/database');
const policy = require('../src/modules/community/community.policy');
const { encryptJournal } = require('../src/modules/mood/journal_crypto');

test('M12 exact retries, publication fail-closed, current authorization and bounded admin views', async (t) => {
  const original = { query: database.query, transaction: database.withTransaction, moderate: policy.moderate,
    readiness: policy.readiness, required: process.env.COMMUNITY_AI_REQUIRED };
  const mother = randomUUID(); const admin = randomUUID(); const guardian = randomUUID();
  const motherMember = randomUUID(); const adminMember = randomUUID();
  const request = { title: 'Recovery today', body: 'I felt supported today.', topic: 'recovery', client_request_id: randomUUID() };
  const metadata = { language: 'en', flags: [], safety_support: false, ai: 'available', model_version: 'test-model',
    policy_version: 'test-policy', runtime: 'onnx-cpu', clinical_validation: false, full_text_processed: true,
    scores: { self_harm: 0, bullying: 0, spam: 0, medical_advice: 0, support: 0.9 } };
  let settings; let users; let row; let statements; let analyses; let transactions; let audits; let session;
  const reset = (next = {}) => {
    settings = next; statements = []; analyses = 0; transactions = 0; audits = []; session = null;
    users = {
      [mother]: { user_id: mother, role: 'mother', onboarding_complete: true, id: motherMember, alias: 'Kind Lotus fixture', rules_version: policy.RULES_VERSION, suspended: false },
      [admin]: { user_id: admin, role: 'admin', onboarding_complete: true, id: adminMember, alias: 'Kind Olive fixture', rules_version: policy.RULES_VERSION, suspended: false },
      [guardian]: { user_id: guardian, role: 'guardian', onboarding_complete: true },
    };
    row = { id: randomUUID(), author_id: motherMember, parent_id: null, session_id: null, title: request.title,
      topic: request.topic, body_encrypted: encryptJournal(request.body), status: 'pending', version: 1, language: 'en',
      client_request_id: request.client_request_id, created_at: '2026-10-15T12:00:00Z',
      moderation: { ...metadata, request_fingerprint: policy.submission(request).fingerprint } };
  };
  const db = { query: async (sql, params = []) => {
    statements.push(sql);
    if (sql.includes('SELECT u.id AS user_id')) {
      const user = users[params[0]];
      return { rows: !user || user.inactive ? [] : [{ ...user }] };
    }
    if (sql.includes('SELECT suspended,rules_version')) {
      return { rows: Object.values(users).filter((user) => user.id === params[0]).map((user) => ({ suspended: user.suspended, rules_version: user.rules_version })) };
    }
    if (sql.startsWith('SELECT * FROM community_content WHERE author_id')) {
      return { rows: settings.existing ? [{ ...row }] : [] };
    }
    if (sql.startsWith('SELECT * FROM community_content WHERE id')) {
      return { rows: [{ ...row, ...(sql.includes('FOR UPDATE') ? settings.lockedChange : {}) }] };
    }
    if (sql.includes('SELECT c.*, m.alias')) {
      return { rows: settings.parentUnavailable ? [] : [{ ...row, id: params[1], status: settings.parentPending ? 'pending' : 'published', alias: 'Kind Lotus parent' }] };
    }
    if (sql.includes('SELECT m.id FROM community_members m JOIN users')) return { rows: settings.authorUnavailable ? [] : [{ id: motherMember }] };
    if (sql.includes('SELECT p.id FROM community_content')) return { rows: settings.parentUnavailable ? [] : [{ id: row.parent_id }] };
    if (sql.includes('INSERT INTO community_content')) {
      const created = { ...row, author_id: params[0], parent_id: params[1], session_id: params[2], topic: params[3],
        title: params[4], body_encrypted: params[5], language: params[6], moderation: JSON.parse(params[7]),
        expert_answer: params[8], client_request_id: params[9] };
      row = created;
      return { rows: [created] };
    }
    if (sql.startsWith('UPDATE community_content SET status = $2')) {
      row = { ...row, status: params[1], moderation: JSON.parse(params[2]), version: row.version + 1 };
      return { rows: [], rowCount: 1 };
    }
    if (sql.startsWith('UPDATE community_content SET status = \'deleted\'')) {
      if (row.status === 'deleted') return { rowCount: 0, rows: [] };
      row = { ...row, status: 'deleted', body_encrypted: null };
      return { rowCount: 1, rows: [] };
    }
    if (sql.startsWith('SELECT id FROM community_content')) return { rows: row.status === 'deleted' ? [{ id: row.id }] : [] };
    if (sql.startsWith('UPDATE community_reports')) return { rows: [], rowCount: 1 };
    if (sql.startsWith('INSERT INTO community_moderation_audit')) { audits.push(params); return { rows: [], rowCount: 1 }; }
    if (sql.includes('SELECT c.*,c.created_at::text AS cursor_time')) {
      return { rows: Array.from({ length: 21 }, (_, index) => ({ ...row, id: randomUUID(), alias: 'Kind Lotus review',
        author_eligible: index !== 0, parent_eligible: index !== 1, cursor_time: `2026-10-15 12:00:${String(index).padStart(2, '0')}+00` })) };
    }
    if (sql.includes('SELECT m.id,m.alias,m.suspended,m.joined_at')) {
      return { rows: Array.from({ length: 21 }, (_, index) => ({ id: randomUUID(), alias: `Kind Daisy ${index}`, suspended: index === 0,
        joined_at: '2026-10-15T12:00:00Z', cursor_time: '2026-10-15 12:00:00+00', user_id: mother, phone: 'must-not-expose' })) };
    }
    if (sql.includes('INSERT INTO community_sessions')) {
      if (session) return { rows: [] };
      session = { id: params[0], host_id: params[1], title: params[2], description: params[3], expert_name: params[4],
        credentials: params[5], starts_at: params[6], ends_at: params[7] };
      return { rows: [{ id: session.id }] };
    }
    if (sql.startsWith('SELECT * FROM community_sessions')) {
      return { rows: settings.sessionClosed ? [{ id: params[0], cancelled: true }] : session ? [{ ...session }] : [] };
    }
    if (sql.startsWith('UPDATE community_sessions SET cancelled')) return { rowCount: settings.sessionMissing ? 0 : 1, rows: [] };
    throw new Error(`Unexpected synthetic SQL: ${sql.slice(0, 80)}`);
  } };
  database.query = (...args) => db.query(...args);
  database.withTransaction = async (run) => { transactions++; return run(db); };
  policy.moderate = async () => {
    analyses++;
    if (settings.afterAnalysis) settings.afterAnalysis();
    return settings.aiUnavailable ? { ...metadata, ai: 'unavailable' } : { ...metadata };
  };
  policy.readiness = async () => ({ required: true, configured: true, ready: true, human_review_required: true });
  delete require.cache[require.resolve('../src/modules/community/community.service')];
  const service = require('../src/modules/community/community.service');
  try {
    await t.test('guardians, incomplete onboarding and disabled accounts have no access', async () => {
      reset();
      await assert.rejects(service.status(guardian), { statusCode: 403 });
      users[mother].onboarding_complete = false;
      await assert.rejects(service.status(mother), { statusCode: 403 });
      users[mother].onboarding_complete = true; users[mother].inactive = true;
      await assert.rejects(service.status(mother), { statusCode: 403 });
      assert.equal(transactions, 0);
    });
    await t.test('exact replay returns private submitted content without additional inference or writes', async () => {
      reset({ existing: true });
      const replay = await service.create(mother, request);
      assert.equal(replay.id, row.id);
      assert.equal(replay.body, request.body);
      assert.equal(JSON.stringify(replay).includes(mother), false);
      assert.equal(replay.moderation, undefined);
      assert.equal(analyses, 0); assert.equal(transactions, 0);
    });
    await t.test('changed payload and deleted replay cannot silently masquerade as a saved new post', async () => {
      reset({ existing: true });
      await assert.rejects(service.create(mother, { ...request, body: 'Different message.' }), { statusCode: 409 });
      row.status = 'deleted'; row.body_encrypted = null;
      await assert.rejects(service.create(mother, request), { statusCode: 410 });
      assert.equal(analyses, 0);
    });
    await t.test('AI outage accepts a private pending submission but never auto-publishes it', async () => {
      reset({ aiUnavailable: true }); process.env.COMMUNITY_AI_REQUIRED = 'true';
      const post = await service.create(mother, request);
      assert.equal(post.status, 'pending'); assert.equal(analyses, 1);
      assert.equal(post.moderation, undefined);
      assert.equal(row.moderation.ai, 'unavailable');
      assert.equal(row.moderation.request_fingerprint, policy.submission(request).fingerprint);
    });
    await t.test('deleted parent and closed Q&A fail before inference', async () => {
      reset({ parentUnavailable: true });
      await assert.rejects(service.create(mother, { ...request, parent_id: randomUUID() }), { statusCode: 404 });
      assert.equal(analyses, 0);
      reset({ sessionClosed: true });
      await assert.rejects(service.create(mother, { ...request, session_id: randomUUID() }), { statusCode: 409 });
      assert.equal(analyses, 0);
    });
    await t.test('role, activity, guideline acceptance and suspension are checked again after inference', async () => {
      for (const mutate of [() => { users[mother].inactive = true; }, () => { users[mother].role = 'guardian'; },
        () => { users[mother].rules_version = 'outdated'; }, () => { users[mother].suspended = true; }]) {
        reset({ afterAnalysis: mutate });
        await assert.rejects(service.create(mother, request), { statusCode: 403 });
        assert.equal(statements.some((sql) => sql.includes('INSERT INTO community_content')), false);
      }
    });
    await t.test('required AI outage refuses publication without any write or resolving reports', async () => {
      reset({ aiUnavailable: true }); process.env.COMMUNITY_AI_REQUIRED = 'true';
      await assert.rejects(service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed supportive content', version: 1 }), { statusCode: 503 });
      assert.equal(row.status, 'pending'); assert.equal(audits.length, 0); assert.equal(transactions, 0);
    });
    await t.test('human publication persists fresh, bounded AI audit metadata and the manual decision', async () => {
      reset(); process.env.COMMUNITY_AI_REQUIRED = 'true';
      await service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed supportive content', version: 1 });
      assert.equal(row.status, 'published'); assert.equal(row.version, 2);
      assert.equal(row.moderation.human_review, true); assert.equal(row.moderation.ai_required, true);
      assert.equal(row.moderation.full_text_processed, true); assert.equal(row.moderation.model_version, 'test-model');
      assert.equal(audits[0][0], admin); assert.equal(audits[0][2], 'publish');
    });
    await t.test('explicit human-only fallback is auditable and never automatic', async () => {
      reset({ aiUnavailable: true }); process.env.COMMUNITY_AI_REQUIRED = 'false';
      await service.review(admin, row.id, { decision: 'publish', reason: 'Manual reviewed fallback', version: 1 });
      assert.equal(row.status, 'published'); assert.equal(row.moderation.ai, 'unavailable');
      assert.equal(row.moderation.human_review, true); assert.equal(row.moderation.ai_required, false);
    });
    await t.test('revoked moderator role and changed version after AI cannot publish stale content', async () => {
      reset({ afterAnalysis: () => { users[admin].role = 'mother'; } });
      await assert.rejects(service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed content', version: 1 }), { statusCode: 403 });
      assert.equal(audits.length, 0);
      reset({ lockedChange: { version: 2 } });
      await assert.rejects(service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed content', version: 1 }), { statusCode: 409 });
      assert.equal(audits.length, 0);
    });
    await t.test('suspended/unconsented author and missing parent remain unpublishable', async () => {
      reset({ authorUnavailable: true });
      await assert.rejects(service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed content', version: 1 }), { statusCode: 409 });
      reset({ parentUnavailable: true }); row.parent_id = randomUUID();
      await assert.rejects(service.review(admin, row.id, { decision: 'publish', reason: 'Reviewed content', version: 1 }), { statusCode: 409 });
      assert.equal(row.status, 'pending');
    });
    await t.test('moderators can remove unsafe/orphaned items while AI is unavailable', async () => {
      reset({ aiUnavailable: true, authorUnavailable: true, parentUnavailable: true }); process.env.COMMUNITY_AI_REQUIRED = 'true';
      row.parent_id = randomUUID();
      await service.review(admin, row.id, { decision: 'remove', reason: 'Removed unsafe item', version: 1 });
      assert.equal(row.status, 'removed'); assert.equal(analyses, 0); assert.equal(audits[0][2], 'remove');
    });
    await t.test('FIFO queue uses forward stable keyset pages and retains remove-only orphan/member items', async () => {
      reset(); const page = await service.queue(admin);
      assert.equal(page.items.length, 20); assert.ok(page.next_cursor);
      assert.equal(page.items[0].can_publish, false); assert.equal(page.items[0].publication_blocked_reason, 'member_unavailable');
      assert.equal(page.items[1].publication_blocked_reason, 'parent_unavailable');
      await service.queue(admin, page.next_cursor);
      assert.ok(statements.some((sql) => sql.includes('(c.created_at,c.id) >')));
      assert.ok(statements.some((sql) => sql.includes('ORDER BY c.created_at ASC,c.id ASC LIMIT 21')));
      await assert.rejects(service.queue(mother), { statusCode: 403 });
    });
    await t.test('admin member restore list and model readiness expose no accounts or health records', async () => {
      reset(); const page = await service.members(admin);
      assert.equal(page.items.length, 20); assert.ok(page.next_cursor);
      assert.deepEqual(Object.keys(page.items[0]).sort(), ['alias', 'id', 'joined_at', 'suspended']);
      assert.equal(JSON.stringify(page).includes(mother), false); assert.equal(JSON.stringify(page).includes('must-not-expose'), false);
      await assert.rejects(service.members(mother), { statusCode: 403 });
      await assert.rejects(service.moderationStatus(mother), { statusCode: 403 });
      assert.equal((await service.moderationStatus(admin)).human_review_required, true);
    });
    await t.test('owner deletion retries are idempotent and no longer erase public children visibility checks', async () => {
      reset(); await service.remove(mother, row.id); await service.remove(mother, row.id);
      assert.equal(row.status, 'deleted'); assert.equal(row.body_encrypted, null);
      assert.equal(analyses, 0);
    });
    await t.test('scheduled Q&A exact retries return one session and changed data conflicts', async () => {
      reset();
      const data = { title: 'Recovery questions', description: 'A reviewed professional question session', expert_name: 'Test professional',
        credentials: 'Operationally reviewed fixture', starts_at: new Date(Date.now() + 60000).toISOString(),
        ends_at: new Date(Date.now() + 3600000).toISOString(), client_request_id: randomUUID() };
      const first = await service.schedule(admin, data);
      assert.deepEqual(await service.schedule(admin, data), first);
      await assert.rejects(service.schedule(admin, { ...data, title: 'A changed session' }), { statusCode: 409 });
      await assert.rejects(service.schedule(mother, data), { statusCode: 403 });
      await assert.rejects(service.schedule(admin, { ...data, starts_at: '2026-02-30T12:30:00Z' }), { statusCode: 422 });
    });
    await t.test('cancel reports missing session instead of falsely confirming success', async () => {
      reset({ sessionMissing: true });
      await assert.rejects(service.cancelSession(admin, randomUUID()), { statusCode: 404 });
      reset(); assert.equal((await service.cancelSession(admin, randomUUID())).cancelled, true);
    });
  } finally {
    database.query = original.query; database.withTransaction = original.transaction;
    policy.moderate = original.moderate; policy.readiness = original.readiness;
    if (original.required === undefined) delete process.env.COMMUNITY_AI_REQUIRED; else process.env.COMMUNITY_AI_REQUIRED = original.required;
    delete require.cache[require.resolve('../src/modules/community/community.service')];
  }
});
