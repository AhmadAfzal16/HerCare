#!/usr/bin/env node
// Refresh the trusted-channel library for live YouTube search (normally done automatically in the
// background at most once a day per channel). Use --force to refresh every channel now.
// Prints counts only; never the API key.
require('dotenv').config();
const database = require('../src/config/database');
const service = require('../src/modules/content/content.service');
const live = require('../src/modules/content/content.live');

(async () => {
  if (!live.enabled()) { console.log('Live search is off: set YOUTUBE_API_KEY in .env (and CONTENT_LIVE_SEARCH is not "off").'); return; }
  const result = await service.refreshLibrary({ force: process.argv.includes('--force') });
  const { rows } = await database.query('SELECT kind,COUNT(*)::int AS videos FROM content_live_library GROUP BY kind ORDER BY kind');
  console.log(`Channels refreshed: ${result.refreshed}, failed: ${result.failed}.`);
  console.log(`Library: ${rows.map((row) => `${row.kind} ${row.videos}`).join(', ') || 'empty'}.`);
})().catch(() => { console.error('Live library refresh failed. Check the database and YouTube settings.'); process.exitCode = 1; })
  .finally(() => database.pool.end().catch(() => {}));
