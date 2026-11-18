const net = require('node:net');
const policy = require('./chatbot.policy');

function privateHost(hostname) {
  const host = hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (['localhost', '127.0.0.1', '::1'].includes(host)) return true;
  if (net.isIP(host) === 4) {
    const [first, second] = host.split('.').map(Number);
    return first === 10 || first === 127 || (first === 172 && second >= 16 && second <= 31) || (first === 192 && second === 168);
  }
  // Deployment operators may explicitly name their own private service, never a model-provider API.
  return (process.env.ML_SERVICE_HOST_ALLOWLIST || '').split(',').map((value) => value.trim().toLowerCase()).filter(Boolean).includes(host);
}
function baseUrl() {
  const url = new URL(process.env.ML_SERVICE_URL || 'http://127.0.0.1:8001');
  if (!['http:', 'https:'].includes(url.protocol) || !privateHost(url.hostname) || url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) {
    throw new Error('Chatbot requires a trusted private ML service.');
  }
  const host = url.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '::1'].includes(host)) {
    throw new Error('Private chatbot inference outside loopback requires HTTPS.');
  }
  if (process.env.NODE_ENV === 'production' && !process.env.ML_SERVICE_TOKEN) throw new Error('Internal ML service authentication must be configured in production.');
  return url.origin;
}
function validateReply(data, language) {
  if (!data || typeof data !== 'object' || data.language !== language || typeof data.reply !== 'string'
      || !data.reply.trim() || data.reply.length > 8000 || !['local_rag', 'retrieval_only', 'safety', 'unavailable'].includes(data.mode)
      || data.clinical_validation !== false || typeof data.model_version !== 'string' || data.model_version.length > 120
      || !Array.isArray(data.sources) || data.sources.length > 5 || !Array.isArray(data.actions) || data.actions.length > 7
      || data.actions.some((action) => !policy.ACTIONS.includes(action)) || !data.safety
      || typeof data.safety.requires_help !== 'boolean' || typeof data.safety.guardian_alert_allowed !== 'boolean'
      || !(data.safety.reason === null || (typeof data.safety.reason === 'string' && data.safety.reason.length <= 80))
      || !data.state || typeof data.state !== 'object' || Array.isArray(data.state) || JSON.stringify(data.state).length > 4000) {
    throw new Error('Invalid private chatbot response.');
  }
  for (const source of data.sources) {
    if (!source || typeof source.id !== 'string' || source.id.length > 100 || typeof source.title !== 'string' || source.title.length > 250
        || typeof source.url !== 'string' || source.url.length > 1000) throw new Error('Invalid chatbot source.');
    const url = new URL(source.url);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Invalid source URL.');
  }
  return { reply: data.reply, language, mode: data.mode, sources: data.sources.map(({ id, title, url }) => ({ id, title, url })),
    actions: [...new Set(data.actions)], safety: { requires_help: data.safety.requires_help, guardian_alert_allowed: false, reason: data.safety.reason },
    state: data.state, model_version: data.model_version, clinical_validation: false };
}
async function reply(body) {
  const controller = new AbortController();
  const configured = Number(process.env.CHATBOT_TIMEOUT_MS || 35000);
  const timeoutMs = Number.isFinite(configured) ? Math.min(45000, Math.max(1000, configured)) : 35000;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${baseUrl()}/v1/chatbot/reply`, { method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', ...(process.env.ML_SERVICE_TOKEN ? { Authorization: `Bearer ${process.env.ML_SERVICE_TOKEN}` } : {}) },
      body: JSON.stringify(body) });
    if (!response.ok) throw new Error('Unavailable');
    const raw = await response.text();
    if (raw.length > 24000) throw new Error('Unbounded chatbot response');
    return validateReply(JSON.parse(raw), body.language);
  } catch {
    // No prompt/raw health details are logged, and failure is never disguised as model inference.
    return policy.fallback(body.language);
  } finally { clearTimeout(timeout); }
}
module.exports = { reply, privateHost, baseUrl, validateReply };
