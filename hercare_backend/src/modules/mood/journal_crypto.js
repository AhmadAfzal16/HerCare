const crypto = require('crypto');

function resolveKey() {
  const configured = process.env.JOURNAL_ENCRYPTION_KEY;
  if (configured) {
    if (/^[a-fA-F0-9]{64}$/.test(configured)) {
      return Buffer.from(configured, 'hex');
    }
    const decoded = Buffer.from(configured, 'base64');
    if (decoded.length === 32) return decoded;
    throw new Error('JOURNAL_ENCRYPTION_KEY must be 32-byte base64 or 64-character hex.');
  }
  if (process.env.NODE_ENV === 'production') {
    throw new Error('JOURNAL_ENCRYPTION_KEY is required in production.');
  }
  const developmentSecret = process.env.JWT_ACCESS_SECRET || 'hercare-development-only';
  return crypto.createHash('sha256').update(developmentSecret).digest();
}

const key = resolveKey();

function encryptJournal(plainText) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(plainText, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return ['v1', iv, tag, ciphertext]
    .map((value) => Buffer.isBuffer(value) ? value.toString('base64url') : value)
    .join('.');
}

function decryptJournal(payload) {
  const [version, ivValue, tagValue, ciphertextValue] = payload.split('.');
  if (version !== 'v1' || !ivValue || !tagValue || !ciphertextValue) {
    throw new Error('Unsupported encrypted journal format.');
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(ivValue, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagValue, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextValue, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

function tokenize(value) {
  return [...new Set(value
    .normalize('NFKC')
    .toLocaleLowerCase('en-US')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/u)
    .filter((token) => token.length >= 2)
    .slice(0, 100))];
}

function buildBlindIndexes(value) {
  return tokenize(value).map((token) => crypto
    .createHmac('sha256', key)
    .update(token)
    .digest('base64url'));
}

module.exports = {
  encryptJournal,
  decryptJournal,
  buildBlindIndexes,
};
