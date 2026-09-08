-- Audit finding: Housekeeping's own create-staff-account Edge Function had
-- no way to tell whether a hotel_id is bridged to a Core property. Its
-- authorization gate (guest_requests_staff_manage_allowed, defined
-- alongside the guest_requests migrations in this same project) is already
-- correctly Core-permission-derived, but that only decides *who* may create
-- an account -- not whether creating a Housekeeping-local account for this
-- hotel is the right operation at all once a property is embedded in
-- Hotsflow. Team is the sole intended source of truth for identities on an
-- embedded property (see the Team directory migrations); this lets that
-- Edge Function refuse to create a parallel, Team-invisible local identity
-- for a hotel that has been mapped to a Core property, no matter who asks.
--
-- Deliberately unscoped by permission (unlike
-- guest_requests_legacy_hotel_for_property): this leaks nothing sensitive,
-- just a boolean, so any authenticated caller may ask "is this hotel_id
-- already on Hotsflow?" without first proving they can access it.

create or replace function legacy_hotel_is_embedded(p_hotel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from legacy_property_mapping where legacy_hotel_id = p_hotel_id
  );
$$;

revoke all on function legacy_hotel_is_embedded(uuid) from public;
grant execute on function legacy_hotel_is_embedded(uuid) to authenticated;

comment on function legacy_hotel_is_embedded(uuid) is
  'True when this legacy hotels.id has been bridged to a Core property via legacy_property_mapping -- i.e. account creation for it must go through Hotsflow Team, not a module''s own local flow.';
