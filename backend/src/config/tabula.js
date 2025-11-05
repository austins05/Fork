require('dotenv').config();

module.exports = {
  apiUrl: process.env.TABULA_API_URL || 'https://test-api.tracmap.com',
  apiKey: process.env.TABULA_API_KEY,
  apiSecret: process.env.TABULA_API_SECRET,
  timeout: 30000, // 30 seconds
  retryAttempts: 3
};
