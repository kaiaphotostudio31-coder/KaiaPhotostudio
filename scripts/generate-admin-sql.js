// Jalankan: node scripts/generate-admin-sql.js email@kamu.com passwordKuat123
// Lalu copy hasilnya dan jalankan di Supabase SQL Editor.
// Password TIDAK dikirim ke mana pun — hanya di-hash secara lokal di komputer kamu.

const bcrypt = require('bcryptjs');

const email = process.argv[2];
const password = process.argv[3];

if (!email || !password) {
  console.log('Cara pakai: node scripts/generate-admin-sql.js email@kamu.com passwordKuat123');
  process.exit(1);
}

const hash = bcrypt.hashSync(password, 10);

console.log('\nJalankan SQL berikut di Supabase SQL Editor:\n');
console.log(`insert into admin_users (name, email, password_hash, role)
values ('Admin Kaia', '${email.toLowerCase()}', '${hash}', 'ADMIN')
on conflict (email) do update set password_hash = excluded.password_hash;
`);
