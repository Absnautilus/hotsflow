-- Fase 2 Step 5 — guest_requests module entitlement.
--
-- For every property in legacy_property_mapping: a property_modules row for
-- guest_requests, enabled=true. property_modules is commercial entitlement,
-- not authorization (0013_entitlement_hardening.sql already revoked
-- insert/update from `authenticated` — this migration adds no grant, it
-- only runs as the migration/superuser role, same as backfill_staff_identity
-- and backfill_legacy_property_mapping). No new permission slug, no RLS
-- change, no touch to memberships/staff_profiles/guest flow.

begin;

-- Re-invokable, idempotent, not a client RPC.
create function backfill_guest_requests_entitlement() returns void
language plpgsql as $$
declare
  m record;
  v_module_id uuid;
  v_existing_enabled boolean;
begin
  select id into v_module_id from modules where slug = 'guest_requests';

  for m in select platform_property_id from legacy_property_mapping loop
    select enabled into v_existing_enabled
      from property_modules
      where property_id = m.platform_property_id and module_id = v_module_id;

    if not found then
      insert into property_modules (property_id, module_id, enabled)
        values (m.platform_property_id, v_module_id, true);
    elsif v_existing_enabled = false then
      -- Ambiguous: could be "not yet bootstrapped" or a deliberate,
      -- service-role decision to disable this property's access. Silently
      -- flipping it to true would override a real commercial decision this
      -- migration has no business making — stop and surface it instead.
      raise exception
        'property % already has a guest_requests entitlement row with enabled=false — not silently overwritten, resolve manually before re-running this backfill',
        m.platform_property_id;
    end if;
    -- v_existing_enabled = true: already correctly bootstrapped, left
    -- entirely as-is (plan/settings untouched).
  end loop;
end;
$$;

revoke all on function backfill_guest_requests_entitlement() from public;

select backfill_guest_requests_entitlement();

commit;
