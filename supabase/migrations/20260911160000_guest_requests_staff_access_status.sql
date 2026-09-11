begin;

-- Read-only counterpart to grant-housekeeping-access's own lookup logic:
-- lets the Team UI show whether a member currently has a Housekeeping
-- profile *before* rendering a toggle, instead of the toggle always
-- starting from an unknown/blank state. Mirrors the same
-- has_permission + guest_requests_legacy_hotel_for_property resolution
-- the Edge Function already does, as a plain read the frontend can call
-- directly (via the authenticated caller's own session, not a
-- service-role round trip) -- same auth.uid()-dependency reasoning that
-- required calling guest_requests_legacy_hotel_for_property via caller,
-- not admin, in the Edge Function (see that fix's own commit).
create or replace function guest_requests_staff_access_status(p_membership_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select sp.active
      from memberships m
      join staff_profiles sp
        on sp.auth_user_id = m.profile_id
        and sp.hotel_id = guest_requests_legacy_hotel_for_property(m.property_id)
      where m.id = p_membership_id
        and has_permission(m.property_id, 'core.staff.manage')
    ),
    false
  );
$$;

revoke all on function guest_requests_staff_access_status(uuid) from public;
grant execute on function guest_requests_staff_access_status(uuid) to authenticated;

comment on function guest_requests_staff_access_status(uuid) is
  'Whether the given membership currently has an active Housekeeping (guest_requests) staff profile at its property''s mapped legacy hotel. False (never null) when unmapped, not entitled, the caller lacks core.staff.manage, or no profile exists -- a read-only companion to grant-housekeeping-access.';

commit;
