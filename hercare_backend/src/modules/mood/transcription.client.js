const { AppError } = require('../../middleware/error_handler');
function validateResult(value) {
  if (!value || !['draft', 'no_speech'].includes(value.status) || value.review_required !== true
      || !['en', 'ur'].includes(value.language) || typeof value.text !== 'string' || value.text.length > 5000
      || typeof value.model_version !== 'string' || value.model_version.length > 100
      || (value.status === 'draft' && !value.text.trim()) || (value.status === 'no_speech' && value.text !== '')) {
    throw new AppError('Invalid voice service response.', 502);
  }
  return { ...value, text: value.text.trim() };
}
async function transcribe(audio, contentType, language, signal) {
  const base = (process.env.ML_SERVICE_URL || 'http://127.0.0.1:8001').replace(/\/$/, '');
  let url;
  try { url = new URL(base); } catch { throw new AppError('Voice service is not configured.', 503); }
  if (url.username || url.password || !['http:', 'https:'].includes(url.protocol)
      || (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))) {
    throw new AppError('Voice service requires private authenticated TLS.', 503);
  }
  if (process.env.NODE_ENV === 'production' && !process.env.ML_SERVICE_TOKEN) {
    throw new AppError('Private voice service authentication is not configured.', 503);
  }
  if (!Buffer.isBuffer(audio) || audio.length > 4194304 || !['audio/wav', 'audio/mp4', 'audio/mpeg'].includes(contentType)
      || !['en', 'ur'].includes(language)) throw new AppError('Invalid voice input.', 422);
  try {
    const response = await fetch(base + '/v1/audio/transcribe', {
      method: 'POST', redirect: 'error', body: audio,
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(90000)]) : AbortSignal.timeout(90000),
      headers: { 'Content-Type': contentType, 'X-Voice-Language': language,
        ...(process.env.ML_SERVICE_TOKEN ? { Authorization: 'Bearer ' + process.env.ML_SERVICE_TOKEN } : {}) },
    });
    if (!response.ok) throw new AppError('Voice service could not transcribe this clip.', [413, 422].includes(response.status) ? 422 : 503);
    const reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 40000) throw new AppError('Invalid voice service response.', 502);
        chunks.push(Buffer.from(value));
      }
    } finally { await reader.cancel(); }
    return validateResult(JSON.parse(Buffer.concat(chunks).toString('utf8')));
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError('Voice service unavailable. Original audio remains saved.', 503);
  }
}
module.exports = { transcribe, validateResult };
