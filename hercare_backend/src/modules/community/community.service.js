const { query, withTransaction } = require('../../config/database');
const { randomUUID } = require('node:crypto');
const { AppError } = require('../../middleware/error_handler');
const { encryptJournal, decryptJournal } = require('../mood/journal_crypto');
const policy = require('./community.policy');

async function actor(userId, requireMember = true, admin = false, db = null, memberWrite = false) {
  const { rows } = await (db ? db.query.bind(db) : query)(
    `SELECT u.id AS user_id, u.role, u.onboarding_complete, m.id, m.alias, m.rules_version, m.suspended
     FROM users u LEFT JOIN community_members m ON m.user_id = u.id
     WHERE u.id = $1 AND u.is_active = TRUE ${db ? `FOR ${memberWrite ? 'UPDATE' : 'SHARE'} OF u` : ''}`, [userId],
  );
  const user = rows[0];
  if (!user || !['mother', 'admin'].includes(user.role) || (user.role === 'mother' && !user.onboarding_complete)) {
    throw new AppError('Community is available to mothers after onboarding.', 403);
  }
  if (admin && user.role !== 'admin') throw new AppError('Moderator access required.', 403);
  if (user.suspended && !admin) throw new AppError('Your community access is suspended. Contact HerCare support.', 403);
  if (requireMember && (!user.id || user.rules_version !== policy.RULES_VERSION)) throw new AppError('Accept the current community guidelines to join.', 403);
  if (db && user.id) {
    // A suspension/guideline change cannot race a committed community write.
    const member = await db.query(`SELECT suspended,rules_version FROM community_members WHERE id = $1 FOR ${memberWrite ? 'UPDATE' : 'SHARE'}`, [user.id]);
    if (!member.rows[0] || (member.rows[0].suspended && !admin)
      || (requireMember && member.rows[0].rules_version !== policy.RULES_VERSION)) {
      throw new AppError('Community access changed. Please refresh.', 403);
    }
  }
  return user;
}
async function status(userId) {
  const user = await actor(userId, false);
  return { joined: !!user.id && user.rules_version === policy.RULES_VERSION, alias: user.alias || null, member_id: user.id || null,
    is_moderator: user.role === 'admin', rules_version: policy.RULES_VERSION, topics: policy.TOPICS };
}
async function join(userId, body) {
  policy.onlyKeys(body, ['accepted', 'rules_version']);
  if (body.accepted !== true || body.rules_version !== policy.RULES_VERSION) throw new AppError('Please accept the community guidelines.', 422);
  await withTransaction(async (db) => {
    await actor(userId, false, false, db, true);
    await db.query(`INSERT INTO community_members(user_id, alias, rules_version) VALUES ($1,$2,$3)
      ON CONFLICT (user_id) DO UPDATE SET rules_version = EXCLUDED.rules_version`, [userId, policy.alias(), policy.RULES_VERSION]);
  });
  return status(userId);
}
async function spendQuota(userId) {
  const { rows } = await query(
    `INSERT INTO community_write_limits(user_id, writes) VALUES ($1,1)
     ON CONFLICT (user_id) DO UPDATE SET
       writes = CASE WHEN community_write_limits.window_start < NOW() - INTERVAL '15 minutes' THEN 1 ELSE community_write_limits.writes + 1 END,
       window_start = CASE WHEN community_write_limits.window_start < NOW() - INTERVAL '15 minutes' THEN NOW() ELSE community_write_limits.window_start END
     WHERE community_write_limits.writes < 60 OR community_write_limits.window_start < NOW() - INTERVAL '15 minutes'
     RETURNING writes`, [userId],
  );
  if (!rows.length) throw new AppError('Please take a moment before trying again.', 429);
}
const unblocked = (author = 'c.author_id', viewer = '$1') => `NOT EXISTS (
  SELECT 1 FROM community_blocks b WHERE (b.blocker_id = ${viewer} AND b.blocked_id = ${author})
  OR (b.blocked_id = ${viewer} AND b.blocker_id = ${author}))`;
const eligible = (member = 'm', user = 'u') => `${member}.suspended = FALSE AND ${user}.is_active = TRUE
  AND ${member}.rules_version = '${policy.RULES_VERSION}'
  AND (${user}.role = 'admin' OR (${user}.role = 'mother' AND ${user}.onboarding_complete = TRUE))`;
const visibleParent = `EXISTS (SELECT 1 FROM community_content root
  JOIN community_members pm ON pm.id = root.author_id JOIN users pu ON pu.id = pm.user_id
  WHERE root.id = c.parent_id AND root.parent_id IS NULL AND root.status = 'published'
    AND ${eligible('pm', 'pu')} AND ${unblocked('root.author_id')})`;
const projection = `c.*, c.created_at::text AS cursor_time, m.alias,
  EXISTS (SELECT 1 FROM community_sessions s WHERE s.id = c.session_id AND (s.cancelled OR s.ends_at <= NOW())) AS session_closed,
  (SELECT COUNT(*)::int FROM community_content reply JOIN community_members rm ON rm.id = reply.author_id
    JOIN users ru ON ru.id = rm.user_id AND ru.is_active = TRUE
    WHERE reply.parent_id = c.id AND reply.status = 'published' AND ${eligible('rm', 'ru')}
      AND ${unblocked('reply.author_id')}) AS comment_count,
  COALESCE((SELECT jsonb_object_agg(kind, total) FROM
    (SELECT kind, COUNT(*)::int AS total FROM community_reactions WHERE content_id = c.id GROUP BY kind) counts), '{}'::jsonb) AS reactions,
  ARRAY(SELECT kind FROM community_reactions WHERE content_id = c.id AND member_id = $1) AS my_reactions`;
function publicContent(row, viewer) {
  return { id: row.id, parent_id: row.parent_id, session_id: row.session_id, author: { id: row.author_id, alias: row.alias },
    topic: row.topic, title: row.title, body: row.body_encrypted ? decryptJournal(row.body_encrypted) : '',
    language: row.language, status: row.status, expert_answer: row.expert_answer, session_closed: row.session_closed === true,
    is_mine: row.author_id === viewer, created_at: row.created_at, version: row.version,
    comment_count: row.comment_count || 0, reactions: row.reactions || {}, my_reactions: row.my_reactions || [] };
}
async function accessible(db, viewer, id, lock = false) {
  const { rows } = await db.query(
    `SELECT c.*, m.alias FROM community_content c JOIN community_members m ON m.id = c.author_id
     JOIN users u ON u.id = m.user_id AND u.is_active = TRUE
     WHERE c.id = $2 AND ${eligible()} AND c.status <> 'deleted'
       AND (c.status = 'published' OR c.author_id = $1) AND ${unblocked()}
       AND (c.parent_id IS NULL OR ${visibleParent})
       ${lock ? 'FOR UPDATE OF c' : ''}`, [viewer, policy.uuid(id)],
  );
  if (!rows[0]) throw new AppError('This discussion is unavailable.', 404);
  return rows[0];
}
async function list(userId, options = {}) {
  policy.pageOptions(options);
  const user = await actor(userId);
  const params = [user.id];
  const filters = [eligible(), "c.status <> 'deleted'", unblocked()];
  if (options.parent_id) {
    const root = await accessible({ query }, user.id, options.parent_id);
    if (root.parent_id) throw new AppError('Invalid thread.', 422);
    if (root.status !== 'published') throw new AppError('This discussion is unavailable.', 404);
    params.push(root.id); filters.push(`c.parent_id = $${params.length}`);
    filters.push("(c.status = 'published' OR c.author_id = $1)");
    filters.push(visibleParent);
  } else {
    if (options.include_replies !== 'true') filters.push('c.parent_id IS NULL');
    filters.push(options.mine === 'true' ? 'c.author_id = $1' : "c.status = 'published'");
  }
  if (options.topic) {
    if (!policy.TOPICS.includes(options.topic)) throw new AppError('Unknown community topic.', 422);
    params.push(options.topic); filters.push(`c.topic = $${params.length}`);
  }
  if (options.session_id) { params.push(policy.uuid(options.session_id)); filters.push(`c.session_id = $${params.length}`); }
  const cursor = policy.decodeCursor(options.cursor);
  if (cursor) { params.push(...cursor); filters.push(`(c.created_at,c.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`); }
  const { rows } = await query(`SELECT ${projection} FROM community_content c
    JOIN community_members m ON m.id = c.author_id JOIN users u ON u.id = m.user_id AND u.is_active = TRUE
    WHERE ${filters.join(' AND ')} ORDER BY c.created_at DESC,c.id DESC LIMIT 21`, params);
  const page = rows.slice(0, 20);
  return { items: page.map((row) => publicContent(row, user.id)), next_cursor: rows.length > 20 ? policy.encodeCursor(page.at(-1)) : null };
}
async function detail(userId, id) {
  const user = await actor(userId);
  // Visibility and projection share one snapshot: deletion/removal cannot race a second read.
  const { rows } = await query(`SELECT ${projection} FROM community_content c
    JOIN community_members m ON m.id = c.author_id JOIN users u ON u.id = m.user_id
    WHERE c.id = $2 AND ${eligible()} AND c.status <> 'deleted'
      AND (c.status = 'published' OR c.author_id = $1) AND ${unblocked()}
      AND (c.parent_id IS NULL OR ${visibleParent})`, [user.id, policy.uuid(id)]);
  if (!rows[0]) throw new AppError('This discussion is unavailable.', 404);
  return publicContent(rows[0], user.id);
}
function replay(row, submission, user) {
  if (row.status === 'deleted') throw new AppError('This submission was deleted. Start a new post to send different content.', 410);
  const fingerprint = row.moderation?.request_fingerprint;
  const legacyMatch = !fingerprint && row.title === submission.title && decryptJournal(row.body_encrypted) === submission.content
    && row.parent_id === submission.parentId
    && (submission.parentId || (row.topic === submission.topic && row.session_id === submission.sessionId));
  if (fingerprint ? fingerprint !== submission.fingerprint : !legacyMatch) {
    throw new AppError('This request was already used for another submission. Please start a new post.', 409);
  }
  return { ...publicContent({ ...row, alias: user.alias }, user.id), safety_support: row.moderation?.safety_support === true };
}
async function creationContext(db, user, userId, submission, lock = false) {
  const parent = submission.parentId ? await accessible(db, user.id, submission.parentId, lock) : null;
  if (parent && (parent.parent_id || parent.status !== 'published')) throw new AppError('Replies are available on published threads.', 409);
  const topic = parent ? parent.topic : submission.topic;
  const sessionId = parent ? parent.session_id : submission.sessionId;
  if (!policy.TOPICS.includes(topic)) throw new AppError('Choose a community topic.', 422);
  let expert = false;
  if (sessionId) {
    const session = await db.query(`SELECT * FROM community_sessions WHERE id = $1 ${lock ? 'FOR SHARE' : ''}`, [sessionId]);
    const row = session.rows[0];
    if (!row || row.cancelled || new Date(row.ends_at) <= new Date()) throw new AppError('This Q&A is closed.', 409);
    expert = !!parent && user.role === 'admin' && row.host_id === userId && new Date(row.starts_at) <= new Date();
  }
  return { parent, topic, sessionId, expert };
}
async function create(userId, body) {
  const submission = policy.submission(body);
  const user = await actor(userId);
  const existing = await query('SELECT * FROM community_content WHERE author_id = $1 AND client_request_id = $2', [user.id, submission.requestId]);
  if (existing.rows[0]) return replay(existing.rows[0], submission, user);
  await creationContext({ query }, user, userId, submission);
  const analysis = { ...await policy.moderate(`${submission.title}\n${submission.content}`), request_fingerprint: submission.fingerprint };
  return withTransaction(async (db) => {
    const currentUser = await actor(userId, true, false, db);
    const saved = await db.query('SELECT * FROM community_content WHERE author_id = $1 AND client_request_id = $2', [currentUser.id, submission.requestId]);
    if (saved.rows[0]) return replay(saved.rows[0], submission, currentUser);
    const { parent, topic, sessionId, expert } = await creationContext(db, currentUser, userId, submission, true);
    const { rows } = await db.query(
      `INSERT INTO community_content(author_id,parent_id,session_id,topic,title,body_encrypted,language,moderation,expert_answer,client_request_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10)
       ON CONFLICT (author_id,client_request_id) DO NOTHING RETURNING *`,
      [currentUser.id, parent?.id || null, sessionId, topic, submission.title, encryptJournal(submission.content), analysis.language, JSON.stringify(analysis), expert, submission.requestId],
    );
    if (!rows.length) {
      const duplicate = await db.query('SELECT * FROM community_content WHERE author_id = $1 AND client_request_id = $2', [currentUser.id, submission.requestId]);
      return replay(duplicate.rows[0], submission, currentUser);
    }
    return { ...publicContent({ ...rows[0], alias: currentUser.alias }, currentUser.id), safety_support: rows[0].moderation.safety_support === true };
  });
}
async function remove(userId, id) {
  return withTransaction(async (db) => {
    const user = await actor(userId, true, false, db);
    const { rowCount } = await db.query(`UPDATE community_content SET status = 'deleted', body_encrypted = NULL, title = '', moderation = '{}', version = version + 1
      WHERE id = $1 AND author_id = $2 AND status <> 'deleted'`, [policy.uuid(id), user.id]);
    if (!rowCount) {
      const existing = await db.query("SELECT id FROM community_content WHERE id = $1 AND author_id = $2 AND status = 'deleted'", [id, user.id]);
      if (!existing.rows.length) throw new AppError('Content not found.', 404);
    }
    return { deleted: true };
  });
}
async function react(userId, id, body) {
  policy.onlyKeys(body, ['kind', 'active']);
  if (!policy.REACTIONS.includes(body.kind) || typeof body.active !== 'boolean') throw new AppError('Choose a supportive reaction.', 422);
  return withTransaction(async (db) => {
    const user = await actor(userId, true, false, db);
    const row = await accessible(db, user.id, id, true);
    if (row.status !== 'published') throw new AppError('Content is awaiting review.', 409);
    if (row.parent_id) await accessible(db, user.id, row.parent_id);
    if (body.active) await db.query('INSERT INTO community_reactions VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [id, user.id, body.kind]);
    else await db.query('DELETE FROM community_reactions WHERE content_id = $1 AND member_id = $2 AND kind = $3', [id, user.id, body.kind]);
    return { updated: true };
  });
}
async function report(userId, id, body) {
  policy.onlyKeys(body, ['reason']);
  if (!policy.REPORT_REASONS.includes(body.reason)) throw new AppError('Choose a report reason.', 422);
  return withTransaction(async (db) => {
    const user = await actor(userId, true, false, db);
    const row = await accessible(db, user.id, id, true);
    if (row.parent_id) await accessible(db, user.id, row.parent_id);
    await db.query(`INSERT INTO community_reports(content_id,reporter_id,reason) VALUES ($1,$2,$3)
      ON CONFLICT (content_id,reporter_id) DO UPDATE SET reason = EXCLUDED.reason, resolved = FALSE`, [id, user.id, body.reason]);
    await db.query('UPDATE community_content SET version = version + 1 WHERE id = $1', [id]);
    return { reported: true };
  });
}
async function blocks(userId) {
  const user = await actor(userId);
  const { rows } = await query(`SELECT m.id, m.alias FROM community_blocks b JOIN community_members m ON m.id = b.blocked_id WHERE b.blocker_id = $1 ORDER BY m.alias LIMIT 500`, [user.id]);
  return rows;
}
async function block(userId, id, active) {
  id = policy.uuid(id);
  return withTransaction(async (db) => {
    const user = await actor(userId, true, false, db);
    if (id === user.id) throw new AppError('You cannot block yourself.', 422);
    if (active) {
      const exists = await db.query('SELECT id FROM community_members WHERE id = $1', [id]);
      if (!exists.rows.length) throw new AppError('Member unavailable.', 404);
      await db.query('INSERT INTO community_blocks(blocker_id,blocked_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [user.id, id]);
    } else await db.query('DELETE FROM community_blocks WHERE blocker_id = $1 AND blocked_id = $2', [user.id, id]);
    return { blocked: active };
  });
}
async function queue(userId, cursorValue) {
  await actor(userId, false, true);
  const cursor = policy.decodeCursor(cursorValue);
  const { rows } = await query(`SELECT c.*,c.created_at::text AS cursor_time,m.alias,
    (${eligible()}) AS author_eligible,
    (c.parent_id IS NULL OR EXISTS (SELECT 1 FROM community_content p
      JOIN community_members pm ON pm.id = p.author_id JOIN users pu ON pu.id = pm.user_id
      WHERE p.id = c.parent_id AND p.parent_id IS NULL AND p.status = 'published' AND ${eligible('pm', 'pu')})) AS parent_eligible,
    (SELECT jsonb_agg(r.reason) FROM community_reports r WHERE r.content_id = c.id AND r.resolved = FALSE) AS reports
    FROM community_content c JOIN community_members m ON m.id = c.author_id JOIN users u ON u.id = m.user_id
    WHERE (c.status = 'pending' OR (c.status = 'published' AND EXISTS(SELECT 1 FROM community_reports r WHERE r.content_id = c.id AND r.resolved = FALSE)))
      ${cursor ? 'AND (c.created_at,c.id) > ($1::timestamptz,$2::uuid)' : ''}
    ORDER BY c.created_at ASC,c.id ASC LIMIT 21`, cursor || []);
  const page = rows.slice(0, 20);
  return { items: page.map((row) => ({ ...publicContent(row, null), moderation: row.moderation, reports: row.reports || [],
    can_publish: row.author_eligible === true && row.parent_eligible === true,
    publication_blocked_reason: !row.author_eligible ? 'member_unavailable' : !row.parent_eligible ? 'parent_unavailable' : null })),
    next_cursor: rows.length > 20 ? policy.encodeCursor(page.at(-1)) : null };
}
async function review(userId, id, body) {
  await actor(userId, false, true);
  policy.onlyKeys(body, ['decision', 'reason', 'version']);
  const reason = policy.text(body.reason, 3, 500);
  if (!['publish', 'remove'].includes(body.decision) || !Number.isInteger(body.version) || body.version < 1) throw new AppError('Invalid moderation decision.', 422);
  id = policy.uuid(id);
  // Do not hold database locks during model inference; recheck authorization/version below.
  let analysis;
  if (body.decision === 'publish') {
    const candidate = await query('SELECT * FROM community_content WHERE id = $1', [id]);
    const row = candidate.rows[0];
    if (!row || row.status === 'deleted') throw new AppError('Content unavailable.', 404);
    if (row.version !== body.version) throw new AppError('This item changed. Refresh the review queue.', 409);
    analysis = { ...await policy.moderate(`${row.title}\n${decryptJournal(row.body_encrypted)}`),
      ...(row.moderation?.request_fingerprint ? { request_fingerprint: row.moderation.request_fingerprint } : {}) };
    if (policy.aiRequired() && analysis.ai !== 'available') {
      throw new AppError('AI safety triage is unavailable. The post remains private until triage and human review can be completed.', 503);
    }
  }
  return withTransaction(async (db) => {
    await actor(userId, false, true, db);
    const { rows } = await db.query('SELECT * FROM community_content WHERE id = $1 FOR UPDATE', [id]);
    const row = rows[0];
    if (!row || row.status === 'deleted') throw new AppError('Content unavailable.', 404);
    if (row.version !== body.version) throw new AppError('This item changed. Refresh the review queue.', 409);
    if (body.decision === 'publish') {
      const author = await db.query(`SELECT m.id FROM community_members m JOIN users u ON u.id = m.user_id
        WHERE m.id = $1 AND ${eligible()} FOR SHARE OF m,u`, [row.author_id]);
      if (!author.rows.length) throw new AppError('This member is not eligible for publication. Remove the item or resolve their access first.', 409);
      if (row.parent_id) {
        const parent = await db.query(`SELECT p.id FROM community_content p
          JOIN community_members m ON m.id = p.author_id JOIN users u ON u.id = m.user_id
          WHERE p.id = $1 AND p.parent_id IS NULL AND p.status = 'published' AND ${eligible()} FOR SHARE OF p,m,u`, [row.parent_id]);
        if (!parent.rows.length) throw new AppError('The parent discussion is unavailable. Remove this reply or publish the parent first.', 409);
      }
    }
    const audited = { ...(analysis || row.moderation), reviewed_at: new Date().toISOString(),
      human_review: true, decision: body.decision, ai_required: policy.aiRequired() };
    await db.query('UPDATE community_content SET status = $2, moderation = $3::jsonb, version = version + 1 WHERE id = $1',
      [id, body.decision === 'publish' ? 'published' : 'removed', JSON.stringify(audited)]);
    await db.query('UPDATE community_reports SET resolved = TRUE WHERE content_id = $1', [id]);
    await db.query('INSERT INTO community_moderation_audit(moderator_id,content_id,action,reason) VALUES ($1,$2,$3,$4)', [userId, id, body.decision, reason]);
    return { reviewed: true };
  });
}
async function moderationStatus(userId) {
  await actor(userId, false, true);
  return policy.readiness();
}
async function members(userId, cursorValue) {
  await actor(userId, false, true);
  const cursor = policy.decodeCursor(cursorValue);
  const { rows } = await query(`SELECT m.id,m.alias,m.suspended,m.joined_at,m.joined_at::text AS cursor_time
    FROM community_members m JOIN users u ON u.id = m.user_id WHERE u.role <> 'admin'
      ${cursor ? 'AND (m.joined_at,m.id) < ($1::timestamptz,$2::uuid)' : ''}
    ORDER BY m.joined_at DESC,m.id DESC LIMIT 21`, cursor || []);
  const page = rows.slice(0, 20);
  return { items: page.map(({ id, alias, suspended, joined_at }) => ({ id, alias, suspended, joined_at })),
    next_cursor: rows.length > 20 ? policy.encodeCursor(page.at(-1)) : null };
}
async function suspend(userId, id, body) {
  await actor(userId, false, true);
  policy.onlyKeys(body, ['suspended', 'reason']);
  if (typeof body.suspended !== 'boolean') throw new AppError('Invalid suspension.', 422);
  const reason = policy.text(body.reason, 3, 500);
  return withTransaction(async (db) => {
    await actor(userId, false, true, db);
    const { rowCount } = await db.query(`UPDATE community_members m SET suspended = $2 FROM users u
      WHERE m.id = $1 AND u.id = m.user_id AND u.role <> 'admin'`, [policy.uuid(id), body.suspended]);
    if (!rowCount) throw new AppError('Member unavailable.', 404);
    await db.query('INSERT INTO community_moderation_audit(moderator_id,member_id,action,reason) VALUES ($1,$2,$3,$4)', [userId, id, body.suspended ? 'suspend' : 'restore', reason]);
    return { updated: true };
  });
}
async function sessions(userId) {
  await actor(userId);
  const { rows } = await query(`SELECT id,title,description,expert_name,credentials,starts_at,ends_at,cancelled,
    host_id = $1 AS is_host FROM community_sessions WHERE ends_at >= NOW() - INTERVAL '30 days'
    ORDER BY starts_at DESC,id DESC LIMIT 50`, [userId]);
  return rows;
}
async function schedule(userId, body) {
  await actor(userId, false, true);
  policy.onlyKeys(body, ['title', 'description', 'expert_name', 'credentials', 'starts_at', 'ends_at', 'client_request_id']);
  const timezoneDate = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/;
  if (!timezoneDate.test(body.starts_at) || !timezoneDate.test(body.ends_at)
    || !policy.validTimestamp(body.starts_at, false) || !policy.validTimestamp(body.ends_at, false)) {
    throw new AppError('Session dates must include an explicit timezone.', 422);
  }
  const start = Date.parse(body.starts_at); const end = Date.parse(body.ends_at);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || end - start > 8 * 3600000 || end < Date.now()) throw new AppError('Choose a valid future session of up to eight hours.', 422);
  const id = body.client_request_id === undefined ? randomUUID() : policy.uuid(body.client_request_id);
  const values = [id, userId, policy.text(body.title, 3, 160), policy.text(body.description, 5, 1500),
    policy.text(body.expert_name, 2, 100), policy.text(body.credentials, 3, 300), new Date(start), new Date(end)];
  return withTransaction(async (db) => {
    await actor(userId, false, true, db);
    const { rows } = await db.query(`INSERT INTO community_sessions(id,host_id,title,description,expert_name,credentials,starts_at,ends_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (id) DO NOTHING RETURNING id`, values);
    if (!rows.length) {
      const saved = await db.query('SELECT * FROM community_sessions WHERE id = $1', [id]);
      const row = saved.rows[0];
      if (!row || row.host_id !== userId || row.title !== values[2] || row.description !== values[3]
        || row.expert_name !== values[4] || row.credentials !== values[5]
        || new Date(row.starts_at).getTime() !== start || new Date(row.ends_at).getTime() !== end) {
        throw new AppError('This request was already used for another session. Please start a new session.', 409);
      }
      return { id };
    }
    return rows[0];
  });
}
async function cancelSession(userId, id) {
  return withTransaction(async (db) => {
    await actor(userId, false, true, db);
    const { rowCount } = await db.query('UPDATE community_sessions SET cancelled = TRUE WHERE id = $1', [policy.uuid(id)]);
    if (!rowCount) throw new AppError('Session unavailable.', 404);
    return { cancelled: true };
  });
}
module.exports = { actor, status, join, spendQuota, list, detail, create, remove, react, report, blocks, block,
  queue, review, moderationStatus, members, suspend, sessions, schedule, cancelSession };
