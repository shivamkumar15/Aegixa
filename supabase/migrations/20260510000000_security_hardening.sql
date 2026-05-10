-- 1. Mutual Contact Verification (Sender must have recipient in contacts)
drop policy if exists sos_alerts_insert on public.sos_alerts;
create policy sos_alerts_insert
on public.sos_alerts
for insert
with check (
  auth.uid()::text = sender_user_id
  and coalesce(length(trim(sender_user_id)), 0) > 0
  and exists (
    select 1 from public.emergency_contacts c
    where c.user_id = auth.uid()::text
    and c.username = recipient_username
  )
);

-- 2. Server-Side Rate Limiting for SOS Alerts (30 seconds)
create or replace function public.check_sos_rate_limit()
returns trigger
language plpgsql
as $$
declare
  last_alert_time timestamptz;
begin
  -- Get the most recent alert from this user
  select triggered_at into last_alert_time
  from public.sos_alerts
  where sender_user_id = auth.uid()::text
  order by triggered_at desc
  limit 1;

  if last_alert_time is not null and (now() - last_alert_time) < interval '30 seconds' then
    raise exception 'Rate limit exceeded: You must wait 30 seconds between SOS alerts.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sos_rate_limit on public.sos_alerts;
create trigger trg_sos_rate_limit
before insert on public.sos_alerts
for each row
execute function public.check_sos_rate_limit();
