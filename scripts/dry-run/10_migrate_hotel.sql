-- Production Data Migration — the actual scoped migration logic (plan §D).
-- Generalized (this version) so the dry-run AND the rehearsal run the
-- exact same file against different data — no second implementation, per
-- explicit instruction. Reads from a fixed staging schema, `legacy_source`,
-- populated beforehand by whichever seed script matches the run (synthetic
-- for the dry-run, real-anonymized for the rehearsal). Single transaction
-- (plan §I.1); idempotent via explicit id preservation + ON CONFLICT DO
-- NOTHING, except when an Auth identity already has a target module-local
-- staff_profile: in that case the existing target staff_profile id is reused
-- and legacy staff FK references are remapped to it.
--
-- Requires:
--   -v hotel_id=<uuid> -v hotel_name='<text>' -v hotel_slug='<text>'
-- and a temporary/permanent table `auth_remap(legacy_auth_user_id uuid primary key,
-- new_auth_user_id uuid not null)` already created and populated by the
-- orchestrator's Auth phase (plan §B.1.2 remapping — no explicit id
-- requested from GoTrue) BEFORE this script runs. Data-driven (loops over
-- however many staff rows legacy_source.staff_profiles has), not a fixed
-- count — the rehearsal surfaced a `master` role the dry-run never
-- exercised (see the rehearsal findings), which a hardcoded 3-variable
-- version couldn't have handled without editing the script per hotel.
\set ON_ERROR_STOP on
begin;

-- STEP 0 — the hotel row itself. Must exist before legacy_property_mapping
-- can reference it (missing from the plan's original §D — found while
-- writing the dry-run script, fixed there and in the plan document).
insert into hotels (id, name, timezone, active)
values (:'hotel_id', :'hotel_name', 'Europe/Rome', true)
on conflict (id) do nothing;

-- STEP 1 — organization + property + legacy_property_mapping, this hotel
-- only. One statement, idempotent via CTEs (insert only if not already
-- mapped, otherwise reuse the existing property) -- avoids psql variable
-- substitution inside a do $$ ... $$ body entirely (that's what broke the
-- first version of this script: dollar-quoted text is opaque to psql's
-- :'name' substitution).
with existing as (
  select platform_property_id from legacy_property_mapping where legacy_hotel_id = :'hotel_id'
),
new_org as (
  insert into organizations (name, slug)
  select :'hotel_name', :'hotel_slug'
  where not exists (select 1 from existing)
  returning id
),
new_property as (
  insert into properties (organization_id, name, slug, timezone, status)
  select id, :'hotel_name', :'hotel_slug', 'Europe/Rome', 'active' from new_org
  returning id, organization_id
),
new_mapping as (
  insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  select :'hotel_id', id from new_property
  returning platform_property_id
)
select coalesce((select platform_property_id from existing), (select id from new_property)) as property_id \gset

select organization_id from properties where id = :'property_id' \gset

-- STEP 2 — entitlement, this property only.
select id as module_id from modules where slug = 'guest_requests' \gset
insert into property_modules (property_id, module_id, enabled)
  values (:'property_id', :'module_id', true)
  on conflict (property_id, module_id) do nothing;

select id as role_admin_id from roles where slug = 'property_admin' \gset
select id as role_op_id from roles where slug = 'receptionist' \gset
select id as role_org_admin_id from roles where slug = 'organization_admin' \gset

-- STEP 3 — profiles for every remapped Auth user this hotel has.
insert into profiles (id, full_name)
select ar.new_auth_user_id, ls.name
from legacy_source.staff_profiles ls
join auth_remap ar on ar.legacy_auth_user_id = ls.id
where ls.hotel_id = :'hotel_id'
on conflict (id) do nothing;

-- STEP 4 — memberships: admin/operatore -> property-scoped;
-- master -> organization-scoped (org-wide reach) -- the role the dry-run
-- never exercised, added here after the rehearsal's real data surfaced it.
insert into memberships (profile_id, property_id, role_id, status)
select ar.new_auth_user_id, :'property_id',
  case ls.role when 'admin' then :'role_admin_id'::uuid else :'role_op_id'::uuid end,
  case when ls.active then 'active' else 'suspended' end
from legacy_source.staff_profiles ls
join auth_remap ar on ar.legacy_auth_user_id = ls.id
where ls.hotel_id = :'hotel_id' and ls.role in ('admin','operatore')
on conflict (profile_id, property_id) where property_id is not null do nothing;

insert into memberships (profile_id, organization_id, role_id, status)
select ar.new_auth_user_id, :'organization_id', :'role_org_admin_id'::uuid,
  case when ls.active then 'active' else 'suspended' end
from legacy_source.staff_profiles ls
join auth_remap ar on ar.legacy_auth_user_id = ls.id
where ls.hotel_id = :'hotel_id' and ls.role = 'master'
on conflict (profile_id, organization_id) where organization_id is not null do nothing;

-- STEP 5 — staff_profiles itself (module-local).
-- Normally the legacy staff id is preserved. If an Auth identity already has
-- a target staff_profile (for example an established Hotsflow/demo identity),
-- reuse that row instead of violating staff_profiles.auth_user_id uniqueness.
-- Keep a transaction-local legacy->target staff id map so downstream staff FKs
-- are rewritten consistently.
create temp table staff_profile_remap (
  legacy_staff_profile_id uuid primary key,
  target_staff_profile_id uuid not null unique
) on commit drop;

insert into staff_profile_remap (legacy_staff_profile_id, target_staff_profile_id)
select
  ls.id,
  coalesce(existing_sp.id, ls.id)
from legacy_source.staff_profiles ls
join auth_remap ar on ar.legacy_auth_user_id = ls.id
left join staff_profiles existing_sp on existing_sp.auth_user_id = ar.new_auth_user_id
where ls.hotel_id = :'hotel_id';

-- Re-home an already-existing module-local staff_profile onto the real hotel
-- and synchronize its legacy module-local fields. Its target id is preserved
-- because other target-side references may already point to it.
update staff_profiles sp
set
  hotel_id = ls.hotel_id,
  name = ls.name,
  role = ls.role::staff_role,
  department = ls.department::department,
  active = ls.active,
  login_username = ls.login_username
from legacy_source.staff_profiles ls
join staff_profile_remap sr on sr.legacy_staff_profile_id = ls.id
where sp.id = sr.target_staff_profile_id
  and sr.target_staff_profile_id <> sr.legacy_staff_profile_id
  and ls.hotel_id = :'hotel_id';

-- New identities still preserve the legacy staff id exactly.
insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username)
select sr.target_staff_profile_id, ls.hotel_id, ar.new_auth_user_id, ls.name, ls.role::staff_role,
       ls.department::department, ls.active, ls.login_username
from legacy_source.staff_profiles ls
join auth_remap ar on ar.legacy_auth_user_id = ls.id
join staff_profile_remap sr on sr.legacy_staff_profile_id = ls.id
where ls.hotel_id = :'hotel_id'
on conflict (id) do nothing;

-- STEP 6 — config tables: full migration, own ids preserved.
insert into rooms (id, hotel_id, room_number, active)
  select id, hotel_id, room_number, active from legacy_source.rooms where hotel_id = :'hotel_id'
  on conflict (id) do nothing;

insert into request_categories (id, hotel_id, name, department, icon, active, sort_order)
  select id, hotel_id, name, department::department, icon, active, sort_order
  from legacy_source.request_categories where hotel_id = :'hotel_id'
  on conflict (id) do nothing;

insert into request_types (id, category_id, name, description, allows_quantity, active, sort_order, available_quantity)
  select rt.id, rt.category_id, rt.name, rt.description, rt.allows_quantity, rt.active, rt.sort_order, rt.available_quantity
  from legacy_source.request_types rt
  join legacy_source.request_categories rc on rc.id = rt.category_id
  where rc.hotel_id = :'hotel_id'
  on conflict (id) do nothing;

-- STEP 7 — stays: active only (plan §E).
insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status, source, external_stay_id, created_by)
  select s.id, s.hotel_id, s.room_id, s.guest_last_name, s.check_in_at, s.check_out_at, s.status::stay_status,
    coalesce(s.source, 'manual')::stay_source, s.external_stay_id,
    coalesce(sr_created.target_staff_profile_id, s.created_by)
  from legacy_source.stays s
  left join staff_profile_remap sr_created on sr_created.legacy_staff_profile_id = s.created_by
  where s.hotel_id = :'hotel_id' and s.status = 'active'
  on conflict (id) do nothing;

-- STEP 8 — guest_requests: open only (plan §E).
insert into guest_requests (id, hotel_id, stay_id, room_number, request_type_id, quantity, status, assigned_department, accepted_by, created_at, accepted_at, completed_at, priority, created_by_staff, archived_at, returned_at)
  select gr.id, gr.hotel_id, gr.stay_id, gr.room_number, gr.request_type_id, gr.quantity,
    gr.status::request_status, gr.assigned_department::department,
    coalesce(sr_accepted.target_staff_profile_id, gr.accepted_by),
    coalesce(gr.created_at, now()), gr.accepted_at, gr.completed_at, gr.priority,
    coalesce(sr_created.target_staff_profile_id, gr.created_by_staff),
    gr.archived_at, gr.returned_at
  from legacy_source.guest_requests gr
  left join staff_profile_remap sr_accepted on sr_accepted.legacy_staff_profile_id = gr.accepted_by
  left join staff_profile_remap sr_created on sr_created.legacy_staff_profile_id = gr.created_by_staff
  where gr.hotel_id = :'hotel_id' and gr.status in ('requested','in_progress') and gr.archived_at is null
  on conflict (id) do nothing;

commit;
