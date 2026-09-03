#!/usr/bin/env bash
# Cutover-readiness final verification -- real webhook test against the
# REAL Hotsflow project. Creates one clearly-marked, fully synthetic
# fixture (hotel/room/stay/category/type/guest_request, all ids prefixed
# facade00-...  so they can never be mistaken for real data), inserts the
# guest_requests row that fires the trigger, waits for pg_net's async
# response, reports the result, then ALWAYS deletes everything it created
# (trap-guaranteed, runs even on failure) so no trace is left behind.
#
# guest_requests_notify_after_insert / notify_new_request() is the only
# caller of net.http_post() anywhere in this schema (confirmed by grep
# across supabase/migrations/*.sql before writing this script) -- so any
# row that lands in net._http_response after our insert can only be the
# response to *our* test call, no ambiguity from concurrent traffic on
# this trigger (there is none).
set -uo pipefail

: "${DB_URL:?DB_URL must be set (postgresql://... to the real Hotsflow project)}"

HOTEL_ID="facade00-0000-4000-8000-000000000001"
ROOM_ID="facade00-0000-4000-8000-000000000002"
STAY_ID="facade00-0000-4000-8000-000000000003"
CATEGORY_ID="facade00-0000-4000-8000-000000000004"
TYPE_ID="facade00-0000-4000-8000-000000000005"
REQUEST_ID="facade00-0000-4000-8000-000000000006"

cleanup() {
  echo "=== Cleanup: removing synthetic test fixture (always runs) ==="
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL
delete from guest_requests where id = '$REQUEST_ID';
delete from request_types where id = '$TYPE_ID';
delete from request_categories where id = '$CATEGORY_ID';
delete from stays where id = '$STAY_ID';
delete from rooms where id = '$ROOM_ID';
delete from hotels where id = '$HOTEL_ID';
SQL
  REMAINING="$(psql "$DB_URL" -tAc "select count(*) from hotels where id = '$HOTEL_ID'")"
  if [ "$REMAINING" != "0" ]; then
    echo "!!! CLEANUP FAILED: test hotel row still present. Manual removal required: delete from hotels where id = '$HOTEL_ID';"
    exit 1
  fi
  echo "Cleanup confirmed: no trace of the test fixture remains."
}
trap cleanup EXIT

echo "=== Pre-check: no non-test rows in hotels (confirms no business data has been migrated yet) ==="
PRE_COUNT="$(psql "$DB_URL" -tAc "select count(*) from hotels where id != '$HOTEL_ID'")"
echo "hotels rows other than our test fixture: $PRE_COUNT"
if [ "$PRE_COUNT" != "0" ]; then
  echo "!!! ABORT: hotels already contains $PRE_COUNT row(s) not created by this script."
  echo "!!! This means real (or unexpected) data is already present. Refusing to proceed."
  exit 1
fi

echo "=== Seeding synthetic test fixture ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL
insert into hotels (id, name, timezone, active) values
  ('$HOTEL_ID', 'ZZ_WEBHOOK_VERIFY_DELETE_ME', 'Europe/Rome', true);
insert into rooms (id, hotel_id, room_number, active) values
  ('$ROOM_ID', '$HOTEL_ID', 'ZZTEST', true);
insert into stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status) values
  ('$STAY_ID', '$HOTEL_ID', '$ROOM_ID', 'ZZWEBHOOKTEST', now() - interval '1 hour', now() + interval '1 day', 'active');
insert into request_categories (id, hotel_id, name, department) values
  ('$CATEGORY_ID', '$HOTEL_ID', 'ZZ_WEBHOOK_TEST_CATEGORY', 'housekeeping');
insert into request_types (id, category_id, name) values
  ('$TYPE_ID', '$CATEGORY_ID', 'ZZ_WEBHOOK_TEST_TYPE');
SQL
if [ $? -ne 0 ]; then echo "!!! Fixture seed failed"; exit 1; fi

echo "=== Baseline: net._http_response row count before the test insert ==="
BASELINE="$(psql "$DB_URL" -tAc "select count(*) from net._http_response")"
echo "baseline count: $BASELINE"

echo "=== Firing the trigger: inserting the test guest_requests row ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "insert into guest_requests (id, hotel_id, stay_id, request_type_id) values ('$REQUEST_ID', '$HOTEL_ID', '$STAY_ID', '$TYPE_ID');"
if [ $? -ne 0 ]; then echo "!!! Test insert failed -- webhook: FAIL (could not even create the triggering row)"; exit 1; fi

echo "=== Waiting for pg_net's async worker + Edge Function round trip ==="
sleep 10

echo "=== Checking net._http_response for the new response ==="
AFTER="$(psql "$DB_URL" -tAc "select count(*) from net._http_response")"
echo "post-insert count: $AFTER"

if [ "$AFTER" -le "$BASELINE" ]; then
  echo ">>> webhook: FAIL (no new row appeared in net._http_response -- trigger did not fire or pg_net never queued the request)"
  exit 1
fi

echo "--- Most recent response(s) since baseline ---"
psql "$DB_URL" -c "select id, status_code, timed_out, error_msg, left(content::text, 300) as content_preview, created from net._http_response order by id desc limit 3;"

LATEST_STATUS="$(psql "$DB_URL" -tAc "select status_code from net._http_response order by id desc limit 1")"
LATEST_ERROR="$(psql "$DB_URL" -tAc "select coalesce(error_msg, '') from net._http_response order by id desc limit 1")"

if [ "$LATEST_STATUS" = "200" ] && [ -z "$LATEST_ERROR" ]; then
  echo ">>> webhook: PASS (trigger fired, notify-new-request responded 200)"
  echo ">>> Note: a 200 from notify-new-request means the function ran without throwing -- this is evidence (not final proof) that its VAPID secrets are readable server-side, since a missing VAPID_PRIVATE_KEY would typically make the push-send step inside the function fail. It does NOT prove a push was actually delivered to a subscribed device -- that requires a real device test, which only you can perform."
  exit 0
else
  echo ">>> webhook: FAIL (trigger fired, but response was status=$LATEST_STATUS error_msg='$LATEST_ERROR' -- not a clean 200)"
  exit 1
fi
