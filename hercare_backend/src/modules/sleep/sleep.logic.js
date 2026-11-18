const { AppError } = require('../../middleware/error_handler');

function validateSleep(data, now = Date.now()) {
  const fail = () => { throw new AppError('Enter valid sleep times, quality, and awakenings.', 422); };
  const keys = ['sleep_date', 'bedtime', 'wake_time', 'awake_minutes', 'quality', 'awakenings', 'timezone_offset_minutes'];
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some((key) => !keys.includes(key))) fail();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data.sleep_date)) fail();
  const timestamp = /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/;
  if (!timestamp.test(data.bedtime) || !timestamp.test(data.wake_time)) fail();
  const start = Date.parse(data.bedtime);
  const end = Date.parse(data.wake_time);
  const minutes = (end - start) / 60000;
  if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 1440 || end > now + 60000 || start < now - 366 * 86400000) fail();
  for (const [key, min, max] of [['awake_minutes', 0, 1439], ['timezone_offset_minutes', -840, 840]]) {
    if (!Number.isInteger(data[key]) || data[key] < min || data[key] > max) fail();
  }
  for (const [key, min, max] of [['quality', 1, 5], ['awakenings', 0, 50]]) {
    if (data[key] != null && (!Number.isInteger(data[key]) || data[key] < min || data[key] > max)) fail();
  }
  if (data.awake_minutes >= minutes) fail();
  const localWake = new Date(end - data.timezone_offset_minutes * 60000).toISOString().slice(0, 10);
  if (localWake !== data.sleep_date) fail();
  return { ...data, quality: data.quality ?? null, awakenings: data.awakenings ?? null };
}

function dashboardQuery(query = {}, now = Date.now()) {
  const fail = () => { throw new AppError('Invalid sleep date or timezone.', 422); };
  if (Object.keys(query).some((key) => !['as_of', 'timezone_offset_minutes'].includes(key))) fail();
  const rawOffset = query.timezone_offset_minutes ?? '0';
  if (typeof rawOffset !== 'string' || !/^-?\d{1,4}$/.test(rawOffset)) fail();
  const offset = Number(rawOffset);
  if (offset < -840 || offset > 840) fail();
  const today = new Date(now - offset * 60000).toISOString().slice(0, 10);
  const asOf = query.as_of ?? today;
  if (typeof asOf !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(asOf)) fail();
  const date = Date.parse(`${asOf}T00:00:00Z`);
  if (!Number.isFinite(date) || new Date(date).toISOString().slice(0, 10) !== asOf) fail();
  const age = (Date.parse(today) - date) / 86400000;
  if (age < 0 || age > 365) fail();
  return { asOf, offset };
}

module.exports = { validateSleep, dashboardQuery };
