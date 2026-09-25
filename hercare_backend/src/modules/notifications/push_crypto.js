const crypto = require('crypto');

function resolveKey() {
  const configured = process.env.PUSH_TOKEN_ENCRYPTION_KEY
    || process.env.CHAT_ENCRYPTION_KEY
    || process.env.JOURNAL_ENCRYPTION_KEY;
  if (configured) {
    if (/^[a-fA-F0-9]{64}$/.test(configured)) return Buffer.from(configured, 'hex');
    const decoded = Buffer.from(configured, 'base64');
    if (decoded.length === 32) return decoded;
    throw new Error('PUSH_TOKEN_ENCRYPTION_KEY must be 32-byte base64 or 64-character hex.');
  }
  if (process.env.NODE_ENV === 'production') {
    throw new Error('PUSH_TOKEN_ENCRYPTION_KEY is required in production.');
  }
  return crypto.createHash('sha256')
    .update(process.env.JWT_ACCESS_SECRET || 'hercare-development-only')
    .digest();
}

function encryptToken(token) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', resolveKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
  return ['v1', iv, cipher.getAuthTag(), ciphertext]
    .map((part) => Buffer.isBuffer(part) ? part.toString('base64url') : part)
    .join('.');
}

function decryptToken(payload) {
  const [version, iv, tag, ciphertext] = payload.split('.');
  if (version !== 'v1' || !iv || !tag || !ciphertext) throw new Error('Invalid push token payload.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', resolveKey(), Buffer.from(iv, 'base64url'));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertext, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

function hashToken(token) {
  return crypto.createHmac('sha256', resolveKey()).update(token).digest('hex');
}

module.exports = { encryptToken, decryptToken, hashToken };
