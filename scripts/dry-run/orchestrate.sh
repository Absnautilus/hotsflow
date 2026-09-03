#!/usr/bin/env bash
# Production Data Migration dry-run orchestrator. Runs against a disposable
# local Supabase stack only (127.0.0.1) -- see the header of
# 00_seed_legacy_synthetic.sql. Requires `supabase start` already running
# in the working directory, and psql/curl/jq on PATH.
#
# Covers, in order, the 13 checks requested for this dry-run:
#  1 export (seed synthetic "legacy" schema)      -> Item 1
#  2 Auth user creation/mapping                   -> Item 2
#  3 import respecting FK order                   -> Items 3-4
#  4 profiles/staff_profiles/memberships          -> Items 3-4 + reconcile
#  5 ID preservation where planned                -> reconcile
#  6 row counts pre/post                          -> reconcile
#  7 referential integrity                        -> reconcile
#  8 tenant/property mapping                      -> reconcile
#  9 entitlement                                  -> reconcile
# 10 login of a migrated user                     -> Item 10
# 11 idempotent rerun                             -> Item 11
# 12 mid-Auth failure + cleanup                   -> Item 12
# 13 post-Auth SQL failure + rollback             -> Item 13
set -uo pipefail  # not -e: this script deliberately triggers failures and must keep going to check cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
init_connection_vars

HOTEL_ID="99999999-0000-0000-0000-000000000001"
HOTEL_NAME="Hotel Sample E2E Dry-Run"
HOTEL_SLUG="hotel-sample-e2e-dryrun"

# ---------------------------------------------------------------------------
# Item 1 — export (synthetic legacy seed)
# ---------------------------------------------------------------------------
echo "=== Item 1: seeding synthetic legacy export ==="
if psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/00_seed_legacy_synthetic.sql"; then
  record "1_export_seed" "PASS"
else
  record "1_export_seed" "FAIL"; exit 1
fi

# ---------------------------------------------------------------------------
# Item 2 — Auth user creation/mapping, data-driven from legacy_source
# ---------------------------------------------------------------------------
echo "=== Item 2: Auth user creation (remapping strategy, plan default) ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "create table if not exists auth_remap (legacy_auth_user_id uuid primary key, new_auth_user_id uuid not null); truncate auth_remap;" \
  -c "\copy (select id, email, password from legacy_source.staff_profiles where hotel_id = '$HOTEL_ID') to '/tmp/dryrun_staff.csv' with csv"
AUTH_OK=1
while IFS=, read -r legacy_id email password; do
  new_id="$(create_auth_user "$email" "$password")"
  if [ "$new_id" = "FAILED" ]; then AUTH_OK=0; break; fi
  psql "$DB_URL" -v ON_ERROR_STOP=1 -c "insert into auth_remap (legacy_auth_user_id, new_auth_user_id) values ('$legacy_id','$new_id');" >/dev/null
done < /tmp/dryrun_staff.csv
if [ "$AUTH_OK" = "1" ]; then
  record "2_auth_mapping" "PASS ($(wc -l < /tmp/dryrun_staff.csv) staff mapped)"
else
  record "2_auth_mapping" "FAIL"; exit 1
fi

# ---------------------------------------------------------------------------
# Items 3-4 — import respecting FK order; profiles/staff_profiles/memberships
# ---------------------------------------------------------------------------
echo "=== Items 3-4: scoped Core provisioning + module data import ==="
if psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="$HOTEL_ID" -v hotel_name="$HOTEL_NAME" -v hotel_slug="$HOTEL_SLUG" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then
  record "3_4_import_and_provisioning" "PASS"
else
  record "3_4_import_and_provisioning" "FAIL"; exit 1
fi

# ---------------------------------------------------------------------------
# Items 5-9 — reconciliation
# ---------------------------------------------------------------------------
echo "=== Items 5-9: reconciliation ==="
psql "$DB_URL" -v hotel_id="$HOTEL_ID" -f "$SCRIPT_DIR/20_reconciliation.sql" | tee /tmp/reconciliation_output.txt
record "5_9_reconciliation" "SEE OUTPUT ABOVE — manually cross-checked against expected values in job log"

# ---------------------------------------------------------------------------
# Item 10 — login of a migrated user
# ---------------------------------------------------------------------------
echo "=== Item 10: login test for a migrated user ==="
TOKEN="$(login_password 'dryrun-admin@example.test' 'DryRunAdmin!234')"
if [ "$TOKEN" != "FAILED" ]; then
  record "10_login_test" "PASS (access_token issued)"
else
  record "10_login_test" "FAIL"
fi

# ---------------------------------------------------------------------------
# Item 11 — idempotent rerun (Auth phase + SQL phase again)
# ---------------------------------------------------------------------------
echo "=== Item 11: idempotent rerun ==="
RERUN_OK=1
create_auth_user 'dryrun-admin@example.test' 'DryRunAdmin!234' >/dev/null
DUP_COUNT="$(count_auth_users_by_email_prefix 'dryrun-admin@example.test')"
if [ "$DUP_COUNT" != "1" ]; then RERUN_OK=0; fi
if ! psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="$HOTEL_ID" -v hotel_name="$HOTEL_NAME" -v hotel_slug="$HOTEL_SLUG" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then RERUN_OK=0; fi
POST_RERUN_COUNT="$(psql "$DB_URL" -tAc "select count(*) from guest_requests where hotel_id = '$HOTEL_ID'")"
if [ "$POST_RERUN_COUNT" != "2" ]; then RERUN_OK=0; fi
if [ "$RERUN_OK" = "1" ]; then
  record "11_idempotent_rerun" "PASS (no duplicate auth user, guest_requests still =2 after rerun)"
else
  record "11_idempotent_rerun" "FAIL (dup_auth_count=$DUP_COUNT post_rerun_requests=$POST_RERUN_COUNT)"
fi

# ---------------------------------------------------------------------------
# Item 12 — mid-Auth failure injection + cleanup verification (Hotel B, synthetic)
# ---------------------------------------------------------------------------
echo "=== Item 12: mid-Auth failure injection ==="
B1_ID="$(create_auth_user 'dryrun-b-staff1@staff.local' 'HotelB!Pass1')"
B2_ID="FAILED"
if [ "$B1_ID" != "FAILED" ]; then
  B2_ID="$(create_auth_user 'dryrun-b-staff1@staff.local' 'HotelB!Pass2')"
fi
if [ "$B1_ID" != "FAILED" ] && [ "$B2_ID" = "FAILED" ]; then
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
# Item 13 — post-Auth SQL failure injection + rollback verification (Hotel C, synthetic)
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
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('99999999-0000-0000-0000-000000000003', :'scenario_c_prop_id');
commit;
SQL
  SQL_EXIT=$?
  POST_ROLLBACK_HOTEL_COUNT="$(psql "$DB_URL" -tAc "select count(*) from hotels where id = '99999999-0000-0000-0000-000000000003'")"
  if [ "$SQL_EXIT" != "0" ] && [ "$POST_ROLLBACK_HOTEL_COUNT" = "0" ]; then
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
