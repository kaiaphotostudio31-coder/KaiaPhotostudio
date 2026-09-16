# Kaia Photo Studio Booking

Booking website Kaia Photo Studio untuk Netlify + Supabase PostgreSQL. Booking, availability, admin, Google Calendar/Drive foundation, customer photo selection, dan production output berjalan melalui API Express di Netlify Functions.

## Arsitektur
- Frontend: `public/` static hosting Netlify
- API: Express + `serverless-http` di `netlify/functions/api.js`
- Database: Supabase PostgreSQL
- Auth admin: JWT HttpOnly cookie
- Timezone bisnis: Asia/Jakarta (WIB)
- Jam operasional: 08:00–18:00 setiap hari

## Setup Supabase
1. Buat project Supabase.
2. Jalankan `supabase/schema.sql` untuk instalasi baru.
3. Untuk project yang sudah memakai schema lama, jalankan migration berurutan dari `supabase/migrations/`.
4. Jangan masukkan service-role key ke browser.

## Environment Variables
Isi di Netlify (server-side):
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMIN_JWT_SECRET`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI`
- `GOOGLE_TOKEN_ENCRYPTION_KEY`
- `GOOGLE_CALENDAR_ID` (ID calendar yang benar; tidak selalu sama dengan email)
- `GOOGLE_REFRESH_TOKEN` (opsional; jika kosong, OAuth callback menyimpan token terenkripsi di Supabase settings)
- `PUBLIC_SITE_URL`

## Admin
Buat hash password menggunakan `scripts/generate-admin-sql.js`, lalu jalankan SQL hasilnya di Supabase. Login di `/admin`.

## Google Calendar + Drive
1. Buat OAuth Client di Google Cloud.
2. Tambahkan redirect URI yang sama dengan `GOOGLE_REDIRECT_URI`.
3. Isi client ID/secret dan encryption key di Netlify.
4. Login admin → Settings → Hubungkan Google Calendar & Drive.
5. Setelah OAuth selesai, set `GOOGLE_CALENDAR_ID` ke calendar ID yang benar.
6. Dari detail booking, admin dapat sync Calendar atau menghubungkan folder Drive.

Booking disimpan lebih dulu. Kegagalan Calendar tidak membatalkan booking; status sync menjadi failed/pending dan dapat dicoba lagi.

## Photo Selection
Admin: Booking → hubungkan Drive folder → buat link pilih foto. Customer mendapat token acak yang hanya mengizinkan akses ke sesi selection tersebut. Foto asli tetap di Google Drive; Supabase menyimpan metadata/reference dan pilihan.

## Template
Template yang tersedia di data model: KP1, KP2, KP3, KP4, KP5. Semua berformat 4×6 portrait / 2:3. Layout visual tidak ditebak: template tetap `REFERENCE_MISSING` sampai konfigurasi visual asli dimasukkan. Setelah referensi dikonfigurasi, ubah status menjadi `IMPLEMENTED` dan isi slot/configuration yang benar.

## Booking safety
- Availability divalidasi server-side.
- 08:00 diterima; booking harus selesai maksimal 18:00.
- Overlap dilindungi PostgreSQL transaction/advisory lock.
- Booking code dialokasikan dari sequence per tanggal, bukan `COUNT(*)`.
- `Idempotency-Key` disimpan di database untuk mencegah duplicate retry.
- Snapshot harga/durasi/package disimpan di booking.
- Family Jadoel memiliki durasi `NULL`; tidak dapat dipilih lewat scheduler sampai durasi ditentukan/manual scheduling.

## Testing
Jalankan:
```bash
node scripts/smoke-test.js
```
Smoke test memeriksa struktur, marker schema, dan obsolete values. Live Supabase/Google API tests harus dijalankan setelah credentials tersedia; jangan menganggapnya sukses hanya karena smoke test lolos.

## Deploy Netlify
1. Push repository ke Git.
2. Connect repository ke Netlify.
3. Build command: `npm install`.
4. Publish directory: `public`.
5. Functions directory: `netlify/functions`.
6. Isi semua environment variables di atas.
7. Jalankan SQL/migrations di Supabase.
8. Deploy.

## Manual dependencies
Studio owner tetap perlu melakukan setup Google Cloud OAuth, memberi akses Calendar/Drive yang sesuai, memasukkan Calendar ID, dan memasukkan referensi visual template KP1–KP5 jika ingin template production benar-benar aktif.
