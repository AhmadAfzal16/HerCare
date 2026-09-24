const logger = require('../utils/logger');

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
  // Log the full error internally
  logger.error(`[${req.method} ${req.url}] ${err.message}`, {
    stack: err.stack,
    body: redactSensitive(req.body),
  });

  // Determine status code
  const statusCode = err.statusCode || err.status || 500;

  // Operational errors (intentionally thrown with a message for the client)
  const isOperational = err.isOperational === true;

  const response = {
    success: false,
    message: isOperational
      ? err.message
      : process.env.NODE_ENV === 'production'
        ? 'An internal error occurred. Please try again.'
        : err.message,
  };

  // Include validation errors if present
  if (err.errors) {
    response.errors = err.errors;
  }

  // Only expose stack in development
  if (process.env.NODE_ENV === 'development') {
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
