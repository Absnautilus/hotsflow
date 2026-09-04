-- Production migration -- VALIDATION, legacy side. Same anomaly set
-- already used manually for cutover-readiness pre-flight and in the
-- rehearsal -- generalized here with -v legacy_hotel_id=<uuid> instead of
-- the real id hardcoded, so the exact same file serves the real run and
-- the disposable E2E test. Every result is a count or an enum label --
-- no PII, safe to print. If any count below is nonzero, the orchestrator
-- stops before EXPORT.
--
-- Deliberately no `create temporary table` here: the E2E test's first
-- run against a genuinely read-only session (default_transaction_read_only
-- = on, see setup_readonly_role.sql) proved that CREATE TABLE AS -- even
-- temporary -- is itself rejected as a write. Every check below runs as
-- a plain SELECT over a subquery instead; the same UNION ALL block
-- appears twice (once to print the breakdown, once to sum it) since a
-- WITH-clause CTE only lives for the single statement it's attached to
-- and can't be reused across two separate psql statements.
--
-- The staff_profiles_missing_email check reads
-- public.migration_readonly_auth_lookup, NOT auth.users directly (see
-- create_migration_auth_lookup.sql / 02_export_legacy.sql) --
-- migration_readonly holds no privilege on the auth schema at all. This
-- was the exact bug PRE-FLIGHT #14's first E2E re-run caught: this file
-- still referenced auth.users directly after the rest of the redesign
-- had already moved off it.
\set ON_ERROR_STOP on

\echo '--- anomaly checks (every "n" must be 0) ---'
select * from (
  select 'staff_profiles.name null' as check_name, count(*) as n from staff_profiles where hotel_id = :'legacy_hotel_id' and (name is null or trim(name) = '')
  union all select 'staff_profiles.auth_user_id null', count(*) from staff_profiles where hotel_id = :'legacy_hotel_id' and auth_user_id is null
  union all select 'rooms.room_number null', count(*) from rooms where hotel_id = :'legacy_hotel_id' and (room_number is null or trim(room_number) = '')
  union all select 'stays.guest_last_name null', count(*) from stays where hotel_id = :'legacy_hotel_id' and (guest_last_name is null or trim(guest_last_name) = '')
  union all select 'guest_requests.request_type_id null', count(*) from guest_requests where hotel_id = :'legacy_hotel_id' and request_type_id is null
  union all select 'staff_profiles.auth_user_id dupes', count(*) - count(distinct auth_user_id) from staff_profiles where hotel_id = :'legacy_hotel_id'
  union all select 'staff_profiles.login_username dupes', count(login_username) - count(distinct login_username) from staff_profiles where hotel_id = :'legacy_hotel_id'
  union all select 'rooms (hotel_id,room_number) dupes', count(*) - count(distinct (hotel_id, room_number)) from rooms where hotel_id = :'legacy_hotel_id'
  union all select 'stays_missing_room', count(*) from stays s where s.hotel_id = :'legacy_hotel_id' and not exists (select 1 from rooms r where r.id = s.room_id)
  union all select 'requests_missing_type', count(*) from guest_requests gr where gr.hotel_id = :'legacy_hotel_id' and not exists (select 1 from request_types rt where rt.id = gr.request_type_id)
  union all select 'requests_missing_stay_when_set', count(*) from guest_requests gr where gr.hotel_id = :'legacy_hotel_id' and gr.stay_id is not null and not exists (select 1 from stays s where s.id = gr.stay_id)
  union all select 'types_missing_category', count(*) from request_types rt join request_categories rc2 on rc2.id = rt.category_id where rc2.hotel_id = :'legacy_hotel_id' and not exists (select 1 from request_categories rc where rc.id = rt.category_id)
  union all select 'staff_profiles.role invalid', count(*) from staff_profiles where hotel_id = :'legacy_hotel_id' and role not in ('admin','operatore','master')
  union all select 'stays.status invalid', count(*) from stays where hotel_id = :'legacy_hotel_id' and status not in ('active','closed','cancelled')
  union all select 'guest_requests.status invalid', count(*) from guest_requests where hotel_id = :'legacy_hotel_id' and status not in ('requested','in_progress','completed','cancelled')
  union all select 'bad_stay_range', count(*) from stays where hotel_id = :'legacy_hotel_id' and check_out_at <= check_in_at
  union all select 'stay_room_hotel_mismatch', count(*) from stays s join rooms r on r.id = s.room_id where s.hotel_id = :'legacy_hotel_id' and r.hotel_id <> s.hotel_id
  union all select 'staff_profiles_missing_email', count(*) from staff_profiles sp where sp.hotel_id = :'legacy_hotel_id' and not exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
) checks
order by check_name;

\echo '--- ANOMALY_COUNT (must be 0 for the orchestrator to proceed) ---'
select coalesce(sum(n), 0) as anomaly_count from (
  select 'staff_profiles.name null' as check_name, count(*) as n from staff_profiles where hotel_id = :'legacy_hotel_id' and (name is null or trim(name) = '')
  union all select 'staff_profiles.auth_user_id null', count(*) from staff_profiles where hotel_id = :'legacy_hotel_id' and auth_user_id is null
  union all select 'rooms.room_number null', count(*) from rooms where hotel_id = :'legacy_hotel_id' and (room_number is null or trim(room_number) = '')
  union all select 'stays.guest_last_name null', count(*) from stays where hotel_id = :'legacy_hotel_id' and (guest_last_name is null or trim(guest_last_name) = '')
  union all select 'guest_requests.request_type_id null', count(*) from guest_requests where hotel_id = :'legacy_hotel_id' and request_type_id is null
  union all select 'staff_profiles.auth_user_id dupes', count(*) - count(distinct auth_user_id) from staff_profiles where hotel_id = :'legacy_hotel_id'
  union all select 'staff_profiles.login_username dupes', count(login_username) - count(distinct login_username) from staff_profiles where hotel_id = :'legacy_hotel_id'
  union all select 'rooms (hotel_id,room_number) dupes', count(*) - count(distinct (hotel_id, room_number)) from rooms where hotel_id = :'legacy_hotel_id'
  union all select 'stays_missing_room', count(*) from stays s where s.hotel_id = :'legacy_hotel_id' and not exists (select 1 from rooms r where r.id = s.room_id)
  union all select 'requests_missing_type', count(*) from guest_requests gr where gr.hotel_id = :'legacy_hotel_id' and not exists (select 1 from request_types rt where rt.id = gr.request_type_id)
  union all select 'requests_missing_stay_when_set', count(*) from guest_requests gr where gr.hotel_id = :'legacy_hotel_id' and gr.stay_id is not null and not exists (select 1 from stays s where s.id = gr.stay_id)
  union all select 'types_missing_category', count(*) from request_types rt join request_categories rc2 on rc2.id = rt.category_id where rc2.hotel_id = :'legacy_hotel_id' and not exists (select 1 from request_categories rc where rc.id = rt.category_id)
  union all select 'staff_profiles.role invalid', count(*) from staff_profiles where hotel_id = :'legacy_hotel_id' and role not in ('admin','operatore','master')
  union all select 'stays.status invalid', count(*) from stays where hotel_id = :'legacy_hotel_id' and status not in ('active','closed','cancelled')
  union all select 'guest_requests.status invalid', count(*) from guest_requests where hotel_id = :'legacy_hotel_id' and status not in ('requested','in_progress','completed','cancelled')
  union all select 'bad_stay_range', count(*) from stays where hotel_id = :'legacy_hotel_id' and check_out_at <= check_in_at
  union all select 'stay_room_hotel_mismatch', count(*) from stays s join rooms r on r.id = s.room_id where s.hotel_id = :'legacy_hotel_id' and r.hotel_id <> s.hotel_id
  union all select 'staff_profiles_missing_email', count(*) from staff_profiles sp where sp.hotel_id = :'legacy_hotel_id' and not exists (select 1 from public.migration_readonly_auth_lookup mal where mal.staff_profile_id = sp.id and mal.email is not null)
) checks \gset

\echo :anomaly_count
