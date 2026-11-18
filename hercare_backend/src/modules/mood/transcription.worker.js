const service = require('./transcription.service');
const logger = require('../../utils/logger');
let timer, active, abort;
let stopped = false;
function processPendingSafely() {
  if (stopped || active || process.env.VOICE_WORKER_ENABLED === 'false') return active || Promise.resolve();
  abort = new AbortController();
  active = service.processOne(abort.signal)
    .catch(() => logger.warn('Private voice worker failed; no audio or transcript was logged.'))
    .finally(() => { active = null; abort = null; });
  return active;
}
function startWorker() {
  if (timer || process.env.VOICE_WORKER_ENABLED === 'false') return;
  stopped = false;
  timer = setInterval(processPendingSafely, 5000);
  timer.unref();
  void processPendingSafely();
}
async function stopWorker() {
  stopped = true;
  clearInterval(timer);
  timer = null;
  abort?.abort();
  await active;
}
module.exports = { startWorker, stopWorker, processPendingSafely };
