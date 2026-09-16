const { createClient } = require('@supabase/supabase-js');

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.warn('[warn] SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY belum diisi. Set di .env (lokal) atau Netlify env vars (production).');
}

// service_role key dipakai supaya backend bisa baca/tulis penuh tanpa terhalang
// Row Level Security. Key ini HARUS hanya ada di environment variable server-side
// (Netlify Functions env), TIDAK BOLEH pernah dikirim ke frontend/browser.
const supabase = createClient(url, key, {
  auth: { persistSession: false }
});

module.exports = supabase;
