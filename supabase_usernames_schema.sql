-- Run this in Supabase SQL editor before using username flow.

create table if not exists public.usernames (
  uid text primary key,
  username text not null unique,
  created_at timestamptz not null default now(),
  constraint usernames_format_check
    check (username ~ '^[a-z0-9._]{3,24}$')
);

create unique index if not exists usernames_username_unique_idx
  on public.usernames (username);

alter table public.usernames enable row level security;

-- RLS: anyone authenticated can look up usernames (needed for search)
drop policy if exists usernames_select on public.usernames;
create policy usernames_select
  on public.usernames
  for select
  using (true);

-- RLS: users can only claim a username for their own uid
drop policy if exists usernames_insert on public.usernames;
create policy usernames_insert
  on public.usernames
  for insert
  with check (auth.uid()::text = uid);
