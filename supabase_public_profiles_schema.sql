create table if not exists public.public_profiles (
  uid text primary key,
  username text not null unique,
  display_name text,
  phone_number text,
  photo_path text,
  date_of_birth text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_profiles_username_format
    check (username ~ '^[a-z0-9._]{3,24}$')
);

alter table public.public_profiles
add column if not exists photo_path text;

alter table public.public_profiles
add column if not exists date_of_birth text;

create or replace function public.touch_public_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_public_profiles_updated_at on public.public_profiles;

create trigger trg_public_profiles_updated_at
before update on public.public_profiles
for each row
execute function public.touch_public_profiles_updated_at();

alter table public.public_profiles enable row level security;

-- RLS: only authenticated users can read public profiles.
-- NOTE: phone_number and date_of_birth are sensitive PII.
-- Application queries should only select (uid, username, display_name, photo_path)
-- for other users. The full profile should only be fetched for the current user.
-- Consider moving phone_number and date_of_birth to a separate private_profiles
-- table with strict owner-only RLS if stronger isolation is needed.
drop policy if exists public_profiles_select on public.public_profiles;
create policy public_profiles_select
on public.public_profiles
for select
using (auth.role() = 'authenticated');

-- RLS: users can only insert their own profile
drop policy if exists public_profiles_insert on public.public_profiles;
create policy public_profiles_insert
on public.public_profiles
for insert
with check (auth.uid()::text = uid);

-- RLS: users can only update their own profile
drop policy if exists public_profiles_update on public.public_profiles;
create policy public_profiles_update
on public.public_profiles
for update
using (auth.uid()::text = uid)
with check (auth.uid()::text = uid);

-- RLS: users can only delete their own profile
drop policy if exists public_profiles_delete on public.public_profiles;
create policy public_profiles_delete
on public.public_profiles
for delete
using (auth.uid()::text = uid);
