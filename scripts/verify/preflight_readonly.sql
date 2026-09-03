-- Cutover PRE-FLIGHT — strictly read-only. No INSERT/UPDATE/DELETE
-- anywhere in this file. Every check here is a SELECT against the real
-- Hotsflow project, run only to confirm current state before FREEZE.

\echo '=== 8. Entitlement: guest_requests module exists ==='
select id, slug from modules where slug = 'guest_requests';

\echo '=== 10. Realtime publication (expect exactly public.guest_requests) ==='
select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime' order by 1,2;

\echo '=== 11a. Database webhook trigger: exists and enabled? ==='
select tgname, tgenabled from pg_trigger where tgname = 'guest_requests_notify_after_insert';

\echo '=== 11b. notify_new_request() function: no leftover placeholders, correct live endpoint ==='
select
  pg_get_functiondef('public.notify_new_request()'::regprocedure) not like '%YOUR_PROJECT_REF%' as no_project_ref_placeholder,
  pg_get_functiondef('public.notify_new_request()'::regprocedure) not like '%YOUR_ANON_KEY%' as no_anon_key_placeholder,
  (regexp_match(pg_get_functiondef('public.notify_new_request()'::regprocedure), 'url\s*:=\s*''([^'']+)'''))[1] as endpoint_url;

\echo '=== 11c. Most recent pg_net responses (read-only signal only, no new test fired here) ==='
select id, status_code, error_msg, created from net._http_response order by id desc limit 5;

\echo '=== 13. PMS integrations row count (expect 0) ==='
select count(*) as pms_integrations_count from pms_integrations;

\echo '=== 14. Palazzo Veneziano NOT already present in target (expect 0) ==='
select count(*) as real_hotel_rows from hotels where id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb' or name ilike '%veneziano%';

\echo '=== 15. No residual synthetic readiness-test fixtures (expect 0) ==='
select count(*) as facade00_residue from hotels where id::text like 'facade00-%';

\echo '=== Context: full current hotels table (for audit -- expect only known Fase 2 demo rows) ==='
select id, name, created_at from hotels order by created_at;

\echo '=== Context: current staff_profiles row count on target (expect 0 -- nothing migrated yet) ==='
select count(*) as staff_profiles_on_target from staff_profiles;
