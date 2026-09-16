const serverless = require('serverless-http');
const app = require('../../server/app');

const handler = serverless(app, {
  request: (req) => {
    if (!req.url.startsWith('/api')) {
      req.url = `/api${req.url.startsWith('/') ? '' : '/'}${req.url}`;
    }
  }
});

module.exports.handler = handler;
