#!/usr/bin/env node
// M11 Phase 3: how recommendations are performing, for an operator tuning the ranking weights.
// Prints aggregates only. Any group with fewer than MIN_GROUP accounts is suppressed so no
// individual mother's behaviour or mood can be read from the output. Nothing is changed.
require('dotenv').config();
const database = require('../src/config/database');
const ranking = require('../src/modules/content/content.ranking');

const MIN_GROUP = 5;
const pct = (part, whole) => (whole ? `${Math.round((100 * part) / whole)}%` : '-');

// Rows: one per (account, item) with engagement and feedback, joined with the item's reason/category.
const ENGAGEMENT_SQL = `SELECT v.user_id, v.last_reason, c.category, c.format, c.tags,
    v.view_count, v.media_opens, v.completions, v.engaged_seconds, f.value AS feedback
  FROM content_views v JOIN content_items c ON c.id=v.content_id
  LEFT JOIN content_feedback f ON f.user_id=v.user_id AND f.content_id=v.content_id
  WHERE GREATEST(v.last_viewed_at, COALESCE(v.last_engaged_at, v.last_viewed_at)) > NOW()-INTERVAL '90 days'`;
// Observational only: mood on the day after she finished calming/learning content,
// compared with her own 30-day average. Not evidence that content caused any change.
const MOOD_SQL = `SELECT c.category, v.user_id, m.mood_rating - avg30.average AS delta
  FROM content_views v JOIN content_items c ON c.id=v.content_id
  JOIN mood_checkins m ON m.mother_id=v.user_id AND m.entry_date=(v.last_engaged_at AT TIME ZONE 'UTC')::date+1
  JOIN LATERAL (SELECT AVG(mood_rating)::float AS average FROM mood_checkins
    WHERE mother_id=v.user_id AND entry_date BETWEEN CURRENT_DATE-30 AND CURRENT_DATE) avg30 ON avg30.average IS NOT NULL
  WHERE v.completions>0 AND v.last_engaged_at > NOW()-INTERVAL '60 days'`;

function summarize(rows, keyOf) {
  const groups = new Map();
  for (const row of rows) {
    for (const key of [].concat(keyOf(row)).filter(Boolean)) {
      const g = groups.get(key) || { users: new Set(), items: 0, opens: 0, done: 0, helpful: 0, notHelpful: 0, dismissed: 0 };
      g.users.add(row.user_id); g.items += 1;
      g.opens += Number(row.media_opens) > 0 ? 1 : 0; g.done += Number(row.completions) > 0 ? 1 : 0;
      if (row.feedback === 'helpful') g.helpful += 1;
      if (row.feedback === 'not_helpful') g.notHelpful += 1;
      if (row.feedback === 'dismissed') g.dismissed += 1;
      groups.set(key, g);
    }
  }
  return [...groups.entries()].map(([key, g]) => ({ key, accounts: g.users.size, opened: g.items,
    played: pct(g.opens, g.items), finished: pct(g.done, g.items), helpful: pct(g.helpful, g.items),
    not_helpful: pct(g.notHelpful, g.items), dismissed: pct(g.dismissed, g.items), _g: g }))
    .filter((row) => row.accounts >= MIN_GROUP).sort((a, b) => b.opened - a.opened);
}
// Plain-language hints; an operator decides whether to change weights in the admin policy.
function suggestions(byReason) {
  const hints = [];
  for (const row of byReason) {
    const { _g: g } = row;
    if (g.items < 20) continue;
    if (g.notHelpful + g.dismissed > g.helpful * 2) hints.push(`"${row.key}" cards are often marked not helpful or dismissed: consider lowering the weight behind them.`);
    else if (g.helpful + g.done > g.items * 0.5) hints.push(`"${row.key}" cards are often finished or marked helpful: the weight behind them looks well placed.`);
  }
  return hints;
}

async function main() {
  try {
    const engagement = (await database.query(ENGAGEMENT_SQL)).rows;
    const mood = (await database.query(MOOD_SQL)).rows;
    const strip = (rows) => rows.map(({ _g, ...rest }) => rest);
    const byReason = summarize(engagement, (row) => row.last_reason || 'unknown');
    console.log(`Content recommendation report (last 90 days; groups under ${MIN_GROUP} accounts hidden)\n`);
    console.log('By the reason shown on the card when she opened it:'); console.table(strip(byReason));
    console.log('By category:'); console.table(strip(summarize(engagement, (row) => row.category)));
    console.log('By format:'); console.table(strip(summarize(engagement, (row) => row.format)));
    console.log('By tag:'); console.table(strip(summarize(engagement, (row) => row.tags)).slice(0, 25));
    const moodGroups = new Map();
    for (const row of mood) {
      const g = moodGroups.get(row.category) || { users: new Set(), sum: 0, n: 0 };
      g.users.add(row.user_id); g.sum += Number(row.delta); g.n += 1; moodGroups.set(row.category, g);
    }
    const moodTable = [...moodGroups.entries()].filter(([, g]) => g.users.size >= MIN_GROUP)
      .map(([category, g]) => ({ category, accounts: g.users.size, observations: g.n, next_day_mood_vs_own_average: (g.sum / g.n).toFixed(2) }));
    console.log('Next-day mood after finishing content (observational, 1-5 scale; NOT proof of benefit):');
    if (moodTable.length) console.table(moodTable); else console.log('  Not enough data yet.\n');
    const hints = suggestions(byReason);
    console.log('Suggestions:'); console.log(hints.length ? hints.map((h) => `  - ${h}`).join('\n') : '  Not enough data for suggestions yet (need 20+ opens per reason).');
    const known = Object.keys(ranking.REASONS).join(', ');
    console.log(`\nReason codes: ${known}. Weights are changed in the admin content policy, not by this script.`);
  } finally { await database.pool.end().catch(() => {}); }
}
if (require.main === module) main().catch(() => { console.error('Content report failed. Check the database settings and migrations.'); process.exitCode = 1; });
module.exports = { summarize, suggestions, MIN_GROUP };
