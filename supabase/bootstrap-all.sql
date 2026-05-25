-- One-shot bootstrap for a fresh Supabase project.
-- Creates required tables, defaults, RLS policies, and public RPC helpers.
-- Run this file once in Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

-- ================================================================
-- Tables
-- ================================================================
create table if not exists public.guests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  category text not null default 'אתר ציבורי',
  invite_side text not null default 'groom' check (invite_side in ('groom', 'bride')),
  token text not null unique default encode(gen_random_bytes(8), 'hex'),
  rsvp_status text not null default 'not_invited' check (rsvp_status in ('not_invited', 'pending', 'coming', 'not_coming')),
  guests_count integer not null default 1,
  notes text,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

alter table public.guests
  drop constraint if exists guests_guests_count_check;

alter table public.guests
  add constraint guests_guests_count_check
  check (guests_count between 0 and 10);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  guest_name text not null,
  question_text text not null,
  status text not null default 'pending' check (status in ('pending', 'answered')),
  answer_text text,
  created_at timestamptz not null default now()
);

create index if not exists idx_guests_created_at on public.guests(created_at desc);
create index if not exists idx_guests_token on public.guests(token);
create index if not exists idx_questions_created_at on public.questions(created_at desc);
create index if not exists idx_questions_status on public.questions(status);

alter table public.guests add column if not exists initial_invite_sent_at timestamptz;
alter table public.guests add column if not exists gift_reminder_sent_at timestamptz;
alter table public.guests add column if not exists rsvp_override_until timestamptz;

create table if not exists public.event_settings (
  id integer primary key check (id = 1),
  rsvp_deadline_enabled boolean not null default false,
  rsvp_deadline_at timestamptz
);

insert into public.event_settings (id, rsvp_deadline_enabled, rsvp_deadline_at)
values (1, false, null)
on conflict (id) do nothing;

-- ================================================================
-- RLS
-- ================================================================
alter table public.guests enable row level security;
alter table public.questions enable row level security;
alter table public.event_settings enable row level security;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) in (
    'ic850536@gmail.com',
    'matan.hdmi@gmail.com'
  );
$$;

drop policy if exists "guests_admin_all" on public.guests;
drop policy if exists "questions_admin_all" on public.questions;

create policy "guests_admin_all"
on public.guests
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

create policy "questions_admin_all"
on public.questions
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "event_settings_admin_all" on public.event_settings;
create policy "event_settings_admin_all"
on public.event_settings
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

-- ================================================================
-- Public RPC functions (for guest page)
-- ================================================================
create or replace function public.get_guest_by_token(p_token text)
returns table(
  id uuid,
  token text,
  full_name text,
  phone text,
  category text,
  invite_side text,
  rsvp_status text,
  guests_count integer,
  notes text,
  responded_at timestamptz,
  created_at timestamptz,
  initial_invite_sent_at timestamptz,
  gift_reminder_sent_at timestamptz,
  rsvp_override_until timestamptz,
  rsvp_deadline_enabled boolean,
  rsvp_deadline_at timestamptz,
  rsvp_closed boolean
)
language sql
security definer
set search_path = public
as $$
  with cleaned as (
    select lower(trim(coalesce(p_token, ''))) as token
  )
  select
    g.id,
    g.token,
    g.full_name,
    g.phone,
    g.category,
    g.invite_side,
    g.rsvp_status,
    g.guests_count,
    g.notes,
    g.responded_at,
    g.created_at,
    g.initial_invite_sent_at,
    g.gift_reminder_sent_at,
    g.rsvp_override_until,
    coalesce(
      (select es0.rsvp_deadline_enabled from public.event_settings es0 where es0.id = 1),
      false
    ) as rsvp_deadline_enabled,
    (select es0.rsvp_deadline_at from public.event_settings es0 where es0.id = 1) as rsvp_deadline_at,
    (
      case
        when not coalesce(
          (select es0.rsvp_deadline_enabled from public.event_settings es0 where es0.id = 1),
          false
        )
          or (select es0.rsvp_deadline_at from public.event_settings es0 where es0.id = 1) is null then false
        when now() <= (select es0.rsvp_deadline_at from public.event_settings es0 where es0.id = 1) then false
        when g.rsvp_override_until is not null and now() <= g.rsvp_override_until then false
        else true
      end
    ) as rsvp_closed
  from public.guests g
  join cleaned c on true
  where c.token ~ '^[0-9a-f]{16}$'
    and g.token = c.token
  limit 1;
$$;

create or replace function public.submit_rsvp_by_token(
  p_token text,
  p_rsvp_status text,
  p_guests_count integer,
  p_notes text default null
)
returns public.guests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.guests;
  v_status text;
  v_guests_count integer;
  v_token text;
  v_enabled boolean;
  v_deadline timestamptz;
  v_override timestamptz;
begin
  v_token := lower(trim(coalesce(p_token, '')));
  if v_token !~ '^[0-9a-f]{16}$' then
    raise exception 'Invalid token format';
  end if;

  select coalesce(es.rsvp_deadline_enabled, false), es.rsvp_deadline_at
  into v_enabled, v_deadline
  from public.event_settings es
  where es.id = 1;

  select g.rsvp_override_until into v_override
  from public.guests g
  where g.token = v_token
  limit 1;

  if coalesce(v_enabled, false) and v_deadline is not null and now() > v_deadline then
    if v_override is null or now() > v_override then
      raise exception 'RSVP deadline has passed';
    end if;
  end if;

  v_status := lower(trim(coalesce(p_rsvp_status, '')));
  if v_status not in ('coming', 'not_coming') then
    raise exception 'Invalid RSVP status';
  end if;

  if v_status = 'not_coming' then
    v_guests_count := 0;
  else
    v_guests_count := least(greatest(coalesce(p_guests_count, 1), 0), 8);
  end if;

  update public.guests g
  set
    rsvp_status = v_status,
    guests_count = v_guests_count,
    notes = coalesce(p_notes, g.notes),
    responded_at = now()
  where g.token = v_token
  returning g.* into v_row;

  if v_row.id is null then
    raise exception 'Guest not found';
  end if;

  return v_row;
end;
$$;

create or replace function public.submit_rsvp_manual(
  p_full_name text,
  p_phone text,
  p_rsvp_status text,
  p_guests_count integer,
  p_category text default 'אתר ציבורי'
)
returns public.guests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.guests;
begin
  if coalesce(length(trim(p_full_name)), 0) < 2 then
    raise exception 'Full name is required';
  end if;

  if lower(trim(coalesce(p_rsvp_status, ''))) not in ('not_invited', 'pending', 'coming', 'not_coming') then
    raise exception 'Invalid RSVP status';
  end if;

  insert into public.guests (
    full_name,
    phone,
    category,
    rsvp_status,
    guests_count
  )
  values (
    p_full_name,
    nullif(p_phone, ''),
    coalesce(nullif(p_category, ''), 'אתר ציבורי'),
    lower(trim(p_rsvp_status)),
    least(greatest(coalesce(p_guests_count, 1), 0), 8)
  )
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.submit_question_public(
  p_guest_name text,
  p_question_text text
)
returns public.questions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.questions;
begin
  if coalesce(length(trim(p_guest_name)), 0) < 2 then
    raise exception 'Guest name is required';
  end if;

  if coalesce(length(trim(p_question_text)), 0) < 2 then
    raise exception 'Question text is required';
  end if;

  insert into public.questions (
    guest_name,
    question_text
  )
  values (
    p_guest_name,
    p_question_text
  )
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.admin_set_rsvp_deadline(
  p_enabled boolean,
  p_deadline_local text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ts timestamptz;
begin
  if not public.is_admin_user() then
    raise exception 'Unauthorized';
  end if;

  if coalesce(p_enabled, false) then
    if coalesce(length(trim(coalesce(p_deadline_local, ''))), 0) = 0 then
      raise exception 'Deadline datetime required when RSVP deadline is enabled';
    end if;
    begin
      v_ts := (trim(p_deadline_local)::timestamp AT TIME ZONE 'Asia/Jerusalem');
    exception when others then
      raise exception 'Invalid deadline datetime (expected YYYY-MM-DD HH:MI in Jerusalem)';
    end;
    update public.event_settings e
    set rsvp_deadline_enabled = true, rsvp_deadline_at = v_ts
    where e.id = 1;
  else
    update public.event_settings e
    set rsvp_deadline_enabled = false, rsvp_deadline_at = null
    where e.id = 1;
  end if;
end;
$$;

create or replace function public.admin_grant_rsvp_override(p_guest_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_until timestamptz := now() + interval '12 hours';
  v_gid uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Unauthorized';
  end if;

  update public.guests g
  set rsvp_override_until = v_until
  where g.id = p_guest_id
  returning g.id into v_gid;

  if v_gid is null then
    raise exception 'Guest not found';
  end if;

  return v_until;
end;
$$;

create or replace function public.admin_patch_guest_send_status(
  p_guest_id uuid,
  p_kind text,
  p_mark_sent boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Unauthorized';
  end if;

  if lower(trim(coalesce(p_kind, ''))) not in ('invite', 'gift') then
    raise exception 'Invalid send kind';
  end if;

  if lower(trim(coalesce(p_kind, ''))) = 'invite' then
    update public.guests g
    set
      initial_invite_sent_at = case when p_mark_sent then now() else null end,
      rsvp_status = case
        when p_mark_sent and g.rsvp_status = 'not_invited' then 'pending'
        when not p_mark_sent and g.rsvp_status = 'pending' then 'not_invited'
        else g.rsvp_status
      end
    where g.id = p_guest_id;
  else
    update public.guests g
    set gift_reminder_sent_at = case when p_mark_sent then now() else null end
    where g.id = p_guest_id;
  end if;

  if not found then
    raise exception 'Guest not found';
  end if;
end;
$$;

create or replace function public.admin_bulk_patch_guest_send_status(
  p_guest_ids uuid[],
  p_kind text,
  p_mark_sent boolean
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  if not public.is_admin_user() then
    raise exception 'Unauthorized';
  end if;

  if p_guest_ids is null or array_length(p_guest_ids, 1) is null then
    return 0;
  end if;

  if lower(trim(coalesce(p_kind, ''))) not in ('invite', 'gift') then
    raise exception 'Invalid send kind';
  end if;

  if lower(trim(coalesce(p_kind, ''))) = 'invite' then
    update public.guests g
    set
      initial_invite_sent_at = case when p_mark_sent then now() else null end,
      rsvp_status = case
        when p_mark_sent and g.rsvp_status = 'not_invited' then 'pending'
        when not p_mark_sent and g.rsvp_status = 'pending' then 'not_invited'
        else g.rsvp_status
      end
    where g.id = any(p_guest_ids);
  else
    update public.guests g
    set gift_reminder_sent_at = case when p_mark_sent then now() else null end
    where g.id = any(p_guest_ids);
  end if;

  get diagnostics v_n = row_count;
  return coalesce(v_n, 0);
end;
$$;

create or replace function public.admin_regenerate_guest_token(p_guest_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tok text;
begin
  if not public.is_admin_user() then
    raise exception 'Unauthorized';
  end if;

  update public.guests g
  set token = encode(gen_random_bytes(8), 'hex')
  where g.id = p_guest_id
  returning g.token into v_tok;

  if v_tok is null then
    raise exception 'Guest not found';
  end if;

  return v_tok;
end;
$$;

grant execute on function public.get_guest_by_token(text) to anon, authenticated;
grant execute on function public.submit_rsvp_by_token(text, text, integer, text) to anon, authenticated;
grant execute on function public.submit_rsvp_manual(text, text, text, integer, text) to anon, authenticated;
grant execute on function public.submit_question_public(text, text) to anon, authenticated;
grant execute on function public.admin_set_rsvp_deadline(boolean, text) to authenticated;
grant execute on function public.admin_grant_rsvp_override(uuid) to authenticated;
grant execute on function public.admin_patch_guest_send_status(uuid, text, boolean) to authenticated;
grant execute on function public.admin_bulk_patch_guest_send_status(uuid[], text, boolean) to authenticated;
grant execute on function public.admin_regenerate_guest_token(uuid) to authenticated;

revoke execute on function public.get_guest_by_token(text) from public;
revoke execute on function public.submit_rsvp_by_token(text, text, integer, text) from public;
revoke execute on function public.submit_rsvp_manual(text, text, text, integer, text) from public;
revoke execute on function public.submit_question_public(text, text) from public;
revoke execute on function public.admin_set_rsvp_deadline(boolean, text) from public;
revoke execute on function public.admin_grant_rsvp_override(uuid) from public;
revoke execute on function public.admin_patch_guest_send_status(uuid, text, boolean) from public;
revoke execute on function public.admin_bulk_patch_guest_send_status(uuid[], text, boolean) from public;
revoke execute on function public.admin_regenerate_guest_token(uuid) from public;

revoke execute on function public.get_guest_by_token(text) from authenticated;
revoke execute on function public.submit_rsvp_by_token(text, text, integer, text) from authenticated;
revoke execute on function public.submit_rsvp_manual(text, text, text, integer, text) from authenticated;
revoke execute on function public.submit_question_public(text, text) from authenticated;
revoke execute on function public.admin_set_rsvp_deadline(boolean, text) from anon;
revoke execute on function public.admin_grant_rsvp_override(uuid) from anon;
revoke execute on function public.admin_patch_guest_send_status(uuid, text, boolean) from anon;
revoke execute on function public.admin_bulk_patch_guest_send_status(uuid[], text, boolean) from anon;
revoke execute on function public.admin_regenerate_guest_token(uuid) from anon;

notify pgrst, 'reload schema';

commit;
