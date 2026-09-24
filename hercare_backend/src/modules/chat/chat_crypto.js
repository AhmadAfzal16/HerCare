const crypto = require('crypto');

function resolveKey() {
  const configured = process.env.CHAT_ENCRYPTION_KEY || process.env.JOURNAL_ENCRYPTION_KEY;
  if (configured) {
    if (/^[a-fA-F0-9]{64}$/.test(configured)) return Buffer.from(configured, 'hex');
    const decoded = Buffer.from(configured, 'base64');
    if (decoded.length === 32) return decoded;
    throw new Error('CHAT_ENCRYPTION_KEY must be 32-byte base64 or 64-character hex.');
  }
  if (process.env.NODE_ENV === 'production') {
    throw new Error('CHAT_ENCRYPTION_KEY is required in production.');
  }
  return crypto.createHash('sha256')
    .update(process.env.JWT_ACCESS_SECRET || 'hercare-chat-development-only')
    .digest();
}

const key = resolveKey();

function encryptMessage(plainText) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
  return ['v1', iv, cipher.getAuthTag(), ciphertext]
    .map((value) => Buffer.isBuffer(value) ? value.toString('base64url') : value)
    .join('.');
}

function decryptMessage(payload) {
  const [version, ivValue, tagValue, ciphertextValue] = payload.split('.');
  if (version !== 'v1' || !ivValue || !tagValue || !ciphertextValue) {
    throw new Error('Unsupported encrypted chat format.');
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm', key, Buffer.from(ivValue, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagValue, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextValue, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

module.exports = { encryptMessage, decryptMessage };

