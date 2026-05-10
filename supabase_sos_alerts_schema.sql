create table if not exists public.sos_alerts (
  id bigint generated always as identity primary key,
  session_id text not null,
  sender_user_id text not null,
  sender_name text not null,
  sender_username text,
  sender_phone_number text,
  sender_photo_path text,
  recipient_user_id text not null,
  recipient_username text,
  contact_name text not null,
  contact_phone_number text not null,
  is_primary boolean not null default false,
  alert_message text not null,
  latitude double precision not null,
  longitude double precision not null,
  location_accuracy_meters double precision,
  status text not null default 'active'
    check (status in ('active', 'resolved')),
  voice_recording_url text,
  video_recording_url text,
  triggered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.sos_alerts
  add column if not exists voice_recording_url text;

alter table public.sos_alerts
  add column if not exists video_recording_url text;

create index if not exists sos_alerts_session_id_idx
  on public.sos_alerts (session_id);

create index if not exists sos_alerts_recipient_status_idx
  on public.sos_alerts (recipient_user_id, status, triggered_at desc);

create index if not exists sos_alerts_sender_status_idx
  on public.sos_alerts (sender_user_id, status, triggered_at desc);

create or replace function public.touch_sos_alerts_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_sos_alerts_updated_at on public.sos_alerts;

create trigger trg_sos_alerts_updated_at
before update on public.sos_alerts
for each row
execute function public.touch_sos_alerts_updated_at();

alter table public.sos_alerts enable row level security;

-- RLS: only the sender or recipient can read their own alerts
drop policy if exists sos_alerts_select on public.sos_alerts;
create policy sos_alerts_select
on public.sos_alerts
for select
using (
  auth.uid()::text = sender_user_id
  or auth.uid()::text = recipient_user_id
);

-- RLS: only authenticated user can insert, and sender_user_id must match their uid
drop policy if exists sos_alerts_insert on public.sos_alerts;
create policy sos_alerts_insert
on public.sos_alerts
for insert
with check (
  auth.uid()::text = sender_user_id
  and coalesce(length(trim(sender_user_id)), 0) > 0
);

-- RLS: only the sender can update their own alerts (e.g. resolve, add recordings)
drop policy if exists sos_alerts_update on public.sos_alerts;
create policy sos_alerts_update
on public.sos_alerts
for update
using (auth.uid()::text = sender_user_id)
with check (auth.uid()::text = sender_user_id);

-- RLS: only the sender can delete their own alerts
drop policy if exists sos_alerts_delete on public.sos_alerts;
create policy sos_alerts_delete
on public.sos_alerts
for delete
using (auth.uid()::text = sender_user_id);

-- Storage bucket: private (not public) - use signed URLs for access
insert into storage.buckets (id, name, public)
values ('sos-alert-recordings', 'sos-alert-recordings', false)
on conflict (id) do update
set public = false;

-- Storage RLS: only the owner can read recordings in their own folder
-- Files are stored at: {sender_user_id}/{session_id}/filename
drop policy if exists sos_alert_recordings_public_read on storage.objects;
drop policy if exists sos_alert_recordings_read on storage.objects;
create policy sos_alert_recordings_read
on storage.objects
for select
using (
  bucket_id = 'sos-alert-recordings'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Storage RLS: only authenticated users can upload to their own folder
drop policy if exists sos_alert_recordings_upload on storage.objects;
create policy sos_alert_recordings_upload
on storage.objects
for insert
with check (
  bucket_id = 'sos-alert-recordings'
  and auth.role() = 'authenticated'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Storage RLS: only the owner can update their own recordings
drop policy if exists sos_alert_recordings_update on storage.objects;
create policy sos_alert_recordings_update
on storage.objects
for update
using (
  bucket_id = 'sos-alert-recordings'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'sos-alert-recordings'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Storage RLS: only the owner can delete their own recordings
drop policy if exists sos_alert_recordings_delete on storage.objects;
create policy sos_alert_recordings_delete
on storage.objects
for delete
using (
  bucket_id = 'sos-alert-recordings'
  and (storage.foldername(name))[1] = auth.uid()::text
);
