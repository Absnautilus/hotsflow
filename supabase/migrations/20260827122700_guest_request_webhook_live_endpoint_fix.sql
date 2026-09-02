-- Fase 2 pre-cutover gate — fixes a live-state placeholder found during the
-- infrastructure verification: notify_new_request() (created by
-- 20260827121300) still had the literal YOUR_PROJECT_REF/YOUR_ANON_KEY
-- placeholders from that migration's own file, unpatched on hosted since
-- deploy — confirmed live via pg_get_functiondef() before writing this fix,
-- not assumed. CREATE OR REPLACE keeps the function's OID, so the existing
-- guest_requests_notify_after_insert trigger (untouched here) keeps
-- resolving to it with no gap in coverage; the trigger, its event (AFTER
-- INSERT), and the payload shape are all unchanged — only the URL/
-- Authorization header inside the function body change.
--
-- The anon key below is the project's public anon key (its own JWT claims
-- confirm role: anon, not service_role) -- by design meant to be public,
-- already shipped inside the web app bundle; same reasoning as the original
-- 20260827121300 migration's own header comment.
--
-- ROLLBACK, if this ever needs to be undone: do NOT restore the previous
-- (placeholder) body -- that was a deliberately-broken, known-bad state,
-- not a safe fallback. The supported path is operational, not a
-- down-migration:
--   1. kill switch, immediately: alter table guest_requests disable trigger
--      guest_requests_notify_after_insert; -- stops webhook calls at once,
--      nothing else in the app depends on this trigger.
--   2. diagnose/correct the endpoint or credential causing the problem.
--   3. ship a new corrective migration with the fix (never edit this file
--      after it has been applied to hosted).
--   4. verify (031_guest_request_webhook_no_placeholders.test.sql plus the
--      live pg_get_functiondef() check used to confirm this fix).
--   5. re-enable: alter table guest_requests enable trigger
--      guest_requests_notify_after_insert;
begin;

create or replace function notify_new_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://flyedzqqdrxxtxchoeer.supabase.co/functions/v1/notify-new-request',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZseWVkenFxZHJ4eHR4Y2hvZWVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc4OTUwNTQsImV4cCI6MjEwMzQ3MTA1NH0.c6z6VldYjWf-ITHgAh1bhBHAaoc75uP1jlZo-E0YdTo'
    ),
    body := jsonb_build_object('type', 'INSERT', 'table', 'guest_requests', 'record', to_jsonb(NEW))
  );
  return NEW;
end;
$$;

commit;
