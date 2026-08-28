-- Fase 2 Step 7 — DEFINER HYGIENE (static audit).
-- prosecdef, PUBLIC/anon residual EXECUTE, search_path, ownership, policy
-- target roles, and table/column grants, for every function/policy Step 6
-- touched, plus a full-catalog scan proving PUBLIC/anon EXECUTE on a
-- guest_requests SECURITY DEFINER function exists ONLY on the functions
-- that are deliberately guest-facing, and that the pre-existing,
-- out-of-scope gap (current_staff_department, current_staff_manages_
-- front_desk, and 2 trigger-adjacent functions never touched by Step 6)
-- is exactly the known set — not a growing one.
begin;
create extension if not exists pgtap;
select plan(17);

-- ### the 8 functions Step 6 created or redefined ###
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname in ('current_staff_hotel','current_staff_role','current_staff_is_master',
       'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
       'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration')),
  8,
  'all 8 Step-6 functions are SECURITY DEFINER (prosecdef = true)'
);

select is(
  (select count(*)::int from information_schema.role_routine_grants g
   where g.specific_schema = 'public' and g.grantee in ('PUBLIC', 'anon')
     and g.routine_name in ('current_staff_hotel','current_staff_role','current_staff_is_master',
       'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
       'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration')),
  0,
  'none of the 8 Step-6 functions has any residual PUBLIC or anon EXECUTE grant'
);

select is(
  (select count(*)::int from information_schema.role_routine_grants g
   where g.specific_schema = 'public' and g.grantee = 'authenticated'
     and g.routine_name in ('current_staff_hotel','current_staff_role','current_staff_is_master',
       'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
       'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration')),
  8,
  'all 8 have exactly the intended authenticated EXECUTE grant'
);

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname in ('current_staff_hotel','current_staff_role','current_staff_is_master',
       'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
       'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration')
     and p.proconfig::text like '%search_path=public%'),
  8,
  'all 8 have search_path pinned to public (SECURITY DEFINER search_path-hijacking hygiene)'
);

select is(
  (select count(distinct proowner)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('current_staff_hotel','current_staff_role','current_staff_is_master',
       'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
       'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration')),
  1,
  'all 8 share a single, consistent owner (the migration-applying role) -- no ownership drift'
);

-- ### the 2 policies Step 6 rewrote ###
select is(
  (select array_agg(distinct r::text order by r::text) from pg_policies, unnest(roles) as r
   where schemaname = 'public' and tablename = 'staff_profiles'
     and policyname in ('staff_profiles_select_scoped', 'staff_profiles_write_scoped')),
  array['authenticated'],
  'both rewritten staff_profiles policies target authenticated only -- no anon, no public'
);

-- ### staff_profiles.role write lockdown ###
select is(
  (select count(*)::int from information_schema.role_column_grants
   where table_name = 'staff_profiles' and column_name = 'role'
     and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE')),
  0,
  'authenticated has no INSERT or UPDATE grant on staff_profiles.role at all'
);
select ok(
  (select count(*)::int from information_schema.role_column_grants
   where table_name = 'staff_profiles' and column_name = 'department'
     and grantee = 'authenticated' and privilege_type = 'UPDATE') > 0,
  'sanity: authenticated still has UPDATE on staff_profiles.department -- the lockdown is column-specific to role, not a blanket revoke'
);

-- ### full-catalog scan: PUBLIC/anon EXECUTE on a guest_requests SECURITY
-- DEFINER function must exist ONLY for the deliberately guest-facing ones.
-- (guest_stay_from_token was already revoked from PUBLIC in the original
-- 0002; the other 4 keep a PUBLIC grant alongside their explicit anon
-- grant -- harmless since PUBLIC already includes anon and every one of
-- them is a self-contained token validator, but recorded here precisely
-- rather than assumed.)
select set_eq(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and exists (
         select 1 from information_schema.role_routine_grants g
         where g.specific_schema = 'public' and g.routine_name = p.proname and g.grantee in ('PUBLIC', 'anon')
       )
       and p.proname in ('current_staff_hotel','current_staff_role','current_staff_department',
         'current_staff_is_master','current_staff_manages_front_desk',
         'guest_requests_property_for_hotel','guest_requests_staff_roster_visible',
         'guest_requests_staff_manage_allowed','get_pms_integration_status','save_pms_integration',
         'guest_login','create_guest_request','list_my_requests','cancel_my_request',
         'guest_stay_from_token','guest_stay_info','set_on_duty') $$,
  $$ values ('guest_login'), ('create_guest_request'), ('list_my_requests'), ('cancel_my_request'),
            ('guest_stay_info'), ('current_staff_department'), ('current_staff_manages_front_desk'),
            ('set_on_duty') $$,
  'PUBLIC/anon EXECUTE on a SECURITY DEFINER guest_requests function exists ONLY on the known set: '
  || 'the 5 deliberately guest-facing RPCs, plus the 3 already-documented, out-of-scope pre-existing gaps '
  || '(current_staff_department, current_staff_manages_front_desk, set_on_duty) -- nothing new'
);

-- the 3 known, documented, out-of-scope gaps specifically -- confirmed
-- unchanged (Step 6 never touched them, on purpose)
select ok(
  (select prosecdef from pg_proc where proname = 'current_staff_department' and pronamespace = 'public'::regnamespace),
  'current_staff_department is still SECURITY DEFINER (untouched, as documented)'
);
select is(
  (select count(*)::int from information_schema.role_routine_grants
   where specific_schema = 'public' and routine_name = 'current_staff_department' and grantee = 'PUBLIC'),
  1,
  'current_staff_department still has the pre-existing PUBLIC grant -- a known, documented, out-of-scope gap, not a new regression'
);
select is(
  (select count(*)::int from information_schema.role_routine_grants
   where specific_schema = 'public' and routine_name = 'current_staff_manages_front_desk' and grantee = 'PUBLIC'),
  1,
  'current_staff_manages_front_desk: same, still open, still out of scope'
);

-- guest_stay_from_token: internal-only, PUBLIC explicitly revoked back in
-- the original 0002_functions.sql -- confirm that revoke is still in
-- effect (no anon/authenticated grant either)
select is(
  (select count(*)::int from information_schema.role_routine_grants
   where specific_schema = 'public' and routine_name = 'guest_stay_from_token'
     and grantee in ('authenticated', 'anon', 'PUBLIC')),
  0,
  'guest_stay_from_token has no authenticated/anon/PUBLIC grant -- internal-only, as originally designed '
  || '(the owner''s own implicit grant row is excluded here, not a privilege anyone else has)'
);

-- ### legacy_property_mapping and guest_requests_guest_sessions: zero
-- client grants of any kind (both RLS-enabled, zero policies) ###
select is(
  (select count(*)::int from information_schema.role_table_grants
   where table_name in ('legacy_property_mapping', 'guest_requests_guest_sessions')
     and grantee in ('authenticated', 'anon', 'PUBLIC')),
  0,
  'legacy_property_mapping and guest_requests_guest_sessions have zero grants to authenticated/anon/PUBLIC'
);

-- ### the 3 new permissions/role_permissions rows from Step 6 are exactly
-- what was approved -- no more, no less ###
select is(
  (select array_agg(r.slug order by r.slug) from role_permissions rp
   join roles r on r.id = rp.role_id
   join permissions p on p.id = rp.permission_id
   where p.slug = 'guest_requests.pms.manage'),
  array['organization_admin', 'property_admin'],
  'guest_requests.pms.manage is granted to exactly property_admin and organization_admin, nothing else'
);
select is(
  (select count(*)::int from permissions where slug = 'guest_requests.pms.manage'),
  1,
  'guest_requests.pms.manage exists exactly once (idempotent bootstrap, no duplicate)'
);
select is(
  (select m.slug from permissions p join modules m on m.id = p.module_id where p.slug = 'guest_requests.pms.manage'),
  'guest_requests',
  'guest_requests.pms.manage is correctly module-owned by guest_requests (entitlement applies automatically)'
);

select * from finish();
rollback;
