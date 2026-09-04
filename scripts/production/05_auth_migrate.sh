#!/usr/bin/env bash
# Production migration -- AUTH MIGRATION. Reads (legacy_id,email) pairs
# from a LOCAL FILE (never stdin/stdout, never echoed), creates one
# Hotsflow Auth user per pair via the Admin API (reusing lib.sh's
# create_auth_user/delete_auth_user unchanged -- no second
# implementation), and populates the permanent `auth_remap` table
# 10_migrate_hotel.sql depends on. On the FIRST failed creation, deletes
# every user already created in this run and exits nonzero -- the caller
# (orchestrate_production_migration.sh) must not proceed to SQL MIGRATION
# if this script exits nonzero.
#
# Passwords are never carried over from legacy (never read, never
# available to this script at all) -- a fresh, deterministic value is
# generated from the legacy id, same approach already validated in the
# rehearsal. Staff must reset it after migration; this script's job is
# only to create a working account, not to preserve a real credential.
#
# On a failed creation, prints a sanitized diagnostic alongside the
# legacy_id -- HTTP status plus the Admin API's .code/.error_code/.msg/
# .message fields only (lib.sh's create_auth_user/sanitize_auth_error;
# real run 33884207538 hit this exact FAILED path with only "creation
# failed" and no usable reason, since the prior version of create_auth_user
# discarded the response body entirely on non-200). Never the full
# response body, never email/password/service-role key -- see lib.sh for
# the exact field allowlist and the defense-in-depth email-pattern
# scrub applied to each field before it is ever printed.
#
# Usage: DB_URL=... API_URL=... SERVICE_ROLE_KEY=... \
#   05_auth_migrate.sh <staff_csv_path>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../dry-run/lib.sh
source "$SCRIPT_DIR/../dry-run/lib.sh"

: "${DB_URL:?DB_URL must be set (target Hotsflow)}"
: "${API_URL:?API_URL must be set (target Hotsflow)}"
: "${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY must be set (target Hotsflow)}"

STAFF_CSV="${1:?usage: 05_auth_migrate.sh <staff_csv_path>}"
if [ ! -f "$STAFF_CSV" ]; then
  echo "!!! staff CSV not found: $STAFF_CSV"
  exit 1
fi

pw_for_id() { echo "Migrated$(echo "$1" | tr -dc '0-9' | cut -c1-8)!Aa"; }

psql "$DB_URL" -v ON_ERROR_STOP=1 -c \
  "create table if not exists auth_remap (legacy_auth_user_id uuid primary key, new_auth_user_id uuid not null);" >/dev/null

CREATED_IDS=()
MAPPED=0
FAILED=0

cleanup_on_failure() {
  if [ "$FAILED" = "1" ] && [ "${#CREATED_IDS[@]}" -gt 0 ]; then
    echo "=== Auth migration failed -- rolling back ${#CREATED_IDS[@]} already-created user(s) ==="
    for id in "${CREATED_IDS[@]}"; do
      delete_auth_user "$id"
    done
    psql "$DB_URL" -v ON_ERROR_STOP=1 -c "truncate auth_remap;" >/dev/null
    echo "=== Rollback complete: 0 Auth users, 0 auth_remap rows remain from this run ==="
  fi
}
trap cleanup_on_failure EXIT

while IFS=, read -r legacy_id email; do
  [ -z "$legacy_id" ] && continue
  pw="$(pw_for_id "$legacy_id")"
  new_id="$(create_auth_user "$email" "$pw")"
  if [ "$new_id" = "FAILED" ]; then
    echo "!!! Auth user creation failed for legacy_id=$legacy_id (email withheld from log) -- diagnostic: ${AUTH_CREATE_LAST_ERROR:-no diagnostic available}"
    FAILED=1
    break
  fi
  CREATED_IDS+=("$new_id")
  psql "$DB_URL" -v ON_ERROR_STOP=1 -c "insert into auth_remap (legacy_auth_user_id, new_auth_user_id) values ('$legacy_id','$new_id') on conflict (legacy_auth_user_id) do nothing;" >/dev/null
  MAPPED=$((MAPPED + 1))
done < "$STAFF_CSV"

if [ "$FAILED" = "1" ]; then
  echo ">>> auth_migration: FAIL (0 staff mapped after rollback)"
  exit 1
fi

echo ">>> auth_migration: PASS ($MAPPED staff mapped)"
