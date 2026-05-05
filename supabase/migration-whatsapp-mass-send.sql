-- Run once in Supabase SQL Editor.
-- Creates logging tables for WhatsApp mass sending campaigns.

create table if not exists public.message_campaigns (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('whatsapp')),
  mode text not null check (mode in ('invite', 'gift_reminder')),
  filter_category text,
  filter_side text check (filter_side in ('groom', 'bride')),
  only_confirmed boolean not null default false,
  dry_run boolean not null default false,
  total_targets integer not null default 0,
  total_sent integer not null default 0,
  total_failed integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.message_campaign_items (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.message_campaigns(id) on delete cascade,
  guest_id uuid references public.guests(id) on delete set null,
  phone text,
  status text not null check (status in ('queued', 'sent', 'failed', 'skipped')),
  provider_message_id text,
  provider_error text,
  payload jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_message_campaigns_created_at on public.message_campaigns(created_at desc);
create index if not exists idx_message_campaign_items_campaign on public.message_campaign_items(campaign_id);

alter table public.message_campaigns enable row level security;
alter table public.message_campaign_items enable row level security;

drop policy if exists "message_campaigns_admin_all" on public.message_campaigns;
drop policy if exists "message_campaign_items_admin_all" on public.message_campaign_items;

create policy "message_campaigns_admin_all"
on public.message_campaigns
for all
to authenticated
using (true)
with check (true);

create policy "message_campaign_items_admin_all"
on public.message_campaign_items
for all
to authenticated
using (true)
with check (true);
