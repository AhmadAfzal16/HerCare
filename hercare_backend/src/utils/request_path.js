// Do not retain query values, fragments, referrers or control characters in logs.
// Optional location is device-only, including when a client wrongly adds it to a URL.
function requestPath(req) {
  const raw = typeof req.originalUrl === 'string' ? req.originalUrl
    : typeof req.url === 'string' ? req.url : '/';
  const path = raw.split(/[?#]/, 1)[0].slice(0, 512);
  return Array.from(path).filter((character) => {
    const code = character.charCodeAt(0);
    return code > 31 && code !== 127;
  }).join('');
}

module.exports = { requestPath };
