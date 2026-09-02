-- Production Data Migration — reconciliation queries (plan §G), adapted
-- to the dry-run's synthetic hotel id. Plain psql run (not pgTAP), so
-- every SELECT's output is visible directly in the job log.
\pset border 2
\echo '--- row counts (target) ---'
select
  (select count(*) from hotels where id = '99999999-0000-0000-0000-000000000001') as hotels_migrated,
  (select count(*) from staff_profiles where hotel_id = '99999999-0000-0000-0000-000000000001') as staff_migrated,
  (select count(*) from rooms where hotel_id = '99999999-0000-0000-0000-000000000001') as rooms_migrated,
  (select count(*) from request_categories where hotel_id = '99999999-0000-0000-0000-000000000001') as categories_migrated,
  (select count(*) from request_types rt join request_categories rc on rc.id = rt.category_id where rc.hotel_id = '99999999-0000-0000-0000-000000000001') as types_migrated,
  (select count(*) from stays where hotel_id = '99999999-0000-0000-0000-000000000001') as stays_migrated,
  (select count(*) from guest_requests where hotel_id = '99999999-0000-0000-0000-000000000001') as requests_migrated;
\echo 'expected: hotels_migrated=1 staff_migrated=3 rooms_migrated=7 categories_migrated=6 types_migrated=12 stays_migrated=1 requests_migrated=2'

\echo '--- PK preservation (expect 0 dupes everywhere) ---'
select 'staff_profiles' as t, count(*) - count(distinct id) as dupes from staff_profiles where hotel_id = '99999999-0000-0000-0000-000000000001'
union all select 'stays', count(*) - count(distinct id) from stays where hotel_id = '99999999-0000-0000-0000-000000000001'
union all select 'guest_requests', count(*) - count(distinct id) from guest_requests where hotel_id = '99999999-0000-0000-0000-000000000001';

\echo '--- FK integrity (expect 0 everywhere) ---'
select 'stays_missing_room' as check_name, count(*) from stays s
  where s.hotel_id = '99999999-0000-0000-0000-000000000001'
  and not exists (select 1 from rooms r where r.id = s.room_id)
union all
select 'requests_missing_type', count(*) from guest_requests gr
  where gr.hotel_id = '99999999-0000-0000-0000-000000000001'
  and not exists (select 1 from request_types rt where rt.id = gr.request_type_id)
union all
select 'requests_missing_stay', count(*) from guest_requests gr
  where gr.hotel_id = '99999999-0000-0000-0000-000000000001' and gr.stay_id is not null
  and not exists (select 1 from stays s where s.id = gr.stay_id);

\echo '--- hotel -> property mapping (expect exactly 1 row) ---'
select h.id, h.name, m.platform_property_id, p.name as property_name, p.organization_id
from hotels h
join legacy_property_mapping m on m.legacy_hotel_id = h.id
join properties p on p.id = m.platform_property_id
where h.id = '99999999-0000-0000-0000-000000000001';

\echo '--- staff -> auth user -> membership chain (expect all true / >=1) ---'
select
  sp.id as staff_profile_id, sp.role,
  (au.id is not null) as auth_user_exists,
  (pr.id is not null) as profile_exists,
  (select count(*) from memberships m where m.profile_id = sp.auth_user_id) as membership_count
from staff_profiles sp
left join auth.users au on au.id = sp.auth_user_id
left join profiles pr on pr.id = sp.auth_user_id
where sp.hotel_id = '99999999-0000-0000-0000-000000000001';

\echo '--- entitlement (expect exactly 1 row, enabled=true) ---'
select pm.enabled from property_modules pm
join legacy_property_mapping m on m.platform_property_id = pm.property_id
join modules mod on mod.id = pm.module_id
where m.legacy_hotel_id = '99999999-0000-0000-0000-000000000001' and mod.slug = 'guest_requests';

\echo '--- active/suspended staff mapping consistency (expect equal) ---'
select
  (select count(*) from staff_profiles where hotel_id = '99999999-0000-0000-0000-000000000001' and active) as legacy_active,
  (select count(*) from memberships m join staff_profiles sp on sp.auth_user_id = m.profile_id
   where sp.hotel_id = '99999999-0000-0000-0000-000000000001' and m.status = 'active') as core_active;
