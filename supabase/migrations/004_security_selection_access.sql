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

revoke all on function submit_photo_selection(bigint,bigint[],text,text) from public, anon, authenticated;
