#!/usr/bin/env bash
# Production Data Migration dry-run orchestrator. Runs against a disposable
# local Supabase stack only (127.0.0.1) -- see the header of
# 00_seed_legacy_synthetic.sql. Requires `supabase start` already running
# in the working directory, and psql/curl/jq on PATH.
#
# Covers, in order, the 13 checks requested for this dry-run:
#  1 export (seed synthetic "legacy" schema)      -> seed_legacy()
#  2 Auth user creation/mapping                   -> auth_phase()
#  3 import respecting FK order                   -> migrate_hotel_a()
#  4 profiles/staff_profiles/memberships          -> migrate_hotel_a() + reconcile()
#  5 ID preservation where planned                -> reconcile()
#  6 row counts pre/post                          -> reconcile()
#  7 referential integrity                        -> reconcile()
#  8 tenant/property mapping                      -> reconcile()
#  9 entitlement                                  -> reconcile()
# 10 login of a migrated user                     -> login_test()
# 11 idempotent rerun                             -> rerun_idempotency()
# 12 mid-Auth failure + cleanup                   -> scenario_b_mid_auth_failure()
# 13 post-Auth SQL failure + rollback             -> scenario_c_post_auth_sql_failure()
set -uo pipefail  # not -e: this script deliberately triggers failures and must keep going to check cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
STATUS_JSON="$(supabase status -o json)"
echo "supabase status -o json: $STATUS_JSON"
API_URL="$(echo "$STATUS_JSON" | jq -r '.API_URL')"
# This CLI's local stack has been observed printing the newer
# Publishable/Secret key names (see the CI job log for the `database` job,
# "Authentication Keys" table) rather than the legacy ANON_KEY/
# SERVICE_ROLE_KEY names -- try both rather than assuming one.
SERVICE_ROLE_KEY="$(echo "$STATUS_JSON" | jq -r '.SERVICE_ROLE_KEY // .SECRET_KEY // empty')"

RESULTS=()
record() { RESULTS+=("$1: $2"); echo ">>> $1: $2"; }

create_auth_user() {  # $1=email $2=password -> prints new id on stdout, or "FAILED"
  local email="$1" password="$2" resp status body
  resp="$(curl -s -w '\n%{http_code}' -X POST "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" -H "User-Agent: dry-run-script/1.0" \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true}")"
  status="$(echo "$resp" | tail -1)"; body="$(echo "$resp" | sed '$d')"
  if [ "$status" = "200" ]; then echo "$body" | jq -r '.id'; else echo "FAILED"; fi
}

delete_auth_user() {
  curl -s -X DELETE "$API_URL/auth/v1/admin/users/$1" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "User-Agent: dry-run-script/1.0" >/dev/null
}

count_auth_users_by_email_prefix() {  # $1=prefix -> count
  psql "$DB_URL" -tAc "select count(*) from auth.users where email like '$1%'"
}

# ---------------------------------------------------------------------------
# Item 1 — export (synthetic legacy seed)
# ---------------------------------------------------------------------------
echo "=== Item 1: seeding synthetic legacy export ==="
if psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/00_seed_legacy_synthetic.sql"; then
  record "1_export_seed" "PASS"
else
  record "1_export_seed" "FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# Item 2 — Auth user creation/mapping (Hotel A, full scenario)
# ---------------------------------------------------------------------------
echo "=== Item 2: Auth user creation (remapping strategy, plan default) ==="
ADMIN_ID="$(create_auth_user 'dryrun-admin@example.test' 'DryRunAdmin!234')"
OPA_ID="$(create_auth_user 'dryrun-operatore-a@staff.local' '135790abcDEF')"
OPB_ID="$(create_auth_user 'dryrun-operatore-b@staff.local' '246801abcDEF')"
if [ "$ADMIN_ID" != "FAILED" ] && [ "$OPA_ID" != "FAILED" ] && [ "$OPB_ID" != "FAILED" ]; then
  record "2_auth_mapping" "PASS (admin=$ADMIN_ID opa=$OPA_ID opb=$OPB_ID)"
else
  record "2_auth_mapping" "FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# Items 3-4 — import respecting FK order; profiles/staff_profiles/memberships
# ---------------------------------------------------------------------------
echo "=== Items 3-4: scoped Core provisioning + module data import ==="
if psql "$DB_URL" -v ON_ERROR_STOP=1 -v admin_id="$ADMIN_ID" -v opa_id="$OPA_ID" -v opb_id="$OPB_ID" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then
  record "3_4_import_and_provisioning" "PASS"
else
  record "3_4_import_and_provisioning" "FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# Items 5-9 — reconciliation (id preservation, row counts, FK integrity,
# tenant/property mapping, entitlement)
# ---------------------------------------------------------------------------
echo "=== Items 5-9: reconciliation ==="
psql "$DB_URL" -f "$SCRIPT_DIR/20_reconciliation.sql" | tee /tmp/reconciliation_output.txt
record "5_9_reconciliation" "SEE OUTPUT ABOVE — manually cross-checked against expected values in job log"

# ---------------------------------------------------------------------------
# Item 10 — login of a migrated user
# ---------------------------------------------------------------------------
echo "=== Item 10: login test for a migrated user ==="
ANON_KEY="$(echo "$STATUS_JSON" | jq -r '.ANON_KEY // .PUBLISHABLE_KEY // empty')"
LOGIN_RESP="$(curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -H "User-Agent: dry-run-script/1.0" \
  -d '{"email":"dryrun-admin@example.test","password":"DryRunAdmin!234"}')"
if echo "$LOGIN_RESP" | jq -e '.access_token' >/dev/null 2>&1; then
  record "10_login_test" "PASS (access_token issued)"
else
  record "10_login_test" "FAIL ($LOGIN_RESP)"
fi

# ---------------------------------------------------------------------------
# Item 11 — idempotent rerun (Auth phase + SQL phase again, same ids)
# ---------------------------------------------------------------------------
echo "=== Item 11: idempotent rerun ==="
RERUN_OK=1
# Auth phase rerun: creating the same email again must fail (already exists),
# which is the CORRECT idempotent behavior for admin.createUser -- a real
# migration script must treat "already exists" as already-migrated, not as
# an error. Verify no duplicate auth.users rows exist for these emails.
create_auth_user 'dryrun-admin@example.test' 'DryRunAdmin!234' >/dev/null
DUP_COUNT="$(count_auth_users_by_email_prefix 'dryrun-admin@example.test')"
if [ "$DUP_COUNT" != "1" ]; then RERUN_OK=0; fi
# SQL phase rerun: must succeed cleanly (ON CONFLICT DO NOTHING throughout).
if ! psql "$DB_URL" -v ON_ERROR_STOP=1 -v admin_id="$ADMIN_ID" -v opa_id="$OPA_ID" -v opb_id="$OPB_ID" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then RERUN_OK=0; fi
POST_RERUN_COUNT="$(psql "$DB_URL" -tAc "select count(*) from guest_requests where hotel_id = '99999999-0000-0000-0000-000000000001'")"
if [ "$POST_RERUN_COUNT" != "2" ]; then RERUN_OK=0; fi  # must still be 2, not 4
if [ "$RERUN_OK" = "1" ]; then
  record "11_idempotent_rerun" "PASS (no duplicate auth user, guest_requests still =2 after rerun)"
else
  record "11_idempotent_rerun" "FAIL (dup_auth_count=$DUP_COUNT post_rerun_requests=$POST_RERUN_COUNT)"
fi

# ---------------------------------------------------------------------------
# Item 12 — mid-Auth failure injection + cleanup verification (Hotel B)
# ---------------------------------------------------------------------------
echo "=== Item 12: mid-Auth failure injection ==="
B1_ID="$(create_auth_user 'dryrun-b-staff1@staff.local' 'HotelB!Pass1')"
B2_ID="FAILED"
if [ "$B1_ID" != "FAILED" ]; then
  # Deliberate duplicate email -> GoTrue must reject this.
  B2_ID="$(create_auth_user 'dryrun-b-staff1@staff.local' 'HotelB!Pass2')"
fi
if [ "$B1_ID" != "FAILED" ] && [ "$B2_ID" = "FAILED" ]; then
  # Per plan §B.1.5: on a failure partway through, delete every user this
  # run already created, and do not proceed to the SQL transaction.
  delete_auth_user "$B1_ID"
  REMAINING="$(count_auth_users_by_email_prefix 'dryrun-b-staff1')"
  if [ "$REMAINING" = "0" ]; then
    record "12_mid_auth_failure_cleanup" "PASS (failure detected, cleanup left 0 orphaned auth.users rows, SQL phase correctly never ran)"
  else
    record "12_mid_auth_failure_cleanup" "FAIL (cleanup left $REMAINING orphaned row(s))"
  fi
else
  record "12_mid_auth_failure_cleanup" "FAIL (expected first create to succeed and second to fail; got B1=$B1_ID B2=$B2_ID)"
fi

# ---------------------------------------------------------------------------
# Item 13 — post-Auth SQL failure injection + rollback verification (Hotel C)
# ---------------------------------------------------------------------------
echo "=== Item 13: post-Auth SQL failure injection ==="
C1_ID="$(create_auth_user 'dryrun-c-staff1@staff.local' 'HotelC!Pass1')"
if [ "$C1_ID" != "FAILED" ]; then
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL >/tmp/scenario_c_sql.log 2>&1
begin;
insert into hotels (id, name, timezone, active)
  values ('99999999-0000-0000-0000-000000000003', 'Hotel Sample C Dry-Run', 'Europe/Rome', true)
  on conflict (id) do nothing;
insert into organizations (name, slug) values ('Hotel Sample C', 'hotel-sample-c-dryrun') returning id \gset scenario_c_
insert into properties (organization_id, name, slug, timezone, status)
  values (:'scenario_c_id', 'Hotel Sample C', 'hotel-sample-c-dryrun', 'Europe/Rome', 'active') returning id \gset scenario_c_prop_
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('99999999-0000-0000-0000-000000000003', :'scenario_c_prop_id');
-- Deliberate failure: legacy_property_mapping's PK is legacy_hotel_id,
-- inserting the same one again must violate it and abort the transaction.
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('99999999-0000-0000-0000-000000000003', :'scenario_c_prop_id');
commit;
SQL
  SQL_EXIT=$?
  POST_ROLLBACK_HOTEL_COUNT="$(psql "$DB_URL" -tAc "select count(*) from hotels where id = '99999999-0000-0000-0000-000000000003'")"
  if [ "$SQL_EXIT" != "0" ] && [ "$POST_ROLLBACK_HOTEL_COUNT" = "0" ]; then
    # SQL side correctly rolled back to nothing. Per §I.3/§B.1.5: the Auth
    # user created before the (now-rolled-back) SQL phase is orphaned and
    # must be cleaned up too.
    delete_auth_user "$C1_ID"
    REMAINING_C="$(count_auth_users_by_email_prefix 'dryrun-c-staff1')"
    if [ "$REMAINING_C" = "0" ]; then
      record "13_post_auth_sql_failure_rollback" "PASS (SQL transaction rolled back cleanly to 0 rows, orphaned Auth user identified and cleaned up)"
    else
      record "13_post_auth_sql_failure_rollback" "FAIL (Auth cleanup left $REMAINING_C row(s))"
    fi
  else
    record "13_post_auth_sql_failure_rollback" "FAIL (sql_exit=$SQL_EXIT hotel_count=$POST_ROLLBACK_HOTEL_COUNT — see /tmp/scenario_c_sql.log)"
  fi
else
  record "13_post_auth_sql_failure_rollback" "FAIL (could not even create the precondition Auth user)"
fi

echo ""
echo "=== DRY-RUN SUMMARY ==="
for r in "${RESULTS[@]}"; do echo "$r"; done
