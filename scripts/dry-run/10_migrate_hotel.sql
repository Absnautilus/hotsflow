-- Production Data Migration — actual scoped migration logic (plan §D,
-- corrected here: the plan's original §D omitted the `insert into hotels`
-- step entirely, a real gap this dry-run script surfaced while being
-- written — see the plan's dry-run findings). Single transaction (plan
-- §I.1); idempotent via explicit id preservation + ON CONFLICT DO NOTHING,
-- so a rerun against already-migrated state is safe (dry-run item 11).
--
-- Requires three psql variables, set by the orchestrator from the Auth
-- phase's captured new_auth_id values (plan §B.1.2 remapping — no
-- explicit id requested from GoTrue, whatever it assigns is used here):
--   -v admin_id=<uuid> -v opa_id=<uuid> -v opb_id=<uuid>
\set ON_ERROR_STOP on
begin;

-- STEP 0 (new — see header) — the hotel row itself. This must exist
-- before legacy_property_mapping can reference it.
insert into hotels (id, name, timezone, active)
values ('99999999-0000-0000-0000-000000000001', 'Hotel Sample E2E Dry-Run', 'Europe/Rome', true)
on conflict (id) do nothing;

-- STEP 1 — organization + property + legacy_property_mapping, this hotel only.
do $$
declare
  v_org_id uuid;
  v_property_id uuid;
  v_module_id uuid;
  v_role_admin uuid;
  v_role_op uuid;
begin
  if exists (select 1 from legacy_property_mapping where legacy_hotel_id = '99999999-0000-0000-0000-000000000001') then
    select platform_property_id into v_property_id from legacy_property_mapping where legacy_hotel_id = '99999999-0000-0000-0000-000000000001';
  else
    insert into organizations (name, slug) values ('Hotel Sample E2E Dry-Run', 'hotel-sample-e2e-dryrun')
      returning id into v_org_id;
    insert into properties (organization_id, name, slug, timezone, status)
      values (v_org_id, 'Hotel Sample E2E Dry-Run', 'hotel-sample-e2e-dryrun', 'Europe/Rome', 'active')
      returning id into v_property_id;
    insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
      values ('99999999-0000-0000-0000-000000000001', v_property_id);
  end if;

  -- STEP 2 — entitlement, this property only.
  select id into v_module_id from modules where slug = 'guest_requests';
  insert into property_modules (property_id, module_id, enabled)
    values (v_property_id, v_module_id, true)
    on conflict (property_id, module_id) do nothing;

  -- STEP 3 — profiles + memberships for the 3 remapped Auth users.
  select id into v_role_admin from roles where slug = 'property_admin';
  select id into v_role_op from roles where slug = 'receptionist';

  insert into profiles (id, full_name) values (:'admin_id', 'Dry Run Admin') on conflict (id) do nothing;
  insert into profiles (id, full_name) values (:'opa_id', 'Dry Run Operatore A') on conflict (id) do nothing;
  insert into profiles (id, full_name) values (:'opb_id', 'Dry Run Operatore B') on conflict (id) do nothing;

  if not exists (select 1 from memberships where profile_id = :'admin_id' and property_id = v_property_id) then
    insert into memberships (profile_id, property_id, role_id, status) values (:'admin_id', v_property_id, v_role_admin, 'active');
  end if;
  if not exists (select 1 from memberships where profile_id = :'opa_id' and property_id = v_property_id) then
    insert into memberships (profile_id, property_id, role_id, status) values (:'opa_id', v_property_id, v_role_op, 'active');
  end if;
  if not exists (select 1 from memberships where profile_id = :'opb_id' and property_id = v_property_id) then
    insert into memberships (profile_id, property_id, role_id, status) values (:'opb_id', v_property_id, v_role_op, 'active');
  end if;
end $$;

-- STEP 4 — staff_profiles (module-local, id preserved from legacy_dryrun).
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username)
select id, hotel_id, case id
    when '99999999-0000-0000-0000-0000000000a1' then :'admin_id'::uuid
    when '99999999-0000-0000-0000-0000000000a2' then :'opa_id'::uuid
    when '99999999-0000-0000-0000-0000000000a3' then :'opb_id'::uuid
  end,
  name, role::staff_role, department::department, active, login_username
from legacy_dryrun.staff_profiles
on conflict (id) do nothing;

-- STEP 5 — config tables: full migration, own ids preserved.
insert into rooms (id, hotel_id, room_number, active)
  select id, hotel_id, room_number, active from legacy_dryrun.rooms
  on conflict (id) do nothing;

insert into request_categories (id, hotel_id, name, department, sort_order)
  select id, hotel_id, name, department::department, sort_order from legacy_dryrun.request_categories
  on conflict (id) do nothing;

insert into request_types (id, category_id, name, allows_quantity)
  select id, category_id, name, allows_quantity from legacy_dryrun.request_types
  on conflict (id) do nothing;

-- STEP 6 — stays: active only (plan §E).
insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status)
  select id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status::stay_status
  from legacy_dryrun.stays where status = 'active'
  on conflict (id) do nothing;

-- STEP 7 — guest_requests: open only (plan §E).
insert into guest_requests (id, hotel_id, stay_id, room_number, request_type_id, status, assigned_department)
  select gr.id, gr.hotel_id, gr.stay_id, r.room_number, gr.request_type_id, gr.status::request_status, gr.assigned_department::department
  from legacy_dryrun.guest_requests gr
  join legacy_dryrun.stays s on s.id = gr.stay_id
  join legacy_dryrun.rooms r on r.id = s.room_id
  where gr.status in ('requested','in_progress') and gr.archived_at is null
  on conflict (id) do nothing;

commit;
