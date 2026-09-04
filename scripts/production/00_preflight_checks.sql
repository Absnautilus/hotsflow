-- Production migration -- PRE-FLIGHT, legacy side. Run FIRST, over the
-- read-only connection, before anything else. Every check here is
-- read-only and safe to print (no row-level data, no PII). Requires
-- -v legacy_hotel_id=<uuid>. The orchestrator aborts before VALIDATION
-- if any assertion below fails.
\set ON_ERROR_STOP on

\echo '--- write-privilege check: every column below must be false ---'
select
  has_table_privilege(current_user, 'public.hotels', 'INSERT') as hotels_insert,
  has_table_privilege(current_user, 'public.hotels', 'UPDATE') as hotels_update,
  has_table_privilege(current_user, 'public.hotels', 'DELETE') as hotels_delete,
  has_table_privilege(current_user, 'public.staff_profiles', 'INSERT') as staff_profiles_insert,
  has_table_privilege(current_user, 'public.rooms', 'INSERT') as rooms_insert,
  has_table_privilege(current_user, 'public.stays', 'INSERT') as stays_insert,
  has_table_privilege(current_user, 'public.request_categories', 'INSERT') as request_categories_insert,
  has_table_privilege(current_user, 'public.request_types', 'INSERT') as request_types_insert,
  has_table_privilege(current_user, 'public.guest_requests', 'INSERT') as guest_requests_insert;

\echo '--- session-level read-only enforcement (must be "on") ---'
select current_setting('transaction_read_only') as transaction_read_only;

\echo '--- expected hotel present, exact id match (must be exactly 1) ---'
select count(*) as expected_hotel_present from hotels where id = :'legacy_hotel_id';

\echo '--- no unexpected additional hotel in scope (must be 0 rows) ---'
select id from hotels where id != :'legacy_hotel_id';
