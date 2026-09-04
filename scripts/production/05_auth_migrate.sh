#!/usr/bin/env bash
# Production migration -- AUTH MIGRATION. Reads (legacy_id,email) pairs
# from a LOCAL FILE (never stdin/stdout, never echoed), creates or safely
# reuses one Hotsflow Auth user per pair, and populates the permanent
# `auth_remap` table 10_migrate_hotel.sql depends on.
#
# Existing target Auth identities are reused only when the staged email has
# exactly one case-insensitive match in auth.users. Existing users are never
# modified or deleted. Zero matches means create a new Auth user; more than
# one match is treated as an ambiguity and fails closed.
#
# Passwords are never carried over from legacy (never read, never available
# to this script). A fresh deterministic value is generated only for genuinely
# new Auth users. Staff must reset it after migration.
#
# On a failed creation, prints only the sanitized diagnostic implemented in
# lib.sh. Never prints email/password/service-role key or a raw API body.
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
REUSED=0
FAILED=0

# File, not a variable: create_auth_user is invoked through command
# substitution, therefore it runs in a subshell. The file carries the
# sanitized diagnostic back across that subshell boundary.
AUTH_CREATE_ERROR_FILE="$(mktemp)"
export AUTH_CREATE_ERROR_FILE

cleanup_on_failure() {
  rm -f "$AUTH_CREATE_ERROR_FILE"
  if [ "$FAILED" = "1" ]; then
    if [ "${#CREATED_IDS[@]}" -gt 0 ]; then
      echo "=== Auth migration failed -- rolling back ${#CREATED_IDS[@]} newly-created user(s) ==="
      for id in "${CREATED_IDS[@]}"; do
        delete_auth_user "$id"
      done
    fi
    # Clear mappings even when every mapped identity was reused and no new
    # Auth user had yet been created. A failed Auth phase must leave no
    # auth_remap residue from the attempted run.
    psql "$DB_URL" -v ON_ERROR_STOP=1 -c "truncate auth_remap;" >/dev/null
    echo "=== Auth rollback complete: auth_remap cleared; pre-existing Auth users untouched ==="
  fi
}
trap cleanup_on_failure EXIT

while IFS=, read -r legacy_id email; do
  [ -z "$legacy_id" ] && continue

  existing_count="$(psql "$DB_URL" -v ON_ERROR_STOP=1 -v email="$email" -tAc \
    "select count(*) from auth.users where lower(email) = lower(:'email');")"

  if [ "$existing_count" = "1" ]; then
    existing_id="$(psql "$DB_URL" -v ON_ERROR_STOP=1 -v email="$email" -tAc \
      "select id from auth.users where lower(email) = lower(:'email') limit 1;")"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -c \
      "insert into auth_remap (legacy_auth_user_id, new_auth_user_id) values ('$legacy_id','$existing_id') on conflict (legacy_auth_user_id) do update set new_auth_user_id = excluded.new_auth_user_id;" >/dev/null
    MAPPED=$((MAPPED + 1))
    REUSED=$((REUSED + 1))
    echo ">>> auth_identity_reuse: PASS (exact existing target Auth identity reused; PII withheld)"
    continue
  fi

  if [ "$existing_count" != "0" ]; then
    echo "!!! Auth identity lookup ambiguous for legacy_id=$legacy_id (email withheld from log; exact-email matches=$existing_count)"
    FAILED=1
    break
  fi

  pw="$(pw_for_id "$legacy_id")"
  : > "$AUTH_CREATE_ERROR_FILE"
  new_id="$(create_auth_user "$email" "$pw")"
  if [ "$new_id" = "FAILED" ]; then
    diagnostic="$(cat "$AUTH_CREATE_ERROR_FILE" 2>/dev/null)"
    echo "!!! Auth user creation failed for legacy_id=$legacy_id (email withheld from log) -- diagnostic: ${diagnostic:-no diagnostic available}"
    FAILED=1
    break
  fi

  CREATED_IDS+=("$new_id")
  psql "$DB_URL" -v ON_ERROR_STOP=1 -c \
    "insert into auth_remap (legacy_auth_user_id, new_auth_user_id) values ('$legacy_id','$new_id') on conflict (legacy_auth_user_id) do update set new_auth_user_id = excluded.new_auth_user_id;" >/dev/null
  MAPPED=$((MAPPED + 1))
done < "$STAFF_CSV"

if [ "$FAILED" = "1" ]; then
  echo ">>> auth_migration: FAIL"
  exit 1
fi

echo ">>> auth_migration: PASS ($MAPPED staff mapped; $REUSED existing Auth identities reused)"
