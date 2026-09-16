// Entry point untuk development lokal saja: `npm start`.
// Di production (Netlify), yang dipakai adalah netlify/functions/api.js.
const app = require('./app');

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Kaia Booking (dev lokal) jalan di http://localhost:${PORT}`));
