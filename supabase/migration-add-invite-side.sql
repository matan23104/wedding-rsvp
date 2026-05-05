-- Run once in Supabase SQL Editor (existing projects).
-- Adds invite_side for groom vs bride Bit link + admin breakdown.

alter table public.guests
  add column if not exists invite_side text not null default 'groom';

alter table public.guests
  drop constraint if exists guests_invite_side_check;

alter table public.guests
  add constraint guests_invite_side_check
  check (invite_side in ('groom', 'bride'));

update public.guests set invite_side = 'groom' where invite_side is null or invite_side = '';

-- Required because return type/OUT columns changed between versions.
drop function if exists public.get_guest_by_token(text);

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
    g.invite_side,
    g.rsvp_status,
    g.guests_count,
    g.notes,
    g.responded_at,
    g.created_at
  from public.guests g
  where g.token = p_token
  limit 1;
$$;

grant execute on function public.get_guest_by_token(text) to anon, authenticated;

notify pgrst, 'reload schema';
