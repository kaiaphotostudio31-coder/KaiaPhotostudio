create extension if not exists pgcrypto;

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
  last_error text,
  synced_at timestamptz,
  updated_at timestamptz not null default now()
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
begin
  if p_duration_minutes is null then raise exception 'DURATION_UNSPECIFIED'; end if;
  perform pg_advisory_xact_lock(hashtext(p_booking_date::text));

  select booking_id into existing_id from booking_idempotency where idempotency_key=p_idempotency_key for update;
  if existing_id is not null then
    if exists(select 1 from booking_idempotency where idempotency_key=p_idempotency_key and request_hash=p_request_hash) then
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

  insert into booking_idempotency(idempotency_key,request_hash,booking_id) values(p_idempotency_key,p_request_hash,result.id);
  insert into calendar_sync(booking_id,status) values(result.id,'pending') on conflict do nothing;
  return result;
end;
$$ language plpgsql;

create or replace function claim_calendar_sync(p_booking_id bigint) returns calendar_sync as $$
declare r calendar_sync;
begin
  insert into calendar_sync(booking_id,status) values(p_booking_id,'pending') on conflict do nothing;
  update calendar_sync set status='processing',attempt_token=gen_random_uuid(),updated_at=now()
  where booking_id=p_booking_id and status in ('pending','failed') returning * into r;
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
