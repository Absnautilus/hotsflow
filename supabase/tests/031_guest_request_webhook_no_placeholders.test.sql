-- Fase 2 pre-cutover gate — regression coverage for 20260827122700, which
-- fixed notify_new_request() still containing the literal YOUR_PROJECT_REF/
-- YOUR_ANON_KEY placeholders from 20260827121300, unpatched since deploy
-- (confirmed live via pg_get_functiondef() before writing the fix, not
-- assumed). Checks the placeholders are gone, the endpoint is the exact
-- live URL, and the delivery trigger is still present and enabled -- does
-- NOT assert on the anon key value itself, so this file never needs to
-- carry the real credential.
begin;
create extension if not exists pgtap;
select plan(4);

select ok(
  pg_get_functiondef('public.notify_new_request()'::regprocedure) not like '%YOUR_PROJECT_REF%',
  'notify_new_request() must not contain the YOUR_PROJECT_REF placeholder'
);

select ok(
  pg_get_functiondef('public.notify_new_request()'::regprocedure) not like '%YOUR_ANON_KEY%',
  'notify_new_request() must not contain the YOUR_ANON_KEY placeholder'
);

select is(
  (regexp_match(pg_get_functiondef('public.notify_new_request()'::regprocedure), 'url\s*:=\s*''([^'']+)'''))[1],
  'https://flyedzqqdrxxtxchoeer.supabase.co/functions/v1/notify-new-request',
  'notify_new_request() posts to the exact live notify-new-request endpoint'
);

select is(
  (select tgenabled from pg_trigger
   where tgname = 'guest_requests_notify_after_insert' and tgrelid = 'public.guest_requests'::regclass),
  'O',
  'guest_requests_notify_after_insert exists on guest_requests and is enabled (tgenabled = O)'
);

select * from finish();
rollback;
