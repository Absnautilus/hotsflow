-- Generic, Core-level per-device push notification subscription store,
-- backing the "Notifiche" toggle in Settings (apps/web). Deliberately
-- independent of Housekeeping's own staff_profiles-scoped
-- push_subscriptions (20260827121200_guest_requests_push_notifications),
-- which backs a different, module-specific on-duty alert flow -- this
-- table is owned by `profiles`, so it works for any Hotsflow user
-- regardless of module access. No event is wired to send through it yet;
-- today it only backs the toggle's subscribe/unsubscribe.

begin;

create table device_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

create index device_push_subscriptions_profile_idx on device_push_subscriptions(profile_id);

alter table device_push_subscriptions enable row level security;

create policy device_push_subscriptions_owner on device_push_subscriptions for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

grant select, insert, update, delete on device_push_subscriptions to authenticated;

commit;
