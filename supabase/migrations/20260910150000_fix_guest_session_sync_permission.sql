-- public.sync_guest_sessions_on_stay_change() was defined without SECURITY
-- DEFINER (20260827120000_guest_requests_init.sql), so its internal writes
-- to public.guest_requests_guest_sessions run as the calling role
-- (authenticated) instead of the function owner. That table deliberately
-- has RLS enabled with zero policies and no grant to authenticated at all
-- (see 20260827120200_guest_requests_rls.sql's comment: "reachable only
-- through the SECURITY DEFINER functions") and 20260827122500 explicitly
-- revokes all privileges on it from anon/authenticated/public -- so the
-- trigger's own UPDATE has always failed with "permission denied for
-- table guest_requests_guest_sessions", aborting the entire stays update.
--
-- Every checkout, checkout extension ("Estendi"), and deactivation updates
-- stays.status or stays.check_out_at, firing this trigger -- so this has
-- broken those three actions since the trigger was introduced. It went
-- unnoticed because nothing checked for or surfaced the resulting error
-- until later client-side fixes started doing so.
--
-- Confirmed empirically (not just by documentation) on a local Postgres 16
-- instance before writing this migration: a role with no EXECUTE grant on
-- an already-attached trigger function still fires that trigger normally
-- -- Postgres does not check the invoking role's EXECUTE privilege on a
-- trigger function at trigger-fire time, only whether that role can
-- perform the triggering DML on the table the trigger is attached to. This
-- means revoking EXECUTE below is pure defense-in-depth (closing off any
-- direct ad hoc call to this function) and cannot break the trigger's
-- ability to fire for ordinary stays updates.
--
-- SECURITY DEFINER makes the internal writes run as the function's owner
-- (postgres), who does hold full privileges on
-- public.guest_requests_guest_sessions -- the same pattern every other
-- privileged helper in this schema already uses (current_staff_hotel(),
-- guest_login(), etc.). search_path is pinned to '' (rather than the
-- schema-qualified 'public' used elsewhere in this file) as the stricter,
-- unambiguous option: every relation reference inside the function body is
-- therefore written out fully-qualified as public.guest_requests_guest_sessions,
-- so there is no reliance on search_path resolution at all.
create or replace function public.sync_guest_sessions_on_stay_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status <> 'active' then
    update public.guest_requests_guest_sessions set revoked_at = now()
      where stay_id = new.id and revoked_at is null;
  elsif new.check_out_at <> old.check_out_at then
    if new.check_out_at < old.check_out_at then
      update public.guest_requests_guest_sessions set revoked_at = now()
        where stay_id = new.id and revoked_at is null and expires_at > new.check_out_at;
    end if;
    update public.guest_requests_guest_sessions set expires_at = new.check_out_at
      where stay_id = new.id and revoked_at is null;
  end if;
  return new;
end;
$$;

-- The trigger itself (stays_sync_guest_sessions, created in
-- 20260827120000_guest_requests_init.sql) already points at this function
-- by name and needs no changes -- CREATE OR REPLACE FUNCTION preserves the
-- function's OID, so the existing trigger keeps resolving to the new body
-- automatically.

-- Defense-in-depth only (see comment above): nobody is expected to call
-- this function directly, only the trigger manager invokes it. Function
-- owner remains postgres, unchanged by CREATE OR REPLACE FUNCTION.
revoke execute on function public.sync_guest_sessions_on_stay_change() from public, anon, authenticated;
