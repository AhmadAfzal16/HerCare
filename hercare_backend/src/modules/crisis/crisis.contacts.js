const catalog = require('./contacts.json');

// A bounded public directory, never an external fetch or health/location query.
// Return a fresh value so one request cannot mutate another request's catalog.
function getCatalog() { return structuredClone(catalog); }

module.exports = { getCatalog };
