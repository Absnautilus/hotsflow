#!/usr/bin/env bash
# Freeze mechanism rehearsal (runbook §3, cutover-readiness item E).
# Disposable local Supabase stack only -- never legacy production, never
# Hotsflow production. Reuses the dry-run's synthetic fixture (already
# validated) purely to get one real authenticated staff session to prove
# the freeze actually blocks/unblocks real writes, not just that the
# catalog rows look right.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRYRUN_DIR="$(cd "$SCRIPT_DIR/../dry-run" && pwd)"
source "$DRYRUN_DIR/lib.sh"
init_connection_vars

RESULTS=()
record() { RESULTS+=("$1: $2"); echo ">>> $1: $2"; }

# ---------------------------------------------------------------------------
# Fixture: reuse the dry-run's already-validated synthetic hotel + staff.
# ---------------------------------------------------------------------------
echo "=== Freeze rehearsal: seeding fixture (dry-run's synthetic hotel) ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$DRYRUN_DIR/00_seed_legacy_synthetic.sql" >/dev/null
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "create table if not exists auth_remap (legacy_auth_user_id uuid primary key, new_auth_user_id uuid not null); truncate auth_remap;" >/dev/null
ADMIN_ID="$(create_auth_user 'freeze-admin@example.test' 'FreezeAdmin!234')"
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "insert into auth_remap values ('99999999-0000-0000-0000-0000000000a1','$ADMIN_ID');" >/dev/null
psql "$DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="99999999-0000-0000-0000-000000000001" \
  -v hotel_name="Hotel Sample E2E Dry-Run" -v hotel_slug="hotel-sample-e2e-dryrun-freeze" \
  -f "$DRYRUN_DIR/10_migrate_hotel.sql" >/dev/null
TOKEN="$(login_password 'freeze-admin@example.test' 'FreezeAdmin!234')"
if [ "$TOKEN" = "FAILED" ]; then record "fixture" "FAIL (could not log in)"; exit 1; fi
# Login alone doesn't prove the migration transaction actually committed
# (10_migrate_hotel.sql is one transaction -- a failure on any later step,
# e.g. guest_requests, rolls back the hotel/property/membership/staff rows
# too, and Auth user creation happens outside that transaction so login
# would still succeed even though nothing else exists). Verify the rows
# that attempt_write()/attempt_read() actually depend on are really there.
FIXTURE_ROWS="$(psql "$DB_URL" -tAc "select count(*) from guest_requests where hotel_id = '99999999-0000-0000-0000-000000000001'")"
if [ "$FIXTURE_ROWS" -lt 1 ]; then
  record "fixture" "FAIL (login succeeded but migration did not land: guest_requests rows=$FIXTURE_ROWS -- check 10_migrate_hotel.sql output above)"
  exit 1
fi
record "fixture" "PASS ($FIXTURE_ROWS guest_requests rows migrated)"

attempt_write() {  # returns the HTTP status of a real INSERT via REST
  curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/rest/v1/guest_requests" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" -H "User-Agent: freeze-test/1.0" \
    -d '{"hotel_id":"99999999-0000-0000-0000-000000000001","stay_id":"99999999-0000-0000-0000-000000004001","room_number":"101","request_type_id":"99999999-0000-0000-0000-000000030001","status":"requested","assigned_department":"housekeeping"}'
}
attempt_read() {  # returns the HTTP status of a real SELECT via REST
  curl -s -o /dev/null -w '%{http_code}' "$API_URL/rest/v1/guest_requests?hotel_id=eq.99999999-0000-0000-0000-000000000001&select=id" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" -H "User-Agent: freeze-test/1.0"
}

echo "=== Item 1: sanity — write succeeds BEFORE any freeze ==="
PRE_STATUS="$(attempt_write)"
if [ "$PRE_STATUS" = "201" ]; then record "pre_freeze_write_sanity" "PASS (status=$PRE_STATUS)"; else record "pre_freeze_write_sanity" "FAIL (status=$PRE_STATUS)"; fi

echo "=== Item 2: snapshot ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/01_snapshot.sql" | tee /tmp/freeze_snapshot_output.txt
SNAPSHOT_COUNT="$(psql "$DB_URL" -tAc "select count(*) from _freeze_acl_snapshot")"
if [ "$SNAPSHOT_COUNT" -gt 0 ]; then record "snapshot" "PASS ($SNAPSHOT_COUNT ACL rows captured)"; else record "snapshot" "FAIL (empty snapshot)"; fi

echo "=== Item 3: REVOKE ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/02_revoke.sql"
POST_REVOKE_STATUS="$(attempt_write)"
if [ "$POST_REVOKE_STATUS" = "403" ] || [ "$POST_REVOKE_STATUS" = "401" ]; then
  record "revoke_blocks_write" "PASS (write correctly rejected, status=$POST_REVOKE_STATUS)"
else
  record "revoke_blocks_write" "FAIL (expected 401/403, got $POST_REVOKE_STATUS — freeze did not block the write)"
fi

echo "=== Item 4: reads still work during freeze ==="
READ_STATUS="$(attempt_read)"
if [ "$READ_STATUS" = "200" ]; then record "reads_still_work" "PASS (status=$READ_STATUS)"; else record "reads_still_work" "FAIL (status=$READ_STATUS)"; fi

echo "=== Item 5: RESTORE (same run) and verify exact ACL match ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/03_restore.sql" | tee /tmp/freeze_restore_output.txt
MISSING="$(psql "$DB_URL" -tAc "select count(*) from (select * from _freeze_acl_snapshot except select * from _freeze_acl_after) x")"
OVERSHOOT="$(psql "$DB_URL" -tAc "select count(*) from (select * from _freeze_acl_after except select * from _freeze_acl_snapshot) x")"
if [ "$MISSING" = "0" ] && [ "$OVERSHOOT" = "0" ]; then
  record "restore_exact_match" "PASS (0 missing, 0 overshoot — ACL identical to pre-freeze snapshot)"
else
  record "restore_exact_match" "FAIL (missing=$MISSING overshoot=$OVERSHOOT)"
fi

echo "=== Item 6: functional confirmation — write succeeds again after restore ==="
POST_RESTORE_STATUS="$(attempt_write)"
if [ "$POST_RESTORE_STATUS" = "201" ]; then record "post_restore_write" "PASS (status=$POST_RESTORE_STATUS)"; else record "post_restore_write" "FAIL (status=$POST_RESTORE_STATUS)"; fi

echo "=== Item 7: failure scenario — crash between REVOKE and GRANT, recover from a separate session ==="
# Re-snapshot + re-revoke fresh (state is currently open from item 6).
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/01_snapshot.sql" >/dev/null
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/02_revoke.sql" >/dev/null
CRASH_STATUS="$(attempt_write)"
echo "Simulating a crash here: the process that ran REVOKE exits without running RESTORE."
echo "Recovery procedure: from ANY session, with the persisted _freeze_acl_snapshot table"
echo "still present (it is a real table, not a session-scoped temp table), run:"
echo "  psql \"\$DB_URL\" -f $SCRIPT_DIR/03_restore.sql"
# Recover from a brand-new, independent psql invocation -- proves the
# snapshot table (not any in-memory state) is what recovery depends on.
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/03_restore.sql" >/dev/null
RECOVERY_STATUS="$(attempt_write)"
MISSING2="$(psql "$DB_URL" -tAc "select count(*) from (select * from _freeze_acl_snapshot except select * from _freeze_acl_after) x")"
OVERSHOOT2="$(psql "$DB_URL" -tAc "select count(*) from (select * from _freeze_acl_after except select * from _freeze_acl_snapshot) x")"
if [ "$CRASH_STATUS" != "201" ] && [ "$RECOVERY_STATUS" = "201" ] && [ "$MISSING2" = "0" ] && [ "$OVERSHOOT2" = "0" ]; then
  record "failure_scenario_recovery" "PASS (blocked during simulated crash: status=$CRASH_STATUS; recovered from a separate session: status=$RECOVERY_STATUS, ACL exact match)"
else
  record "failure_scenario_recovery" "FAIL (crash_status=$CRASH_STATUS recovery_status=$RECOVERY_STATUS missing=$MISSING2 overshoot=$OVERSHOOT2)"
fi

echo ""
echo "=== FREEZE REHEARSAL SUMMARY ==="
FAILED=0
for r in "${RESULTS[@]}"; do
  echo "$r"
  [[ "$r" == *": FAIL"* ]] && FAILED=1
done

# A green job here must mean every check actually recorded PASS, not just
# that the script ran to completion -- set -uo pipefail alone does not
# stop the script on a failed check (checks are expected to fail and be
# recorded, not to abort the run), so the pass/fail verdict has to be
# enforced explicitly as the job's own exit code.
if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "FREEZE REHEARSAL: FAIL (see above)"
  exit 1
fi
echo ""
echo "FREEZE REHEARSAL: PASS"
