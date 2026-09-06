-- Expose the transitional property -> legacy hotel mapping to authenticated
-- shell/module clients without granting direct table access.
--
-- This remains a Guest Requests compatibility concern: callers must both
-- have Core access to the property and an enabled guest_requests entitlement.
-- The opaque legacy hotel id is then safe to use as the module's runtime
-- scope while operational tables still carry hotel_id.

begin;

create or replace function guest_requests_legacy_hotel_for_property(p_property_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.legacy_hotel_id
  from legacy_property_mapping m
  where m.platform_property_id = p_property_id
    and has_property_access(p_property_id)
    and has_module(p_property_id, 'guest_requests')
  limit 1;
$$;

revoke all on function guest_requests_legacy_hotel_for_property(uuid) from public;
grant execute on function guest_requests_legacy_hotel_for_property(uuid) to authenticated;

comment on function guest_requests_legacy_hotel_for_property(uuid) is
  'Guest Requests runtime adapter: returns the legacy hotels.id mapped to an accessible, entitled Core property; otherwise null.';

commit;
