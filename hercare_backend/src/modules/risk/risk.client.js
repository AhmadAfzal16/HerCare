const { AppError } = require('../../middleware/error_handler');

const DEFAULT_URL = 'http://127.0.0.1:8001';

async function predict(features) {
  const baseUrl = (process.env.ML_SERVICE_URL || DEFAULT_URL).replace(/\/$/, '');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(`${baseUrl}/v1/predict`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(process.env.ML_SERVICE_TOKEN
          ? { Authorization: `Bearer ${process.env.ML_SERVICE_TOKEN}` }
          : {}),
      },
      body: JSON.stringify({ features }),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new AppError('The risk model is temporarily unavailable.', 503);
    }
    const data = await response.json();
    const validRisk = ['low', 'moderate', 'high', 'severe'].includes(data.risk_level);
    if (!validRisk || !Number.isFinite(data.depression_probability)) {
      throw new AppError('The risk model returned an invalid response.', 503);
    }
    return data;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError('The risk model is temporarily unavailable.', 503);
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = { predict };

