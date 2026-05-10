create table if not exists public.push_notification_tokens (
  id bigint generated always as identity primary key,
  user_id text not null,
  fcm_token text not null,
  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint push_notification_tokens_fcm_token_unique unique (fcm_token)
);

create index if not exists push_notification_tokens_user_id_idx
  on public.push_notification_tokens (user_id);

create or replace function public.touch_push_notification_tokens_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_push_notification_tokens_updated_at
on public.push_notification_tokens;

create trigger trg_push_notification_tokens_updated_at
before update on public.push_notification_tokens
for each row
execute function public.touch_push_notification_tokens_updated_at();

alter table public.push_notification_tokens enable row level security;

-- RLS: users can only read their own tokens
drop policy if exists push_notification_tokens_select on public.push_notification_tokens;
create policy push_notification_tokens_select
on public.push_notification_tokens
for select
using (auth.uid()::text = user_id);

-- RLS: users can only insert tokens for themselves
drop policy if exists push_notification_tokens_insert on public.push_notification_tokens;
create policy push_notification_tokens_insert
on public.push_notification_tokens
for insert
with check (
  auth.uid()::text = user_id
  and coalesce(length(trim(user_id)), 0) > 0
  and coalesce(length(trim(fcm_token)), 0) > 0
);

-- RLS: users can only update their own tokens
drop policy if exists push_notification_tokens_update on public.push_notification_tokens;
create policy push_notification_tokens_update
on public.push_notification_tokens
for update
using (auth.uid()::text = user_id)
with check (
  auth.uid()::text = user_id
  and coalesce(length(trim(user_id)), 0) > 0
  and coalesce(length(trim(fcm_token)), 0) > 0
);

-- RLS: users can only delete their own tokens
drop policy if exists push_notification_tokens_delete on public.push_notification_tokens;
create policy push_notification_tokens_delete
on public.push_notification_tokens
for delete
using (auth.uid()::text = user_id);
