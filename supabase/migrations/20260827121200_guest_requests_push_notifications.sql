-- Push notifications for new guest requests, gated to staff who are
-- currently on duty.
--
-- on_duty is self-toggled by the staff member (from the dashboard header),
-- but staff_profiles_write_scoped (0006) only lets admin/master write staff
-- rows — an operatore can't update their own row directly. Rather than widen
-- that policy (which would let an operatore edit their own role/department
-- too), set_on_duty() is a narrow SECURITY DEFINER RPC that only ever
-- touches the caller's own on_duty column.
--
-- push_subscriptions holds one row per browser/device a staff member has
-- subscribed from; RLS scopes all access to rows owned by the caller's own
-- staff_profiles row. The notify-new-request Edge Function reads across all
-- of them using the service-role key, so it isn't bound by this RLS.

begin;

alter table staff_profiles add column on_duty boolean not null default false;

create function set_on_duty(p_on_duty boolean) returns void
language sql security definer set search_path = public as $$
  update staff_profiles set on_duty = p_on_duty where auth_user_id = auth.uid();
$$;

create table push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff_profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

create index push_subscriptions_staff_idx on push_subscriptions(staff_id);

alter table push_subscriptions enable row level security;

create policy push_subscriptions_owner on push_subscriptions for all to authenticated
  using (staff_id in (select id from staff_profiles where auth_user_id = auth.uid()))
  with check (staff_id in (select id from staff_profiles where auth_user_id = auth.uid()));

grant select, insert, update, delete on push_subscriptions to authenticated;

commit;
