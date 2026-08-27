-- Calls the notify-new-request Edge Function directly via pg_net whenever a
-- guest_requests row is inserted. This project's Studio doesn't expose a
-- standalone "Database Webhooks" page, so this recreates the same mechanism
-- by hand: pg_net is the extension Supabase's own Webhooks feature uses
-- under the hood to fire an async HTTP call from a trigger.
--
-- BEFORE RUNNING: replace the two placeholders below.
--   YOUR_PROJECT_REF  — from Settings -> API -> Project URL, the part before
--                       ".supabase.co" (same value as VITE_SUPABASE_URL).
--   YOUR_ANON_KEY     — from Settings -> API -> anon/public key (same value
--                       as VITE_SUPABASE_ANON_KEY). Safe to embed here: it's
--                       already public, shipped inside the web app bundle.
--                       It only proves to Supabase's gateway that the caller
--                       is a legitimate client — the Edge Function itself
--                       uses the service-role key internally for anything
--                       privileged, never this one.

begin;

create extension if not exists pg_net;

create function notify_new_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/notify-new-request',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_ANON_KEY'
    ),
    body := jsonb_build_object('type', 'INSERT', 'table', 'guest_requests', 'record', to_jsonb(NEW))
  );
  return NEW;
end;
$$;

create trigger guest_requests_notify_after_insert
  after insert on guest_requests
  for each row execute function notify_new_request();

commit;
