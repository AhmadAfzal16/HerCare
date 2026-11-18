function createReadThroughCache({ maxEntries, now = Date.now }) {
  if (!Number.isInteger(maxEntries) || maxEntries < 1) {
    throw new TypeError('maxEntries must be a positive integer');
  }
  const entries = new Map();
  const inFlight = new Map();

  async function get(key, ttlMs, load) {
    const cached = entries.get(key);
    if (cached && cached.expiresAt > now()) {
      entries.delete(key);
      entries.set(key, cached);
      return cached.value;
    }
    if (cached) entries.delete(key);
    if (inFlight.has(key)) return inFlight.get(key);

    const pending = Promise.resolve().then(load).then((value) => {
      if (value !== null && value !== undefined) {
        entries.set(key, { value, expiresAt: now() + ttlMs });
        while (entries.size > maxEntries) entries.delete(entries.keys().next().value);
      }
      return value;
    }).finally(() => inFlight.delete(key));
    inFlight.set(key, pending);
    return pending;
  }

  return { get };
}

module.exports = { createReadThroughCache };
