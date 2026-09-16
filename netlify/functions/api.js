const serverless = require('serverless-http');
const app = require('../../server/app');

// Netlify's /api/* redirect strips the /api prefix before invoking the function.
// Express routes in server/app.js intentionally keep /api for local parity.
// Restore the prefix at the function boundary so production and local routing
// behave identically.
const handler = serverless((req, res, next) => {
  if (!req.url.startsWith('/api')) {
    req.url = `/api${req.url.startsWith('/') ? '' : '/'}${req.url}`;
  }
  next();
});

module.exports.handler = handler;
