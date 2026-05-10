create table if not exists public.emergency_contacts (
  id bigint generated always as identity primary key,
  user_id text not null,
  name text not null,
  phone_number text not null,
  username text,
  profile_photo_path text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.emergency_contacts
  add column if not exists user_id text;

alter table public.emergency_contacts
  add column if not exists id bigint;

create sequence if not exists public.emergency_contacts_id_seq;

alter table public.emergency_contacts
  alter column id set default nextval('public.emergency_contacts_id_seq');

update public.emergency_contacts
set id = nextval('public.emergency_contacts_id_seq')
where id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'emergency_contacts_pkey'
      and conrelid = 'public.emergency_contacts'::regclass
  ) then
    alter table public.emergency_contacts
      add constraint emergency_contacts_pkey primary key (id);
  end if;
end
$$;

alter table public.emergency_contacts
  add column if not exists name text;

alter table public.emergency_contacts
  add column if not exists phone_number text;

alter table public.emergency_contacts
  add column if not exists username text;

alter table public.emergency_contacts
  add column if not exists profile_photo_path text;

alter table public.emergency_contacts
  add column if not exists is_primary boolean;

alter table public.emergency_contacts
  add column if not exists created_at timestamptz default now();

alter table public.emergency_contacts
  add column if not exists updated_at timestamptz default now();

update public.emergency_contacts
set is_primary = false
where is_primary is null;

alter table public.emergency_contacts
  alter column is_primary set default false;

create index if not exists emergency_contacts_user_id_idx
  on public.emergency_contacts (user_id);

create unique index if not exists emergency_contacts_id_unique_idx
  on public.emergency_contacts (id);

create or replace function public.touch_emergency_contacts_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_emergency_contacts_updated_at on public.emergency_contacts;

create trigger trg_emergency_contacts_updated_at
before update on public.emergency_contacts
for each row
execute function public.touch_emergency_contacts_updated_at();

alter table public.emergency_contacts enable row level security;

-- RLS: users can only read their own emergency contacts
drop policy if exists emergency_contacts_select on public.emergency_contacts;
create policy emergency_contacts_select
on public.emergency_contacts
for select
using (auth.uid()::text = user_id);

-- RLS: users can only insert contacts for themselves
drop policy if exists emergency_contacts_insert on public.emergency_contacts;
create policy emergency_contacts_insert
on public.emergency_contacts
for insert
with check (
  auth.uid()::text = user_id
  and coalesce(length(trim(user_id)), 0) > 0
);

-- RLS: users can only update their own contacts
drop policy if exists emergency_contacts_update on public.emergency_contacts;
create policy emergency_contacts_update
on public.emergency_contacts
for update
using (auth.uid()::text = user_id)
with check (auth.uid()::text = user_id);

-- RLS: users can only delete their own contacts
drop policy if exists emergency_contacts_delete on public.emergency_contacts;
create policy emergency_contacts_delete
on public.emergency_contacts
for delete
using (auth.uid()::text = user_id);
