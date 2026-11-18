const logger = require('../utils/logger');
const { requestPath } = require('../utils/request_path');

const SENSITIVE_FIELDS = new Set([
  'password',
  'confirm_password',
  'current_password',
  'new_password',
  'refresh_token',
  'access_token',
  'invite_code',
  'content',
  'journal_text',
  'transcript',
  'search',
  'query',
  'answers',
  'notification_text',
  'message',
  'preview',
  'package_name',
  'latitude',
  'longitude',
  'location',
  'consent_tier1',
  'consent_tier2',
  'consent_tier3',
]);

function redactSensitive(value) {
  if (Array.isArray(value)) return value.map(redactSensitive);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    SENSITIVE_FIELDS.has(key) ? '[REDACTED]' : redactSensitive(item),
  ]));
}

/**
 * Centralized error handler middleware.
 * Catches all errors thrown or passed to next(err).
 *
 * Security: never expose stack traces in production responses.
 */
const errorHandler = (err, req, res, _next) => {
  const path = requestPath(req);
  const privateCrisis = /^\/api\/v1\/(?:crisis|sleep|mood|therapy|chat)(?:\/|$)/.test(path);
  const privateCommunity = /^\/api\/v1\/community(?:\/|$)/.test(path);
  const privateContent = /^\/api\/v1\/content(?:\/|$)/.test(path);
  const privateEditorial = privateCommunity || privateContent;
  const privateMonitoring = /^\/api\/v1\/risk\/m4(?:\/|$)/.test(path);
  const suppressDetails = privateEditorial || privateMonitoring;
  // Community parser/database errors can echo submitted text in their message
  // or stack. Never retain these, or the body, in diagnostic logs.
  logger.error(`[${req.method} ${path}] ${suppressDetails ? 'Private request failed' : err.message}`, {
    ...(suppressDetails ? { statusCode: err.statusCode || err.status || 500 } : { stack: err.stack }),
    body: privateMonitoring ? '[REDACTED MONITORING REQUEST]'
      : privateContent ? '[REDACTED CONTENT REQUEST]'
      : privateCommunity ? '[REDACTED COMMUNITY REQUEST]'
      : privateCrisis ? '[REDACTED CRISIS REQUEST]' : redactSensitive(req.body),
  });

  // Determine status code
  const statusCode = err.statusCode || err.status || 500;

  // Operational errors (intentionally thrown with a message for the client)
  const isOperational = err.isOperational === true;

  const response = {
    success: false,
    message: isOperational
      ? err.message
      : privateMonitoring || process.env.NODE_ENV === 'production'
        ? 'An internal error occurred. Please try again.'
        : err.message,
  };

  // Include validation errors if present
  if (err.errors && !privateMonitoring) {
    response.errors = err.errors;
  }

  // Only expose stack in development
  if (process.env.NODE_ENV === 'development' && !privateMonitoring) {
    response.stack = err.stack;
  }

  res.status(statusCode).json(response);
};

/**
 * Creates an operational error (safe to send to client).
 */
class AppError extends Error {
  constructor(message, statusCode = 500) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }
}

module.exports = { errorHandler, AppError };
