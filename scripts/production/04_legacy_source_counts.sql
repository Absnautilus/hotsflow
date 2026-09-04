-- Production migration -- legacy row counts for the reconciliation
-- source->target comparison. Counts only (no row content), safe to
-- print. Scoped to exactly the 7 tables the read-only role can see --
-- pms_integrations/guest_sessions/guest_login_attempts/push_subscriptions
-- are deliberately out of scope: none of their data is migrated, so the
-- read-only role has no grant on them at all (data minimization -- see
-- setup_readonly_role.sql). Requires -v legacy_hotel_id=<uuid>.
\set ON_ERROR_STOP on

\echo '--- legacy source counts (scoped to this hotel) ---'
select 'hotels' as table_name, count(*) as n from hotels where id = :'legacy_hotel_id'
union all select 'staff_profiles', count(*) from staff_profiles where hotel_id = :'legacy_hotel_id'
union all select 'rooms', count(*) from rooms where hotel_id = :'legacy_hotel_id'
union all select 'request_categories', count(*) from request_categories where hotel_id = :'legacy_hotel_id'
union all select 'request_types', count(*) from request_types rt join request_categories rc on rc.id = rt.category_id where rc.hotel_id = :'legacy_hotel_id'
union all select 'stays_total', count(*) from stays where hotel_id = :'legacy_hotel_id'
union all select 'stays_active', count(*) from stays where hotel_id = :'legacy_hotel_id' and status = 'active'
union all select 'guest_requests_total', count(*) from guest_requests where hotel_id = :'legacy_hotel_id'
union all select 'guest_requests_open', count(*) from guest_requests where hotel_id = :'legacy_hotel_id' and status in ('requested','in_progress') and archived_at is null;
