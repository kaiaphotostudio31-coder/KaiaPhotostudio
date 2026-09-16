require('dotenv').config();
const path = require('path');
const express = require('express');

const publicRoutes = require('./routes/public');
const { router: adminRoutes } = require('./routes/admin');

const app = express();
app.use(express.json());

app.use('/api', publicRoutes);
app.use('/api/admin', adminRoutes);

// Static files hanya dipakai untuk dev lokal (`node server/index.js`).
// Di Netlify, folder `public/` di-serve langsung oleh Netlify sebagai static hosting,
// TIDAK lewat function ini — function ini hanya menangani /api/*.
app.use(express.static(path.join(__dirname, '..', 'public')));

module.exports = app;
