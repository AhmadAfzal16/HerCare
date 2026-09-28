const { AppError } = require('../../middleware/error_handler');

function validateSleep(data, now = Date.now()) {
  const fail = () => { throw new AppError('Enter valid sleep times, quality, and awakenings.', 422); };
  const keys = ['sleep_date', 'bedtime', 'wake_time', 'awake_minutes', 'quality', 'awakenings', 'timezone_offset_minutes'];
  if (!data || typeof data !== 'object' || Object.keys(data).some((key) => !keys.includes(key))) fail();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data.sleep_date)) fail();
  const timestamp = /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/;
  if (!timestamp.test(data.bedtime) || !timestamp.test(data.wake_time)) fail();
  const start = Date.parse(data.bedtime);
  const end = Date.parse(data.wake_time);
  const minutes = (end - start) / 60000;
  if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 1440 || end > now + 60000 || start < now - 366 * 86400000) fail();
  for (const [key, min, max] of [['quality', 1, 5], ['awakenings', 0, 50], ['awake_minutes', 0, 1439], ['timezone_offset_minutes', -840, 840]]) {
    if (!Number.isInteger(data[key]) || data[key] < min || data[key] > max) fail();
  }
  if (data.awake_minutes >= minutes) fail();
  const localWake = new Date(end - data.timezone_offset_minutes * 60000).toISOString().slice(0, 10);
  if (localWake !== data.sleep_date) fail();
  return data;
}

function summarize(rows) {
  const recent = rows.slice(0, 7);
  return {
    recorded_nights: recent.length,
    average_minutes: recent.length ? Math.round(recent.reduce((sum, row) => sum + Number(row.sleep_minutes), 0) / recent.length) : null,
    source: 'self_reported',
  };
}
module.exports = { validateSleep, summarize };
