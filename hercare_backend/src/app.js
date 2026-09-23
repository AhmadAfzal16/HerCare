const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const authRoutes     = require('./modules/auth/auth.routes');
const guardianRoutes = require('./modules/guardian/guardian.routes');
const onboardingRoutes = require('./modules/onboarding/onboarding.routes');
const { errorHandler } = require('./middleware/error_handler');
const { query } = require('./config/database');
const logger = require('./utils/logger');

const app = express();

if (process.env.TRUST_PROXY) {
  const configuredProxy = process.env.TRUST_PROXY;
  const trustProxy = /^\d+$/.test(configuredProxy)
    ? Number(configuredProxy)
    : configuredProxy === 'true' ? true : configuredProxy;
  app.set('trust proxy', trustProxy);
}

// ─── Security Headers ──────────────────────────────────────────────────────
app.use(helmet());

// ─── CORS ──────────────────────────────────────────────────────────────────
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map(o => o.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl)
    if (!origin || allowedOrigins.includes(origin) ||
        (process.env.NODE_ENV !== 'production' && allowedOrigins.length === 0)) {
      callback(null, true);
    } else {
      callback(new Error('CORS: origin not allowed'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ─── Body Parsing ──────────────────────────────────────────────────────────
app.use(express.json({ limit: '10kb' })); // prevent oversized payloads
app.use(express.urlencoded({ extended: false, limit: '10kb' }));

// ─── HTTP Logging ──────────────────────────────────────────────────────────
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined', {
    stream: { write: (msg) => logger.http(msg.trim()) },
  }));
}

// ─── Global Rate Limiter ───────────────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests, please try again later.' },
});
app.use(globalLimiter);

// ─── Health Check ──────────────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/health/ready', async (_req, res) => {
  try {
    await query('SELECT 1');
    res.json({ status: 'ready', timestamp: new Date().toISOString() });
  } catch (error) {
    logger.error(`Readiness check failed: ${error.message}`);
    res.status(503).json({ status: 'not_ready' });
  }
});

// ─── API Routes ────────────────────────────────────────────────────────────
const API_PREFIX = '/api/v1';

app.use(`${API_PREFIX}/auth`,     authRoutes);
app.use(`${API_PREFIX}/guardian`, guardianRoutes);
app.use(`${API_PREFIX}/onboarding`, onboardingRoutes);
// Future modules mount here:
// app.use(`${API_PREFIX}/screening`, screeningRoutes); // Phase 1
// app.use(`${API_PREFIX}/mood`,      moodRoutes);     // Phase 2
// app.use(`${API_PREFIX}/chatbot`,   chatbotRoutes);  // Phase 2

// ─── 404 ───────────────────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// ─── Global Error Handler ──────────────────────────────────────────────────
app.use(errorHandler);

module.exports = app;
