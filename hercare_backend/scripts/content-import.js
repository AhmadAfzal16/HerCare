#!/usr/bin/env node
const { readFile, stat } = require('node:fs/promises');
const { resolve } = require('node:path');
const { prepareCatalog, readJSON } = require('../src/modules/content/content.sources');
const policy = require('../src/modules/content/content.policy');

function parseArgs(args) {
  const options = { apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') { if (options.apply) throw new Error('Do not repeat options.'); options.apply = true; }
    else if (arg === '--help') options.help = true;
    else if (['--file', '--api'].includes(arg)) {
      const key = arg.slice(2);
      if (options[key] || !args[index + 1] || args[index + 1].startsWith('--')) throw new Error('Each option needs one value.');
      options[key] = args[++index];
    } else throw new Error('Unknown option. Use --help for usage.');
  }
  if (!options.help && !options.file) throw new Error('Provide --file with an operator-owned catalog JSON file.');
  return options;
}
function adminEndpoint(value, environment = process.env.NODE_ENV) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Provide a valid --api URL ending in /api/v1.'); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !(environment !== 'production' && loopback && url.protocol === 'http:'))
      || url.username || url.password || url.search || url.hash || !/^\/api\/v1\/?$/.test(url.pathname)) {
    throw new Error('Use your own HTTPS /api/v1 endpoint; HTTP loopback is for development only.');
  }
  url.pathname = '/api/v1/content/admin/items';
  return url.href;
}
async function loadManifest(path) {
  const absolute = resolve(path);
  const info = await stat(absolute);
  if (!info.isFile() || info.size > 1024 * 1024) throw new Error('The catalog must be a JSON file no larger than 1 MiB.');
  const contents = await readFile(absolute);
  if (contents.byteLength > 1024 * 1024) throw new Error('The catalog exceeded the safe size limit.');
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(contents).replace(/^\uFEFF/, '')); }
  catch { throw new Error('The catalog is not valid UTF-8 JSON.'); }
}
async function execute(options, { fetchImpl = globalThis.fetch, env = process.env, write = console.log, manifest } = {}) {
  const source = manifest || await loadManifest(options.file);
  const items = await prepareCatalog(source, { fetchImpl });
  write(`Verified ${items.length} catalog items. Imports are drafts only; review and publication are separate administrator actions.`);
  if (!options.apply) {
    for (const item of items) write(JSON.stringify({ key: item.key, client_request_id: item.client_request_id, format: item.format,
      category: item.category, title_en: item.title_en, verse_reference: item.verse_reference, media_url: item.media_url }));
    write('Dry run: no administrator API requests or database changes were made. Add --apply to create drafts.');
    return { applied: false, count: items.length };
  }
  const endpoint = adminEndpoint(options.api || env.CONTENT_IMPORT_API_URL, env.NODE_ENV);
  const token = env.CONTENT_IMPORT_TOKEN;
  if (typeof token !== 'string' || token.length < 20 || token.length > 16000 || /\s/.test(token)) throw new Error('Set CONTENT_IMPORT_TOKEN to your administrator access token.');
  let account;
  try { account = policy.uuid(env.CONTENT_IMPORT_ACCOUNT_ID); }
  catch { throw new Error('Set CONTENT_IMPORT_ACCOUNT_ID to the same administrator account UUID.'); }
  let created = 0;
  for (const item of items) {
    const { key, ...body } = item;
    let response;
    try {
      response = await fetchImpl(endpoint, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(10000),
        headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: `Bearer ${token}`,
          'X-Content-Account-Id': account }, body: JSON.stringify(body) });
      if (!response.ok || response.redirected || (response.url && response.url !== endpoint)) throw new Error('Draft import request failed.');
      const result = await readJSON(response);
      if (!result?.success || result.data?.status !== 'draft') throw new Error('The server did not confirm a draft.');
      write(`Draft confirmed: ${key}.`);
      created += 1;
    } catch {
      throw new Error(`Draft import stopped after ${created} confirmations. Some drafts may already exist; retry the unchanged manifest safely. No approval or publication was requested.`);
    } finally { if (response?.body && !response.body.locked) await response.body.cancel().catch(() => {}); }
  }
  return { applied: true, count: created };
}
async function main(args = process.argv.slice(2)) {
  const options = parseArgs(args);
  if (options.help) {
    console.log('Usage: node scripts/content-import.js --file catalog.json [--api https://your-server/api/v1] [--apply]\n'
      + 'Default: source verification and dry run only. Media/source hosts must be explicitly enabled in CONTENT_MEDIA_ALLOWED_HOSTS.\n'
      + 'Apply requires CONTENT_IMPORT_TOKEN and CONTENT_IMPORT_ACCOUNT_ID; tokens are never accepted as command arguments or printed.\n'
      + 'All items remain drafts. An authorised human must review and publish them separately.');
    return;
  }
  await execute(options);
}
if (require.main === module) main().catch(() => {
  // Never print arbitrary exception text: it may include a bearer token or private endpoint details.
  console.error('Content import failed. Check the manifest, trusted-host configuration, source availability and administrator environment. '
    + 'If --apply was used, unchanged retries are safe; some drafts may already exist. No approval or publication was requested.');
  process.exitCode = 1;
});
module.exports = { parseArgs, adminEndpoint, loadManifest, execute, main };
