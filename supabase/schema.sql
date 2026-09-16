create extension if not exists pgcrypto;

-- =========================================================
-- Kaia Photo Studio — Supabase (Postgres) schema
-- Jalankan seluruh file ini sekali di Supabase SQL Editor.
-- =========================================================

create table if not exists packages (
  id bigint generated always as identity primary key,
  category text not null,               -- 'pas_foto' | 'self_photo' | 'wisuda_family' | 'personal_photo' | 'maternity' | 'prewedding'
  name text not null,
  slug text unique not null,
  description text,
  pricing_type text not null default 'fixed',   -- 'fixed' | 'per_person'
  base_price integer not null,                   -- fixed: harga paket. per_person: harga per orang.
  included_people integer,                       -- jumlah orang yang sudah termasuk base_price (khusus 'fixed')
  additional_person_fee integer,                 -- biaya per orang tambahan di luar included_people (null = tidak ada aturan tambahan orang)
  min_people integer,
  max_people integer,                            -- null = tidak dibatasi
  duration_minutes integer,
  benefits jsonb not null default '[]',
  terms jsonb not null default '[]',
  print_options jsonb not null default '[]',     -- pilihan cetak informasional (tidak mengubah harga)
  is_addon boolean not null default false,
  active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists bookings (
  id bigint generated always as identity primary key,
  booking_code text unique not null,
  customer_name text not null,
  whatsapp text not null,
  email text,
  package_id bigint references packages(id),
  package_name_snapshot text not null,
  category_snapshot text,
  pricing_type_snapshot text not null,
  base_price_snapshot integer not null,
  additional_person_fee_snapshot integer,
  included_people_snapshot integer,
  people_count integer not null,
  additional_people_charged integer not null default 0,
  total_price integer not null,
  booking_date date not null,
  start_time text not null,             -- 'HH:MM' WIB
  end_time text not null,               -- 'HH:MM' WIB
  timezone text not null default 'Asia/Jakarta',
  photo_upload_permission text not null,
  payment_status text not null default 'Unpaid',
  booking_status text not null default 'Pending',
  notes text,
  cancel_reason text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists blocked_slots (
  id bigint generated always as identity primary key,
  date date not null,
  start_time text not null,
  end_time text not null,
  reason text,
  created_at timestamptz default now()
);

create table if not exists admin_users (
  id bigint generated always as identity primary key,
  name text,
  email text unique not null,
  password_hash text not null,
  role text not null default 'ADMIN',
  created_at timestamptz default now()
);

-- Key-value store untuk info bisnis, supaya admin bisa ubah tanpa deploy ulang / tanpa
-- perlu tulis file (Netlify Functions filesystem-nya sekali pakai & tidak persisten).
create table if not exists settings (
  key text primary key,
  value text not null
);

create index if not exists idx_bookings_date on bookings(booking_date);
create index if not exists idx_blocked_date on blocked_slots(date);

-- =========================================================
-- Fungsi atomik: cek bentrok jadwal + insert booking dalam SATU transaksi.
-- pg_advisory_xact_lock mengunci per-tanggal selama fungsi ini berjalan, jadi
-- dua booking yang masuk hampir bersamaan pada tanggal yang sama akan diproses
-- berurutan (bukan paralel) — ini yang mencegah double booking di level database,
-- bukan cuma di kode aplikasi.
-- =========================================================
-- =========================================================
-- SEED: info bisnis final
-- =========================================================
insert into settings (key, value) values
  ('studioName', 'Kaia Photo Studio'),
  ('address', 'Jl. Ariloka No. 17, Krobokan, Semarang Barat, Semarang'),
  ('openTime', '08:00'),
  ('closeTime', '18:00'),
  ('whatsapp', '6281390045600'),
  ('instagram', 'kaia.photostudio'),
  ('bankName', 'BCA'),
  ('bankAccount', '0092280193'),
  ('bankHolder', 'Rajendra Satria Rizki Wardhana'),
  ('slotIntervalMinutes', '10')
on conflict (key) do update set value = excluded.value;

-- =========================================================
-- SEED: paket final (menggantikan seluruh paket lama)
-- Catatan jujur soal 2 hal yang TIDAK disebutkan di data asli, jadi dibuat netral
-- (bukan mengarang aturan baru) — cari komentar "CATATAN" di bawah:
-- =========================================================

insert into packages (category, name, slug, pricing_type, base_price, included_people, additional_person_fee, min_people, max_people, duration_minutes, benefits, terms, print_options) values

-- PAS FOTO
-- CATATAN: jumlah orang untuk "Pas Foto Tanpa Print" tidak disebutkan di data asli,
-- jadi tidak dibatasi (min 1, max kosong) alih-alih menebak aturannya.
('pas_foto', 'Pas Foto Tanpa Print', 'pas-foto-tanpa-print', 'fixed', 25000, null, null, null, null, 15,
  '[]', '[]', '[]'),

('pas_foto', 'Pas Foto Dengan Print', 'pas-foto-dengan-print', 'fixed', 50000, 1, null, 1, 1, 15,
  '["Print langsung jadi", "Free 1x edit background", "Edited print photo"]',
  '[]',
  '["2x3 @4 pcs, 3x4 @4 pcs, 4x6 @4 pcs", "4x6 @6 pcs, 3x4 @10 pcs, 2x3 @12 pcs", "4x6 @5 pcs, 3x4 @5 pcs"]'),

-- SELF PHOTO
('self_photo', 'Self Photo Fermium', 'self-photo-fermium', 'fixed', 100000, 2, 25000, 2, null, 25,
  '["1 strip per orang", "Free semua soft file"]', '[]', '[]'),

('self_photo', 'Self Photo Raksa', 'self-photo-raksa', 'fixed', 80000, 2, 25000, 2, null, 15,
  '["1 strip per orang", "Free semua soft file"]', '[]', '[]'),

('self_photo', 'Student Package', 'student-package', 'per_person', 25000, null, null, 3, null, 20,
  '["Free semua soft file", "Free 1 strip per orang"]',
  '["Wajib menunjukkan Student Card / KTM / kartu pelajar aktif"]', '[]'),

-- WISUDA / FAMILY
('wisuda_family', 'Wisuda Bronze', 'wisuda-bronze', 'fixed', 400000, 6, 20000, 1, null, 30,
  '["Estimasi 70+ foto", "10R (20x25 cm) + frame", "Free semua edited soft files", "Maksimal 1 costume"]', '[]', '[]'),

('wisuda_family', 'Wisuda Silver', 'wisuda-silver', 'fixed', 500000, 6, 20000, 1, null, 30,
  '["Estimasi 80+ foto", "12R (30x40 cm) + frame", "Free semua edited soft files", "Maksimal 1 costume"]', '[]', '[]'),

('wisuda_family', 'Wisuda Gold', 'wisuda-gold', 'fixed', 650000, 6, 20000, 1, null, 30,
  '["Estimasi 70-100 foto", "16RS (40x60 cm) + frame", "Free semua edited soft files", "Maksimal 1 costume"]', '[]', '[]'),

('wisuda_family', 'Wisuda Platinum', 'wisuda-platinum', 'fixed', 700000, 6, 20000, 1, null, 30,
  '["Estimasi 90+ foto", "2x 12R (30x40 cm) + frame", "Free semua edited soft files", "Maksimal 1 costume"]', '[]', '[]'),

-- Durasi Family Jadoel memang tidak ditentukan. Simpan NULL agar tidak mengarang jadwal.
('wisuda_family', 'Family Jadoel', 'family-jadoel', 'fixed', 600000, 5, 50000, 3, null, null,
  '["12R (30x40 cm) + frame", "Free semua edited soft files", "Free background set", "Free 1 package pakaian adat Jawa \"jadoel\""]',
  '["Tambahan cetak 4R: Rp20.000/pcs (informasikan ke admin saat booking)"]', '[]'),

-- PERSONAL PHOTO
('personal_photo', 'Personal Photo Soft File', 'personal-photo-soft-file', 'fixed', 75000, 1, null, 1, 1, 7,
  '["Fotografer mengambil foto", "1 background, bebas pilih", "Unlimited style", "Unlimited jumlah foto", "Free semua edited soft files"]',
  '["Tidak menerima request konsep/theme"]', '[]'),

('personal_photo', 'Personal Photo + Print', 'personal-photo-print', 'fixed', 150000, 1, null, 1, 1, 10,
  '["Fotografer mengambil foto", "1 background, bebas pilih", "Unlimited style", "Free semua edited soft files", "Maksimal 1 costume"]',
  '["Tidak menerima request konsep/theme"]',
  '["4R 1 pcs", "4x6 6 pcs"]'),

-- MATERNITY
('maternity', 'Maternity Bronze', 'maternity-bronze', 'fixed', 400000, null, null, 1, 3, 30,
  '["Maksimal 1 costume", "1 background (pilihan: Gray, Brown, Pink, White Livingroom)", "Estimasi 60+ foto", "Free semua edited files", "Free 10RS (20x30 cm) 1 pcs"]', '[]', '[]'),

('maternity', 'Maternity Silver', 'maternity-silver', 'fixed', 500000, null, null, 1, 3, 30,
  '["Maksimal 2 costumes", "1 background (pilihan: Gray, Brown, Pink, White Livingroom)", "Estimasi 60+ foto", "Free semua edited files", "Free 12R (30x40 cm) + frame 1 pcs"]', '[]', '[]'),

('maternity', 'Maternity Gold', 'maternity-gold', 'fixed', 650000, null, null, 1, 3, 30,
  '["Maksimal 2 costumes", "1 background (pilihan: Gray, Brown, Pink, White Livingroom)", "Estimasi 70+ foto", "Free semua edited files", "Free 16RS (40x60 cm) + frame 1 pcs"]', '[]', '[]'),

-- PREWEDDING
-- CATATAN: jumlah orang tidak disebutkan untuk kategori ini (implisit pasangan), jadi
-- tidak dibatasi alih-alih menebak aturannya.
('prewedding', 'Prewedding Bronze', 'prewedding-bronze', 'fixed', 600000, null, null, null, null, 30,
  '["1 photographer", "Indoor studio", "Modern background - pilih 1 warna", "Maksimal 1 costume", "Free edit semua soft files + 5 special edit", "Free 10R (20x25 cm) + frame"]', '[]', '[]'),

('prewedding', 'Prewedding Silver', 'prewedding-silver', 'fixed', 800000, null, null, null, null, 45,
  '["1 photographer", "Indoor studio", "Modern background - pilih 2 warna", "Maksimal 2 costumes", "Free edit semua soft files + 7 special edit", "Free 12R (30x40 cm) + frame"]', '[]', '[]'),

('prewedding', 'Prewedding Gold', 'prewedding-gold', 'fixed', 1100000, null, null, null, null, 60,
  '["1 photographer", "Indoor studio", "Modern background - pilih 2-3 warna", "Maksimal 2 costumes", "Free edit semua soft files + 10 special edit", "Free 16RS (40x60 cm) + frame"]', '[]', '[]'),

('prewedding', 'Prewedding Platinum', 'prewedding-platinum', 'fixed', 1500000, null, null, null, null, 60,
  '["1 photographer", "Indoor studio", "Modern background - pilih 2-3 warna", "Maksimal 2-3 costumes", "Free edit semua soft files + 15 special edit", "Free 10R (20x25 cm) + frame 1 pcs", "Free 16RS (40x60 cm) + frame 1 pcs"]', '[]', '[]')

on conflict (slug) do nothing;


-- HARDENING / CALENDAR / DRIVE / PHOTO SELECTION
-- Kaia hardening migration. Safe to run after the original schema.
alter table packages alter column duration_minutes drop not null;
alter table bookings add column if not exists duration_minutes_snapshot integer;
alter table bookings add column if not exists calendar_sync_status text not null default 'pending';
alter table bookings add column if not exists idempotency_key text;
create unique index if not exists uq_bookings_idempotency_key on bookings(idempotency_key) where idempotency_key is not null;

create table if not exists booking_idempotency (
  id bigint generated always as identity primary key,
  idempotency_key text not null unique,
  request_hash text not null,
  booking_id bigint references bookings(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists booking_daily_sequences (
  booking_date date primary key,
  next_value integer not null default 1
);

create table if not exists calendar_sync (
  booking_id bigint primary key references bookings(id) on delete cascade,
  status text not null default 'pending',
  google_event_id text unique,
  attempt_token uuid,
  processing_until timestamptz,
  last_error text,
  synced_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists google_oauth_states (
  state_hash text primary key,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists drive_folders (
  booking_id bigint primary key references bookings(id) on delete cascade,
  folder_id text not null,
  folder_name text,
  validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists templates (
  code text primary key,
  name text not null,
  status text not null default 'REFERENCE_MISSING',
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists photo_selection_sessions (
  id bigint generated always as identity primary key,
  booking_id bigint not null references bookings(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  status text not null default 'open',
  template_code text references templates(code),
  selected_color text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists photo_metadata (
  id bigint generated always as identity primary key,
  selection_session_id bigint not null references photo_selection_sessions(id) on delete cascade,
  drive_file_id text not null,
  file_name text not null,
  display_name text not null,
  code text,
  mime_type text not null,
  thumbnail_url text,
  created_at timestamptz not null default now(),
  unique(selection_session_id, drive_file_id)
);

create table if not exists photo_selections (
  id bigint generated always as identity primary key,
  selection_session_id bigint not null references photo_selection_sessions(id) on delete cascade,
  photo_id bigint not null references photo_metadata(id) on delete cascade,
  position integer not null,
  created_at timestamptz not null default now(),
  unique(selection_session_id, photo_id),
  unique(selection_session_id, position)
);

insert into templates(code,name,status,config) values
('KP1','KP1','REFERENCE_MISSING','{"canvas":{"width":1200,"height":1800,"unit":"px","aspectRatio":"2:3"},"supportedColors":["#1a3961","#000000"]}'),
('KP2','KP2','REFERENCE_MISSING','{"canvas":{"width":1200,"height":1800,"unit":"px","aspectRatio":"2:3"},"supportedColors":[]}'),
('KP3','KP3','REFERENCE_MISSING','{"canvas":{"width":1200,"height":1800,"unit":"px","aspectRatio":"2:3"},"supportedColors":[]}'),
('KP4','KP4','REFERENCE_MISSING','{"canvas":{"width":1200,"height":1800,"unit":"px","aspectRatio":"2:3"},"supportedColors":[]}'),
('KP5','KP5','REFERENCE_MISSING','{"canvas":{"width":1200,"height":1800,"unit":"px","aspectRatio":"2:3"},"supportedColors":[]}')
on conflict(code) do nothing;

update settings set value='18:00' where key='closeTime';
update packages set duration_minutes=null, updated_at=now() where slug='family-jadoel';
update bookings b set duration_minutes_snapshot = p.duration_minutes from packages p where b.package_id=p.id and b.duration_minutes_snapshot is null;

insert into booking_daily_sequences(booking_date,next_value)
select booking_date, coalesce(max(substring(booking_code from '([0-9]+)$')::integer),0)+1
from bookings
where booking_code ~ '[0-9]+$'
group by booking_date
on conflict (booking_date) do update set next_value = greatest(booking_daily_sequences.next_value, excluded.next_value);

create or replace function create_booking(
  p_idempotency_key text,
  p_request_hash text,
  p_customer_name text,
  p_whatsapp text,
  p_email text,
  p_package_id bigint,
  p_package_name text,
  p_category text,
  p_pricing_type text,
  p_base_price integer,
  p_duration_minutes integer,
  p_additional_person_fee integer,
  p_included_people integer,
  p_people_count integer,
  p_additional_people_charged integer,
  p_total_price integer,
  p_booking_date date,
  p_start_time text,
  p_photo_upload_permission text
) returns bookings as $$
declare
  result bookings;
  seq_no integer;
  end_min integer;
  end_time_str text;
  existing_id bigint;
  request_hash_existing text;
begin
  if p_duration_minutes is null then raise exception 'DURATION_UNSPECIFIED'; end if;
  perform pg_advisory_xact_lock(hashtext(p_booking_date::text));

  insert into booking_idempotency(idempotency_key,request_hash,booking_id)
    values(p_idempotency_key,p_request_hash,null)
    on conflict(idempotency_key) do nothing;

  select bi.booking_id, bi.request_hash into existing_id, request_hash_existing
    from booking_idempotency bi
    where bi.idempotency_key=p_idempotency_key
    for update;

  if existing_id is not null then
    if request_hash_existing = p_request_hash then
      select * into result from bookings where id=existing_id;
      return result;
    end if;
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;

  end_min := split_part(p_start_time, ':', 1)::integer * 60 + split_part(p_start_time, ':', 2)::integer + p_duration_minutes;
  end_time_str := lpad((end_min/60)::text,2,'0') || ':' || lpad((end_min%60)::text,2,'0');

  if exists(select 1 from bookings where booking_date=p_booking_date and booking_status!='Cancelled' and start_time < end_time_str and end_time > p_start_time)
     or exists(select 1 from blocked_slots where date=p_booking_date and start_time < end_time_str and end_time > p_start_time) then
    raise exception 'SLOT_TAKEN';
  end if;

  insert into booking_daily_sequences(booking_date,next_value) values(p_booking_date,2)
    on conflict(booking_date) do update set next_value=booking_daily_sequences.next_value+1 returning next_value-1 into seq_no;

  insert into bookings(
    booking_code,customer_name,whatsapp,email,package_id,package_name_snapshot,category_snapshot,pricing_type_snapshot,base_price_snapshot,
    duration_minutes_snapshot,additional_person_fee_snapshot,included_people_snapshot,people_count,additional_people_charged,total_price,
    booking_date,start_time,end_time,timezone,photo_upload_permission,payment_status,booking_status,idempotency_key
  ) values(
    'KAIA-'||to_char(p_booking_date,'YYMMDD')||'-'||lpad(seq_no::text,3,'0'),p_customer_name,p_whatsapp,p_email,p_package_id,p_package_name,p_category,p_pricing_type,p_base_price,
    p_duration_minutes,p_additional_person_fee,p_included_people,p_people_count,p_additional_people_charged,p_total_price,p_booking_date,p_start_time,end_time_str,'Asia/Jakarta',p_photo_upload_permission,'Unpaid','Pending',p_idempotency_key
  ) returning * into result;

  update booking_idempotency set booking_id=result.id where idempotency_key=p_idempotency_key;
  insert into calendar_sync(booking_id,status) values(result.id,'pending') on conflict do nothing;
  return result;
end;
$$ language plpgsql;

create or replace function claim_calendar_sync(p_booking_id bigint) returns calendar_sync as $$
declare r calendar_sync;
begin
  insert into calendar_sync(booking_id,status) values(p_booking_id,'pending') on conflict do nothing;
  update calendar_sync set status='processing',attempt_token=gen_random_uuid(),processing_until=now()+interval '5 minutes',updated_at=now()
  where booking_id=p_booking_id and (status in ('pending','failed') or (status='processing' and processing_until < now())) returning * into r;
  return r;
end;
$$ language plpgsql;

create or replace function create_blocked_slot(p_date date,p_start text,p_end text,p_reason text) returns blocked_slots as $$
declare r blocked_slots;
begin
  perform pg_advisory_xact_lock(hashtext(p_date::text));
  if exists(select 1 from bookings where booking_date=p_date and booking_status!='Cancelled' and start_time<p_end and end_time>p_start)
     or exists(select 1 from blocked_slots where date=p_date and start_time<p_end and end_time>p_start) then raise exception 'SLOT_TAKEN'; end if;
  insert into blocked_slots(date,start_time,end_time,reason) values(p_date,p_start,p_end,p_reason) returning * into r;
  return r;
end;
$$ language plpgsql;

-- Final hardening: atomic photo selection + opaque customer booking access.
-- Run after 003_final_concurrency_oauth_hardening.sql.

create or replace function submit_photo_selection(
  p_session_id bigint,
  p_photo_ids bigint[],
  p_template_code text,
  p_color text
) returns void as $$
declare
  valid_count integer;
  template_ok boolean;
begin
  if p_photo_ids is null or coalesce(array_length(p_photo_ids,1),0) < 1 then
    raise exception 'PHOTO_SELECTION_EMPTY';
  end if;

  if not exists (
    select 1 from photo_selection_sessions
    where id=p_session_id and expires_at >= now()
  ) then
    raise exception 'SELECTION_SESSION_INVALID';
  end if;

  select exists(
    select 1 from templates t
    where t.code=p_template_code
      and t.status='IMPLEMENTED'
      and coalesce(t.config->'supportedColors','[]'::jsonb) ? p_color
  ) into template_ok;
  if not template_ok then raise exception 'TEMPLATE_OR_COLOR_INVALID'; end if;

  if (select count(distinct x) from unnest(p_photo_ids) x) <> array_length(p_photo_ids,1) then raise exception 'PHOTO_SELECTION_DUPLICATE'; end if;

  select count(*) into valid_count
  from photo_metadata pm
  where pm.selection_session_id=p_session_id
    and pm.id = any(p_photo_ids);
  if valid_count <> array_length(p_photo_ids,1) then raise exception 'PHOTO_NOT_IN_SESSION'; end if;

  delete from photo_selections where selection_session_id=p_session_id;
  insert into photo_selections(selection_session_id,photo_id,position)
  select p_session_id, photo_id, ordinality::integer
  from unnest(p_photo_ids) with ordinality as x(photo_id,ordinality);

  update photo_selection_sessions
  set template_code=p_template_code,
      selected_color=p_color,
      status='submitted',
      submitted_at=now(),
      updated_at=now()
  where id=p_session_id;
end;
$$ language plpgsql security definer set search_path=public;


-- FINAL SECURITY HARDENING
-- Backend uses the Supabase service role; public/anon clients must not execute booking or sync RPCs directly.
revoke all on function create_booking(
  text,text,text,text,text,bigint,text,text,text,integer,integer,integer,integer,integer,integer,date,text,text
) from public, anon, authenticated;

revoke all on function claim_calendar_sync(bigint) from public, anon, authenticated;
revoke all on function create_blocked_slot(date,text,text,text) from public, anon, authenticated;

-- All application tables are accessed by the backend service role.
-- Keep direct browser access closed even if a public Supabase key is exposed.
alter table packages enable row level security;
alter table bookings enable row level security;
alter table blocked_slots enable row level security;
alter table booking_daily_sequences enable row level security;
alter table booking_idempotency enable row level security;
alter table calendar_sync enable row level security;
alter table google_oauth_states enable row level security;
alter table drive_folders enable row level security;
alter table photo_selection_sessions enable row level security;
alter table photo_metadata enable row level security;
alter table photo_selections enable row level security;
alter table templates enable row level security;
alter table settings enable row level security;
alter table admin_users enable row level security;

-- No browser-facing policies are intentionally granted. service_role bypasses RLS.

