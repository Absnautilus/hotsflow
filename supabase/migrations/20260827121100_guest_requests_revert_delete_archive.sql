-- Three additions to the request lifecycle:
-- 1. Permanent delete for guest_requests (previously only update/insert/select
--    were granted) — scoped the same as update already is: any active staff
--    member of the hotel, matching this dashboard's deliberately shared model.
--    The frontend gates it behind a confirm dialog; RLS just makes it possible.
-- 2. archived_at: completed/cancelled requests older than 72h are swept out of
--    the default "evase" view by a scheduled job, instead of that list growing
--    forever. Archiving only hides them (fetchQueue excludes archived rows);
--    it's not the same as the new manual delete, which is permanent.

begin;

alter table guest_requests add column archived_at timestamptz;

create index guest_requests_archive_idx on guest_requests(status, archived_at) where archived_at is null;

create policy guest_requests_delete_hotel on guest_requests for delete to authenticated
  using (hotel_id = current_staff_hotel());

grant delete on guest_requests to authenticated;

commit;

-- pg_cron scheduling can't run inside the same transaction as the schema
-- changes above on some Supabase project configurations, and needs the
-- extension enabled first — split into its own statement.
create extension if not exists pg_cron with schema extensions;

select cron.schedule(
  'archive-old-requests',
  '0 * * * *',
  $$
    update guest_requests
    set archived_at = now()
    where archived_at is null
      and status in ('completed', 'cancelled')
      and coalesce(completed_at, created_at) < now() - interval '72 hours'
  $$
);
