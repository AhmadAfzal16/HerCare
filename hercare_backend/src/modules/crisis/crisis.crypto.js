const crypto = require('node:crypto');

function key() {
  const configured = process.env.CRISIS_ENCRYPTION_KEY || process.env.JOURNAL_ENCRYPTION_KEY;
  if (configured) {
    const decoded = /^[a-fA-F0-9]{64}$/.test(configured)
      ? Buffer.from(configured, 'hex') : Buffer.from(configured, 'base64');
    if (decoded.length !== 32) throw new Error('Crisis encryption key must be 32 bytes.');
    return decoded;
  }
  if (process.env.NODE_ENV === 'production') throw new Error('CRISIS_ENCRYPTION_KEY or JOURNAL_ENCRYPTION_KEY is required.');
  return crypto.createHash('sha256').update(process.env.JWT_ACCESS_SECRET || 'hercare-crisis-development-only').digest();
}
function encrypt(value, motherId) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  cipher.setAAD(Buffer.from(`hercare:crisis-plan:v1:${motherId}`));
  const body = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), body.toString('base64url')].join('.');
}
function decrypt(value, motherId) {
  const [version, iv, tag, body, extra] = String(value).split('.');
  if (version !== 'v1' || !iv || !tag || !body || extra !== undefined) throw new Error('Invalid encrypted safety plan.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'base64url'));
  decipher.setAAD(Buffer.from(`hercare:crisis-plan:v1:${motherId}`));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(body, 'base64url')), decipher.final()]).toString('utf8'));
}
function fingerprint(value) {
  // This payload contains only action flags and an existing link ID, no health text.
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}
module.exports = { encrypt, decrypt, fingerprint };
