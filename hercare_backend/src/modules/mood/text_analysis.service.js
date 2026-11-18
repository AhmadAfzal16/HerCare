const { analyzeJournal } = require('./journal_analysis');
let retryAfter = 0;
let inFlight = 0;

async function analyzeText(text) {
  const rules = analyzeJournal(text);
  const fallback = (status) => ({ ...rules, metadata: {
    sentiment_source: 'rules', model_status: status, distress_source: 'rules', clinical_validation: false,
  } });
  // Deterministic safety remains independent; negative sentiment is not suicidality.
  if (rules.containsDanger) return fallback('safety_rules_priority');
  if (process.env.NLP_ENABLED === 'false' || Date.now() < retryAfter || inFlight >= 4) return fallback('unavailable');
  const base = (process.env.ML_SERVICE_URL || 'http://127.0.0.1:8001').replace(/\/$/, '');
  let url;
  try { url = new URL(base); } catch { return fallback('invalid_service_config'); }
  if (url.protocol !== 'https:' && !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) return fallback('private_tls_required');
  const abort = new AbortController();
  const timeout = setTimeout(() => abort.abort(), 1500);
  inFlight += 1;
  try {
    const response = await fetch(`${base}/v1/text/sentiment`, {
      method: 'POST', signal: abort.signal,
      headers: { 'Content-Type': 'application/json',
        ...(process.env.ML_SERVICE_TOKEN ? { Authorization: `Bearer ${process.env.ML_SERVICE_TOKEN}` } : {}) },
      body: JSON.stringify({ text }),
    });
    if (!response.ok) throw new Error('NLP unavailable');
    const result = await response.json();
    if (!['positive', 'negative', 'neutral', null].includes(result.label)
        || !Number.isFinite(result.score) || result.score < -1 || result.score > 1
        || !['estimated', 'abstained'].includes(result.status)) throw new Error('Invalid NLP output');
    if (result.status === 'abstained' || result.label === null) return fallback('abstained');
    return { ...rules, sentimentLabel: result.label, sentimentScore: Number(result.score.toFixed(3)),
      analysisVersion: 'sentiment-public-v2', metadata: {
        sentiment_source: 'ml', model_version: String(result.model_version).slice(0, 80),
        language: result.language, model_status: result.status, validation_status: 'public_benchmark_only',
        distress_source: 'rules', clinical_validation: false,
      } };
  } catch {
    retryAfter = Date.now() + 30000;
    return fallback('unavailable');
  } finally {
    clearTimeout(timeout);
    inFlight -= 1;
  }
}
module.exports = { analyzeText, _reset: () => { retryAfter = 0; } };
