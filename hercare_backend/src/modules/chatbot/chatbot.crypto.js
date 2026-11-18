const crypto = require('node:crypto');

function key() {
  const configured = process.env.CHATBOT_ENCRYPTION_KEY || process.env.CHAT_ENCRYPTION_KEY || process.env.JOURNAL_ENCRYPTION_KEY;
  if (configured) {
    const decoded = /^[a-fA-F0-9]{64}$/.test(configured) ? Buffer.from(configured, 'hex') : Buffer.from(configured, 'base64');
    if (decoded.length !== 32) throw new Error('Chatbot encryption key must be 32 bytes.');
    return decoded;
  }
  if (process.env.NODE_ENV === 'production') throw new Error('CHATBOT_ENCRYPTION_KEY or CHAT_ENCRYPTION_KEY is required in production.');
  return crypto.createHash('sha256').update(process.env.JWT_ACCESS_SECRET || 'hercare-chatbot-development-only').digest();
}
function encrypt(value, scope) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  cipher.setAAD(Buffer.from(`hercare:chatbot:v1:${scope}`, 'utf8'));
  const ciphertext = Buffer.concat([cipher.update(String(value), 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
}
function decrypt(payload, scope) {
  const [version, iv, tag, ciphertext, extra] = String(payload).split('.');
  if (version !== 'v1' || !iv || !tag || ciphertext === undefined || extra !== undefined) throw new Error('Unsupported encrypted chatbot format.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'base64url'));
  decipher.setAAD(Buffer.from(`hercare:chatbot:v1:${scope}`, 'utf8'));
  decipher.setAuthTag(Buffer.from(tag, 'base64url'));
  return Buffer.concat([decipher.update(Buffer.from(ciphertext, 'base64url')), decipher.final()]).toString('utf8');
}
function fingerprint(value) { return crypto.createHmac('sha256', key()).update(`chatbot-request:${value}`).digest('hex'); }
module.exports = { encrypt, decrypt, fingerprint };
