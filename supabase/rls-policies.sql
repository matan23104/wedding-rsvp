-- Wedding RSVP security hardening
-- Run in Supabase SQL Editor.
--
-- What this does:
-- 1) Enables strict RLS on guests/questions
-- 2) Lets public users RSVP only via safe RPC functions
-- 3) Lets authenticated users (admin) manage full data

begin;

-- -------------------------------------------------------------------
-- RLS
-- -------------------------------------------------------------------
alter table if exists public.guests enable row level security;
alter table if exists public.questions enable row level security;

-- Remove old policies if they exist
drop policy if exists "guests_admin_all" on public.guests;
drop policy if exists "questions_admin_all" on public.questions;

-- Authenticated users can do everything (for admin dashboard)
create policy "guests_admin_all"
on public.guests
for all
to authenticated
using (true)
with check (true);

create policy "questions_admin_all"
on public.questions
for all
to authenticated
using (true)
with check (true);

-- -------------------------------------------------------------------
-- Public RPC functions (SECURITY DEFINER)
-- -------------------------------------------------------------------
create or replace function public.get_guest_by_token(p_token text)
returns table(
  id uuid,
  token text,
  full_name text,
  phone text,
  category text,
  rsvp_status text,
  guests_count integer,
  notes text,
  responded_at timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    g.id,
    g.token,
    g.full_name,
    g.phone,
    g.category,
    g.rsvp_status,
    g.guests_count,
    g.notes,
    g.responded_at,
    g.created_at
  from public.guests g
  where g.token = p_token
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
begin
  update public.guests g
  set
    rsvp_status = p_rsvp_status,
    guests_count = greatest(coalesce(p_guests_count, 1), 0),
    notes = coalesce(p_notes, g.notes),
    responded_at = now()
  where g.token = p_token
  returning g.* into v_row;

  return v_row;
end;
$$;

create or replace function public.submit_rsvp_manual(
  p_full_name text,
  p_phone text,
  p_rsvp_status text,
  p_guests_count integer
)
returns public.guests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.guests;
begin
  insert into public.guests (
    full_name,
    phone,
    rsvp_status,
    guests_count
  )
  values (
    p_full_name,
    nullif(p_phone, ''),
    p_rsvp_status,
    greatest(coalesce(p_guests_count, 1), 0)
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

-- Grant execute to public API roles
grant execute on function public.get_guest_by_token(text) to anon, authenticated;
grant execute on function public.submit_rsvp_by_token(text, text, integer, text) to anon, authenticated;
grant execute on function public.submit_rsvp_manual(text, text, text, integer) to anon, authenticated;
grant execute on function public.submit_question_public(text, text) to anon, authenticated;

commit;
