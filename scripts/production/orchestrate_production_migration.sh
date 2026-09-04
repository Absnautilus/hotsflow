#!/usr/bin/env bash
# Production Migration orchestrator. Unlike the dry-run/rehearsal/freeze
# orchestrators (which deliberately continue past a failed check so every
# result gets recorded), this one is a REAL production run: `set -e`
# means it stops at the FIRST failure, on purpose -- there is no "collect
# all results" mode for something that writes real data.
#
# Never prints PII: every step that touches row-level legacy data reads
# or writes a LOCAL FILE (psql -o / a CSV), never stdout. Only count-only
# or structural output (VALIDATION, PREFLIGHT, RECONCILIATION) is ever
# printed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

: "${LEGACY_RO_DB_URL:?LEGACY_RO_DB_URL must be set (read-only legacy connection)}"
: "${TARGET_DB_URL:?TARGET_DB_URL must be set (Hotsflow)}"
: "${TARGET_API_URL:?TARGET_API_URL must be set (Hotsflow)}"
: "${TARGET_SERVICE_ROLE_KEY:?TARGET_SERVICE_ROLE_KEY must be set (Hotsflow)}"
: "${LEGACY_HOTEL_ID:?LEGACY_HOTEL_ID must be set}"
: "${HOTEL_NAME:?HOTEL_NAME must be set}"
: "${HOTEL_SLUG:?HOTEL_SLUG must be set}"

WORKDIR="${RUNNER_TEMP:-/tmp}/migration-workspace"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR"

cleanup() {
  local exit_code=$?
  echo "=== Cleanup: removing $WORKDIR (always runs) ==="
  rm -rf "$WORKDIR"
  if [ -d "$WORKDIR" ]; then
    echo "!!! CLEANUP FAILED: $WORKDIR still exists"
    exit 1
  fi
  echo "Cleanup confirmed: workspace removed."
  exit $exit_code
}
trap cleanup EXIT

echo "=== 0. Frozen artifact integrity: 10_migrate_hotel.sql / 20_reconciliation.sql unchanged since aed67fc ==="
cd "$REPO_ROOT"
FROZEN_BASELINE="aed67fc5b0ce93ba123fd12bcb3bbb707092f6d7"
FROZEN_DIFF="$(git diff "$FROZEN_BASELINE" HEAD -- scripts/dry-run/10_migrate_hotel.sql scripts/dry-run/20_reconciliation.sql)"
if [ -n "$FROZEN_DIFF" ]; then
  echo "!!! ABORT: frozen migration/reconciliation script(s) differ from the validated cutover baseline $FROZEN_BASELINE."
  echo "!!! Refusing to run against a script that was never reviewed."
  exit 1
fi
echo "Frozen scripts confirmed byte-identical to cutover baseline $FROZEN_BASELINE."

echo "=== 1. Hard gate: refuse to run if this hotel is already migrated ==="
ALREADY_MIGRATED="$(psql "$TARGET_DB_URL" -tAc "select count(*) from hotels where id = '$LEGACY_HOTEL_ID'")"
if [ "$ALREADY_MIGRATED" != "0" ]; then
  echo "!!! ABORT: hotel $LEGACY_HOTEL_ID already exists on the target. Refusing to run again."
  echo "!!! (10_migrate_hotel.sql's own ON CONFLICT DO NOTHING is a second, independent safeguard -- this gate is the first.)"
  exit 1
fi
echo "Target does not yet have this hotel. Proceeding."

echo "=== 2. PRE-FLIGHT (legacy, read-only, non-mutative) ==="
psql "$LEGACY_RO_DB_URL" -v ON_ERROR_STOP=1 -v legacy_hotel_id="$LEGACY_HOTEL_ID" -f "$SCRIPT_DIR/00_preflight_checks.sql"

echo "=== 3. VALIDATION (legacy, read-only) ==="
ANOMALY_COUNT="$(psql "$LEGACY_RO_DB_URL" -v ON_ERROR_STOP=1 -v legacy_hotel_id="$LEGACY_HOTEL_ID" -f "$SCRIPT_DIR/01_validate_legacy.sql" | tail -1)"
if [ "$ANOMALY_COUNT" != "0" ]; then
  echo "!!! ABORT: VALIDATION found $ANOMALY_COUNT anomalous row(s). Not proceeding to EXPORT."
  exit 1
fi
echo "VALIDATION: 0 anomalies."

echo "=== 4. EXPORT (legacy, read-only -- output goes to a local file, never stdout) ==="
psql "$LEGACY_RO_DB_URL" -v ON_ERROR_STOP=1 -v legacy_hotel_id="$LEGACY_HOTEL_ID" -f "$SCRIPT_DIR/02_export_legacy.sql" -o "$WORKDIR/import.sql" -t -A
chmod 600 "$WORKDIR/import.sql"
IMPORT_LINES="$(wc -l < "$WORKDIR/import.sql")"
echo "Export complete: $IMPORT_LINES insert statement(s) written to a local file (content never printed)."

echo "=== 5. Stage on target: create legacy_source schema, import ==="
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/03_create_staging_schema.sql"
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -f "$WORKDIR/import.sql" >/dev/null

echo "=== 6. AUTH MIGRATION ==="
psql "$TARGET_DB_URL" -tAc "select id, email from legacy_source.staff_profiles" -F',' > "$WORKDIR/staff.csv"
chmod 600 "$WORKDIR/staff.csv"
DB_URL="$TARGET_DB_URL" API_URL="$TARGET_API_URL" SERVICE_ROLE_KEY="$TARGET_SERVICE_ROLE_KEY" \
  "$SCRIPT_DIR/05_auth_migrate.sh" "$WORKDIR/staff.csv"

echo "=== 7. SQL MIGRATION (frozen, unmodified) ==="
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=1 -v hotel_id="$LEGACY_HOTEL_ID" -v hotel_name="$HOTEL_NAME" -v hotel_slug="$HOTEL_SLUG" \
  -f "$REPO_ROOT/scripts/dry-run/10_migrate_hotel.sql"

echo "=== 8. RECONCILIATION (frozen, unmodified) + source/target comparison ==="
echo "--- target counts ---"
psql "$TARGET_DB_URL" -v hotel_id="$LEGACY_HOTEL_ID" -f "$REPO_ROOT/scripts/dry-run/20_reconciliation.sql"
echo "--- legacy source counts (for comparison, count-only, no PII) ---"
psql "$LEGACY_RO_DB_URL" -v legacy_hotel_id="$LEGACY_HOTEL_ID" -f "$SCRIPT_DIR/04_legacy_source_counts.sql"

echo ""
echo "=== PRODUCTION MIGRATION: COMPLETE ==="
echo "Review the RECONCILIATION and legacy source counts above: hotels/staff/rooms/categories/types/stays_active must match 1:1; guest_requests_migrated must equal legacy guest_requests_open exactly (closed/cancelled stays and completed/cancelled/archived requests are intentionally excluded per the migration plan, not unexpected loss)."
