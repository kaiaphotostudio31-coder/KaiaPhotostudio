create extension if not exists pgcrypto;

-- Final hardening migration. Run after 002_hardening_calendar_drive_selection.sql.
-- Safe for an existing database; does not delete booking data.

alter table packages alter column duration_minutes drop not null;
alter table packages alter column min_people drop not null;
alter table bookings add column if not exists duration_minutes_snapshot integer;
alter table bookings add column if not exists calendar_sync_status text not null default 'pending';
alter table bookings add column if not exists idempotency_key text;
create unique index if not exists uq_bookings_idempotency_key on bookings(idempotency_key) where idempotency_key is not null;

alter table calendar_sync add column if not exists processing_until timestamptz;

create table if not exists google_oauth_states (
  state_hash text primary key,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

-- Do not invent limits that the business source did not specify.
update packages
set min_people = null, updated_at = now()
where slug in ('pas-foto-tanpa-print','prewedding-bronze','prewedding-silver','prewedding-gold','prewedding-platinum');

-- Keep the atomic booking-code counter ahead of all existing numeric suffixes.
insert into booking_daily_sequences(booking_date,next_value)
select booking_date, coalesce(max(substring(booking_code from '([0-9]+)$')::integer),0)+1
from bookings
where booking_code ~ '[0-9]+$'
group by booking_date
on conflict (booking_date) do update
set next_value = greatest(booking_daily_sequences.next_value, excluded.next_value);

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

  -- Insert a placeholder atomically. A concurrent retry with the same key waits
  -- on the unique index, then reads the committed booking instead of duplicating it.
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

  end_min := split_part(p_start_time, ':', 1)::integer * 60
            + split_part(p_start_time, ':', 2)::integer
            + p_duration_minutes;
  if end_min > 24*60 then raise exception 'INVALID_END_TIME'; end if;
  end_time_str := lpad((end_min/60)::text,2,'0') || ':' || lpad((end_min%60)::text,2,'0');

  if exists(
    select 1 from bookings
    where booking_date=p_booking_date
      and booking_status!='Cancelled'
      and start_time < end_time_str and end_time > p_start_time
  ) or exists(
    select 1 from blocked_slots
    where date=p_booking_date
      and start_time < end_time_str and end_time > p_start_time
  ) then raise exception 'SLOT_TAKEN'; end if;

  insert into booking_daily_sequences(booking_date,next_value)
    values(p_booking_date,2)
    on conflict(booking_date)
    do update set next_value=booking_daily_sequences.next_value+1
    returning next_value-1 into seq_no;

  insert into bookings(
    booking_code,customer_name,whatsapp,email,package_id,package_name_snapshot,category_snapshot,
    pricing_type_snapshot,base_price_snapshot,duration_minutes_snapshot,additional_person_fee_snapshot,
    included_people_snapshot,people_count,additional_people_charged,total_price,booking_date,start_time,
    end_time,timezone,photo_upload_permission,payment_status,booking_status,idempotency_key
  ) values(
    'KAIA-'||to_char(p_booking_date,'YYMMDD')||'-'||lpad(seq_no::text,3,'0'),
    p_customer_name,p_whatsapp,p_email,p_package_id,p_package_name,p_category,p_pricing_type,p_base_price,
    p_duration_minutes,p_additional_person_fee,p_included_people,p_people_count,p_additional_people_charged,
    p_total_price,p_booking_date,p_start_time,end_time_str,'Asia/Jakarta',p_photo_upload_permission,'Unpaid','Pending',
    p_idempotency_key
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
  update calendar_sync
  set status='processing',
      attempt_token=gen_random_uuid(),
      processing_until=now()+interval '5 minutes',
      updated_at=now()
  where booking_id=p_booking_id
    and (status in ('pending','failed') or (status='processing' and processing_until < now()))
  returning * into r;
  return r;
end;
$$ language plpgsql;

-- FINAL SECURITY HARDENING
-- Backend uses the Supabase service role; public/anon clients must not execute
-- booking or sync RPCs directly. Remove the legacy create_booking overload.
drop function if exists create_booking(
  text,text,text,text,bigint,text,text,text,integer,integer,integer,integer,integer,integer,date,text,text,text
);

revoke all on function create_booking(
  text,text,text,text,bigint,text,text,text,integer,integer,integer,integer,integer,integer,date,text,text,text
) from public, anon, authenticated;

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

