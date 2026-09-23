require('dotenv').config();

const app = require('./src/app');
const { pool } = require('./src/config/database');
const logger = require('./src/utils/logger');

const PORT = process.env.PORT || 5000;

const server = app.listen(PORT, () => {
  logger.info(`HerCare API running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
});

// Graceful shutdown
let shuttingDown = false;
const shutdown = (signal) => {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`${signal} received – shutting down gracefully`);
  server.close(async () => {
    logger.info('HTTP server closed');
    try {
      await pool.end();
      process.exit(0);
    } catch (error) {
      logger.error(`Database shutdown failed: ${error.message}`);
      process.exit(1);
    }
  });
  // Force kill after 10 s
  setTimeout(() => process.exit(1), 10_000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled Rejection:', reason);
  shutdown('unhandledRejection');
});
