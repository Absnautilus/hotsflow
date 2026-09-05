-- PR0 — scope the legacy `hotels_select_master` compatibility policy to the
-- organization that owns each mapped hotel.
--
-- Fase 2 redefined current_staff_is_master() to mean "this active staff user
-- has at least one active organization_admin membership". The legacy policy
-- below previously used that boolean as a global bypass, which meant an
-- organization_admin of Org A could see hotel rows mapped to Org B as soon as
-- multiple organizations existed.
--
-- Keep current_staff_is_master() unchanged because other compatibility call
-- sites still rely on its no-argument/global contract. Instead, scope this
-- one row-level policy by the Core role rank covering the property mapped to
-- the hotel row. current_actor_role_rank(property_id) is Core-derived and
-- only returns rank 40 here when the caller has organization_admin authority
-- over that property's organization. The extra current_staff_is_master()
-- condition preserves the legacy staff_profiles.active dual gate.

begin;

drop policy hotels_select_master on hotels;
create policy hotels_select_master on hotels for select to authenticated
  using (
    current_staff_is_master()
    and current_actor_role_rank(guest_requests_property_for_hotel(id)) = 40
  );

commit;
