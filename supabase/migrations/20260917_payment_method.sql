alter table public.bookings
add column if not exists payment_method text;

alter table public.bookings
drop constraint if exists bookings_payment_method_check;

alter table public.bookings
add constraint bookings_payment_method_check
check (
  payment_method is null
  or payment_method in ('cash', 'transfer', 'qris')
);

drop function if exists public.create_booking(
  text,text,text,text,text,bigint,text,text,text,
  integer,integer,integer,integer,integer,integer,integer,
  date,text,text
);

create or replace function public.create_booking(
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
  p_photo_upload_permission text,
  p_payment_method text
) returns public.bookings as $$
declare
  result public.bookings;
  seq_no integer;
  end_min integer;
  end_time_str text;
  existing_id bigint;
  request_hash_existing text;
begin
  if p_duration_minutes is null then raise exception 'DURATION_UNSPECIFIED'; end if;

  if p_payment_method is null
     or p_payment_method not in ('cash', 'transfer', 'qris') then
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_booking_date::text));

  insert into booking_idempotency(idempotency_key,request_hash,booking_id)
    values(p_idempotency_key,p_request_hash,null)
    on conflict(idempotency_key) do nothing;

  select bi.booking_id, bi.request_hash
    into existing_id, request_hash_existing
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

  end_time_str := lpad((end_min/60)::text,2,'0')
               || ':'
               || lpad((end_min%60)::text,2,'0');

  if exists(
    select 1 from bookings
    where booking_date=p_booking_date
      and booking_status!='Cancelled'
      and start_time < end_time_str
      and end_time > p_start_time
  ) or exists(
    select 1 from blocked_slots
    where date=p_booking_date
      and start_time < end_time_str
      and end_time > p_start_time
  ) then
    raise exception 'SLOT_TAKEN';
  end if;

  insert into booking_daily_sequences(booking_date,next_value)
    values(p_booking_date,2)
    on conflict(booking_date)
    do update set next_value=booking_daily_sequences.next_value+1
    returning next_value-1 into seq_no;

  insert into bookings(
    booking_code,customer_name,whatsapp,email,package_id,package_name_snapshot,
    category_snapshot,pricing_type_snapshot,base_price_snapshot,
    duration_minutes_snapshot,additional_person_fee_snapshot,included_people_snapshot,
    people_count,additional_people_charged,total_price,booking_date,start_time,end_time,
    timezone,photo_upload_permission,payment_method,payment_status,booking_status,idempotency_key
  ) values(
    'KAIA-'||to_char(p_booking_date,'YYMMDD')||'-'||lpad(seq_no::text,3,'0'),
    p_customer_name,p_whatsapp,p_email,p_package_id,p_package_name,p_category,
    p_pricing_type,p_base_price,p_duration_minutes,p_additional_person_fee,
    p_included_people,p_people_count,p_additional_people_charged,p_total_price,
    p_booking_date,p_start_time,end_time_str,'Asia/Jakarta',
    p_photo_upload_permission,p_payment_method,'Unpaid','Pending',p_idempotency_key
  ) returning * into result;

  update booking_idempotency
    set booking_id=result.id
    where idempotency_key=p_idempotency_key;

  insert into calendar_sync(booking_id,status)
    values(result.id,'pending')
    on conflict do nothing;

  return result;
end;
$$ language plpgsql security definer set search_path=public;

revoke all on function public.create_booking(
  text,text,text,text,text,bigint,text,text,text,
  integer,integer,integer,integer,integer,integer,integer,
  date,text,text,text
) from public, anon, authenticated;
