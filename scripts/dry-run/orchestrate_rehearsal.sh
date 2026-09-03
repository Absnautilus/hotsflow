#!/usr/bin/env bash
# Production Migration Rehearsal orchestrator. Same scripts as the dry-run
# (10_migrate_hotel.sql, 20_reconciliation.sql, lib.sh) — no second
# implementation — run against REAL (anonymized) data instead of
# synthetic, on the same disposable local Supabase stack, destroyed when
# the job ends. Nothing here touches the legacy or Hotsflow projects.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
init_connection_vars

HOTEL_ID="25b00bec-1602-46e9-bf52-a4913ebb5bdb"
HOTEL_NAME="Palazzo Veneziano"
HOTEL_SLUG="palazzo-veneziano-rehearsal"

# Deterministic per-account synthetic password, derived from the full
# legacy id — used identically at creation time and at E2E-login time so
# the two can never drift apart (a real bug in an earlier draft used only
# the id's short prefix on the login side, computing a different value).
pw_for_id() { echo "Rehearsal$(echo "$1" | tr -dc '0-9' | cut -c1-8)!Aa"; }

MASTER_ID="68502c30-a20c-49a6-b6e9-8407b8d14308"
OP1_ID="5bb9c3c7-a318-4d67-9244-4a998e8dc132"
OP3_ID="c427faa3-1030-430d-883d-5c6c905e2b22"

declare -A T  # phase -> elapsed ms
phase_start() { echo "$(now_ms)"; }
phase_end() { local name="$1" start="$2"; T["$name"]="$(elapsed_ms "$start")"; echo ">>> ${name}_duration_ms: ${T[$name]}"; }

TOTAL_START="$(now_ms)"

# ---------------------------------------------------------------------------
# Export/seed phase (real anonymized data, already exported by the user
# directly from legacy — see docs/production-migration-rehearsal.md)
# ---------------------------------------------------------------------------
echo "=== Rehearsal: seeding real (anonymized) legacy export ==="
S="$(phase_start)"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/01_seed_legacy_rehearsal.sql"; then
  record "export_seed" "PASS"
else
  record "export_seed" "FAIL"; exit 1
fi
phase_end "export" "$S"

# A tiny, fully synthetic second property ("Hotel X"), unrelated to the
# real hotel, used only for the cross-property denial check in the E2E
# phase below -- real data alone gives no second property to test against.
S="$(phase_start)"
psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
insert into legacy_source.hotels values ('88888888-0000-0000-0000-000000000001','Hotel X (rehearsal cross-property fixture)','Europe/Rome',true) on conflict (id) do nothing;
insert into legacy_source.staff_profiles (id, hotel_id, email, name, role, department, active, login_username) values
  ('88888888-0000-0000-0000-0000000000b1','88888888-0000-0000-0000-000000000001','hotelx-admin@example.test','Hotel X Admin','admin',null,true,null)
  on conflict (id) do nothing;
SQL
phase_end "hotel_x_fixture_seed" "$S"

# ---------------------------------------------------------------------------
# Auth phase — data-driven remapping, real hotel + Hotel X fixture
# ---------------------------------------------------------------------------
echo "=== Rehearsal: Auth user creation (remapping strategy) ==="
S="$(phase_start)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "create table if not exists auth_remap (legacy_auth_user_id uuid primary key, new_auth_user_id uuid not null); truncate auth_remap;" \
  -c "\copy (select id, email from legacy_source.staff_profiles) to '/tmp/rehearsal_staff.csv' with csv"
AUTH_OK=1
MAPPED=0
while IFS=, read -r legacy_id email; do
  pw="$(pw_for_id "$legacy_id")"
  new_id="$(create_auth_user "$email" "$pw")"
  if [ "$new_id" = "FAILED" ]; then AUTH_OK=0; break; fi
  psql "$DB_URL" -v ON_ERROR_STOP=1 -c "insert into auth_remap (legacy_auth_user_id, new_auth_user_id) values ('$legacy_id','$new_id');" >/dev/null
  MAPPED=$((MAPPED+1))
done < /tmp/rehearsal_staff.csv
phase_end "auth_migration" "$S"
if [ "$AUTH_OK" = "1" ]; then
  record "auth_mapping" "PASS ($MAPPED staff mapped, incl. Hotel X fixture)"
else
  record "auth_mapping" "FAIL"; exit 1
fi

# ---------------------------------------------------------------------------
# SQL import phase — real hotel, then Hotel X fixture (same script, both)
# ---------------------------------------------------------------------------
echo "=== Rehearsal: scoped Core provisioning + module data import ==="
S="$(phase_start)"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="$HOTEL_ID" -v hotel_name="$HOTEL_NAME" -v hotel_slug="$HOTEL_SLUG" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then
  record "sql_import_real_hotel" "PASS"
else
  record "sql_import_real_hotel" "FAIL"; exit 1
fi
psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="88888888-0000-0000-0000-000000000001" -v hotel_name="Hotel X (rehearsal cross-property fixture)" -v hotel_slug="hotel-x-rehearsal" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql" >/dev/null
phase_end "sql_import" "$S"

# ---------------------------------------------------------------------------
# Reconciliation, with legacy/migrated/excluded/unexpected-loss classification
# ---------------------------------------------------------------------------
echo "=== Rehearsal: reconciliation ==="
S="$(phase_start)"
psql "$DB_URL" -v hotel_id="$HOTEL_ID" -f "$SCRIPT_DIR/20_reconciliation.sql" | tee /tmp/rehearsal_reconciliation.txt
phase_end "reconciliation" "$S"
record "reconciliation" "SEE OUTPUT ABOVE — cross-checked against real legacy counts in the rehearsal report"

# ---------------------------------------------------------------------------
# E2E / application-level checks — real REST/RPC network calls, not raw SQL
# ---------------------------------------------------------------------------
echo "=== Rehearsal: application/E2E verification (real network calls) ==="
S="$(phase_start)"

# login admin: Palazzo Veneziano has no 'admin' role staff (real finding —
# only operatore x2 + master) — login is tested against the master and one
# operatore account instead, which is what the real roster actually has.
MASTER_TOKEN="$(login_password 'master-rehearsal@example.test' "$(pw_for_id "$MASTER_ID")")"
if [ "$MASTER_TOKEN" != "FAILED" ]; then record "e2e_login_master" "PASS"; else record "e2e_login_master" "FAIL"; fi

OP1_TOKEN="$(login_password 'operatore-rh-1@staff.local' "$(pw_for_id "$OP1_ID")")"
if [ "$OP1_TOKEN" != "FAILED" ]; then record "e2e_login_operatore_reception" "PASS"; else record "e2e_login_operatore_reception" "FAIL"; fi

OP3_TOKEN="$(login_password 'operatore-rh-3@staff.local' "$(pw_for_id "$OP3_ID")")"
if [ "$OP3_TOKEN" != "FAILED" ]; then record "e2e_login_operatore_housekeeping" "PASS"; else record "e2e_login_operatore_housekeeping" "FAIL"; fi

# roster: master (org-wide) must see all 3 real staff via staff_profiles REST
if [ "$MASTER_TOKEN" != "FAILED" ]; then
  ROSTER="$(call_rest "staff_profiles?hotel_id=eq.$HOTEL_ID&select=id" "$MASTER_TOKEN")"
  ROSTER_BODY="$(echo "$ROSTER" | sed '$d')"; ROSTER_STATUS="$(echo "$ROSTER" | tail -1)"
  ROSTER_COUNT="$(echo "$ROSTER_BODY" | jq 'length' 2>/dev/null || echo 0)"
  if [ "$ROSTER_STATUS" = "200" ] && [ "$ROSTER_COUNT" = "3" ]; then
    record "e2e_roster_master" "PASS (3 staff visible)"
  else
    record "e2e_roster_master" "FAIL (status=$ROSTER_STATUS count=$ROSTER_COUNT)"
  fi
fi

# guest request queue: both operatori are in departments that see the
# housekeeping-assigned queue (reception = front desk, sees everything;
# housekeeping sees its own department) -- both real open requests are
# assigned_department=housekeeping, so both should see 2 rows. NOTE: real
# data has no non-housekeeping open request, so the negative-isolation
# case (a department that should NOT see a given request) is not
# exercisable with real data alone -- reported as a coverage gap, not
# silently skipped.
if [ "$OP3_TOKEN" != "FAILED" ]; then
  Q="$(call_rest "guest_requests?hotel_id=eq.$HOTEL_ID&select=id,status,assigned_department" "$OP3_TOKEN")"
  Q_BODY="$(echo "$Q" | sed '$d')"; Q_STATUS="$(echo "$Q" | tail -1)"
  Q_COUNT="$(echo "$Q_BODY" | jq 'length' 2>/dev/null || echo 0)"
  if [ "$Q_STATUS" = "200" ] && [ "$Q_COUNT" = "2" ]; then
    record "e2e_guest_request_queue_housekeeping" "PASS (2 open requests visible, matches migrated count)"
  else
    record "e2e_guest_request_queue_housekeeping" "FAIL (status=$Q_STATUS count=$Q_COUNT)"
  fi
fi

# status change: accept the still-'requested' one as operatore-rh-3 (real
# network PATCH, respecting RLS -- not a direct SQL UPDATE)
if [ "$OP3_TOKEN" != "FAILED" ]; then
  PATCH_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "$API_URL/rest/v1/guest_requests?id=eq.5629576b-7819-4588-ab8d-477e49888ab6" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $OP3_TOKEN" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" -H "User-Agent: migration-script/1.0" \
    -d '{"status":"in_progress","accepted_at":"now()"}')"
  if [ "$PATCH_STATUS" = "204" ] || [ "$PATCH_STATUS" = "200" ]; then
    record "e2e_status_change" "PASS (real PATCH via REST, status=$PATCH_STATUS)"
  else
    record "e2e_status_change" "FAIL (status=$PATCH_STATUS)"
  fi
fi

# entitlement + PMS permission path: guest_requests_property_for_hotel +
# has_permission('guest_requests.pms.manage') for the master account (real
# RPC calls, same primitives sync-pms-stays uses)
if [ "$MASTER_TOKEN" != "FAILED" ]; then
  PROP_RESP="$(call_rpc "guest_requests_property_for_hotel" "{\"p_hotel_id\":\"$HOTEL_ID\"}" "$MASTER_TOKEN")"
  PROPERTY_ID="$(echo "$PROP_RESP" | sed '$d' | tr -d '"')"
  if [ -n "$PROPERTY_ID" ] && [ "$PROPERTY_ID" != "null" ]; then
    PERM_RESP="$(call_rpc "has_permission" "{\"p_property_id\":\"$PROPERTY_ID\",\"p_permission_slug\":\"guest_requests.pms.manage\"}" "$MASTER_TOKEN")"
    PERM_VALUE="$(echo "$PERM_RESP" | sed '$d')"
    if [ "$PERM_VALUE" = "true" ]; then
      record "e2e_entitlement_and_pms_permission" "PASS (master has guest_requests.pms.manage on the real property)"
    else
      record "e2e_entitlement_and_pms_permission" "FAIL (has_permission returned $PERM_VALUE)"
    fi
  else
    record "e2e_entitlement_and_pms_permission" "FAIL (guest_requests_property_for_hotel returned no property)"
  fi
fi

# cross-property denial: master (real account, org-scoped to Palazzo
# Veneziano's org) must be DENIED on Hotel X (separate synthetic org)
if [ "$MASTER_TOKEN" != "FAILED" ]; then
  DENY_RESP="$(call_rpc "guest_requests_staff_manage_allowed" '{"p_hotel_id":"88888888-0000-0000-0000-000000000001"}' "$MASTER_TOKEN")"
  DENY_VALUE="$(echo "$DENY_RESP" | sed '$d')"
  if [ "$DENY_VALUE" = "false" ]; then
    record "e2e_cross_property_denial" "PASS (master correctly denied on Hotel X, a separate organization)"
  else
    record "e2e_cross_property_denial" "FAIL (expected false, got $DENY_VALUE)"
  fi
fi
phase_end "e2e" "$S"

# ---------------------------------------------------------------------------
# Idempotent rerun
# ---------------------------------------------------------------------------
echo "=== Rehearsal: idempotent rerun ==="
S="$(phase_start)"
RERUN_OK=1
create_auth_user 'master-rehearsal@example.test' 'irrelevant' >/dev/null
DUP_COUNT="$(count_auth_users_by_email_prefix 'master-rehearsal@example.test')"
if [ "$DUP_COUNT" != "1" ]; then RERUN_OK=0; fi
if ! psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="$HOTEL_ID" -v hotel_name="$HOTEL_NAME" -v hotel_slug="$HOTEL_SLUG" \
    -f "$SCRIPT_DIR/10_migrate_hotel.sql"; then RERUN_OK=0; fi
POST_RERUN_COUNT="$(psql "$DB_URL" -tAc "select count(*) from guest_requests where hotel_id = '$HOTEL_ID'")"
if [ "$POST_RERUN_COUNT" != "2" ]; then RERUN_OK=0; fi
phase_end "idempotent_rerun" "$S"
if [ "$RERUN_OK" = "1" ]; then
  record "idempotent_rerun" "PASS (no duplicate auth user, guest_requests still =2 after rerun)"
else
  record "idempotent_rerun" "FAIL (dup_auth_count=$DUP_COUNT post_rerun_requests=$POST_RERUN_COUNT)"
fi

# ---------------------------------------------------------------------------
# Failure injections — reused unchanged from the dry-run, entirely
# synthetic, never touching real data (per explicit instruction not to
# risk real source data to simulate a failure)
# ---------------------------------------------------------------------------
echo "=== Rehearsal: mid-Auth failure injection (synthetic) ==="
S="$(phase_start)"
B1_ID="$(create_auth_user 'rehearsal-b-staff1@staff.local' 'HotelB!Pass1')"
B2_ID="FAILED"
if [ "$B1_ID" != "FAILED" ]; then
  B2_ID="$(create_auth_user 'rehearsal-b-staff1@staff.local' 'HotelB!Pass2')"
fi
if [ "$B1_ID" != "FAILED" ] && [ "$B2_ID" = "FAILED" ]; then
  delete_auth_user "$B1_ID"
  REMAINING="$(count_auth_users_by_email_prefix 'rehearsal-b-staff1')"
  if [ "$REMAINING" = "0" ]; then
    record "mid_auth_failure_cleanup" "PASS (0 orphaned rows, SQL phase correctly never ran)"
  else
    record "mid_auth_failure_cleanup" "FAIL (cleanup left $REMAINING orphaned row(s))"
  fi
else
  record "mid_auth_failure_cleanup" "FAIL (got B1=$B1_ID B2=$B2_ID)"
fi
phase_end "mid_auth_failure" "$S"

echo "=== Rehearsal: post-Auth SQL failure injection (synthetic) ==="
S="$(phase_start)"
C1_ID="$(create_auth_user 'rehearsal-c-staff1@staff.local' 'HotelC!Pass1')"
if [ "$C1_ID" != "FAILED" ]; then
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<SQL >/tmp/rehearsal_scenario_c.log 2>&1
begin;
insert into hotels (id, name, timezone, active)
  values ('99999999-0000-0000-0000-000000000099', 'Hotel Sample C Rehearsal', 'Europe/Rome', true)
  on conflict (id) do nothing;
insert into organizations (name, slug) values ('Hotel Sample C Rehearsal', 'hotel-sample-c-rehearsal') returning id \gset scenario_c_
insert into properties (organization_id, name, slug, timezone, status)
  values (:'scenario_c_id', 'Hotel Sample C Rehearsal', 'hotel-sample-c-rehearsal', 'Europe/Rome', 'active') returning id \gset scenario_c_prop_
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('99999999-0000-0000-0000-000000000099', :'scenario_c_prop_id');
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('99999999-0000-0000-0000-000000000099', :'scenario_c_prop_id');
commit;
SQL
  SQL_EXIT=$?
  POST_ROLLBACK_COUNT="$(psql "$DB_URL" -tAc "select count(*) from hotels where id = '99999999-0000-0000-0000-000000000099'")"
  if [ "$SQL_EXIT" != "0" ] && [ "$POST_ROLLBACK_COUNT" = "0" ]; then
    delete_auth_user "$C1_ID"
    REMAINING_C="$(count_auth_users_by_email_prefix 'rehearsal-c-staff1')"
    if [ "$REMAINING_C" = "0" ]; then
      record "post_auth_sql_failure_rollback" "PASS (transaction rolled back to 0 rows, orphaned Auth user cleaned up)"
    else
      record "post_auth_sql_failure_rollback" "FAIL (Auth cleanup left $REMAINING_C row(s))"
    fi
  else
    record "post_auth_sql_failure_rollback" "FAIL (sql_exit=$SQL_EXIT count=$POST_ROLLBACK_COUNT)"
  fi
else
  record "post_auth_sql_failure_rollback" "FAIL (could not create precondition Auth user)"
fi
phase_end "post_auth_sql_failure" "$S"

echo ""
echo "=== REHEARSAL SUMMARY ==="
for r in "${RESULTS[@]}"; do echo "$r"; done
echo ""
echo "=== TIMING (ms) ==="
for k in "${!T[@]}"; do echo "$k: ${T[$k]}"; done
echo "total_ms: $(elapsed_ms "$TOTAL_START")"
