#!/usr/bin/env bash
# Shared functions for the dry-run and rehearsal orchestrators -- one
# implementation, not duplicated per run, per explicit instruction. Source
# this after `set -uo pipefail`; expects DB_URL, API_URL, ANON_KEY,
# SERVICE_ROLE_KEY already set by the caller.

RESULTS=()
record() { RESULTS+=("$1: $2"); echo ">>> $1: $2"; }

create_auth_user() {  # $1=email $2=password -> prints new id on stdout, or "FAILED"
  local email="$1" password="$2" resp status body
  resp="$(curl -s -w '\n%{http_code}' -X POST "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" -H "User-Agent: migration-script/1.0" \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"email_confirm\":true}")"
  status="$(echo "$resp" | tail -1)"; body="$(echo "$resp" | sed '$d')"
  if [ "$status" = "200" ]; then echo "$body" | jq -r '.id'; else echo "FAILED"; fi
}

delete_auth_user() {
  curl -s -X DELETE "$API_URL/auth/v1/admin/users/$1" \
    -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "User-Agent: migration-script/1.0" >/dev/null
}

count_auth_users_by_email_prefix() {  # $1=prefix -> count
  psql "$DB_URL" -tAc "select count(*) from auth.users where email like '$1%'"
}

login_password() {  # $1=email $2=password -> prints access_token, or "FAILED"
  local resp
  resp="$(curl -s -X POST "$API_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -H "User-Agent: migration-script/1.0" \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}")"
  echo "$resp" | jq -r '.access_token // "FAILED"'
}

# Calls a Postgres RPC as an authenticated user (bearer token from
# login_password) via PostgREST. $1=function name, $2=json args, $3=token.
call_rpc() {
  curl -s -w '\n%{http_code}' -X POST "$API_URL/rest/v1/rpc/$1" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $3" \
    -H "Content-Type: application/json" -H "User-Agent: migration-script/1.0" \
    -d "$2"
}

# REST select as an authenticated user (RLS-scoped). $1=table+query-string, $2=token.
call_rest() {
  curl -s -w '\n%{http_code}' -X GET "$API_URL/rest/v1/$1" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $2" \
    -H "User-Agent: migration-script/1.0"
}

now_ms() { date +%s%3N; }
elapsed_ms() { echo "$(( $(now_ms) - $1 ))"; }

init_connection_vars() {
  DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
  STATUS_JSON="$(supabase status -o json)"
  echo "supabase status -o json: $STATUS_JSON"
  API_URL="$(echo "$STATUS_JSON" | jq -r '.API_URL')"
  # This CLI's local stack prints the newer Publishable/Secret key names
  # (see the CI "Authentication Keys" table) rather than legacy
  # ANON_KEY/SERVICE_ROLE_KEY -- try both, never assume one.
  SERVICE_ROLE_KEY="$(echo "$STATUS_JSON" | jq -r '.SERVICE_ROLE_KEY // .SECRET_KEY // empty')"
  ANON_KEY="$(echo "$STATUS_JSON" | jq -r '.ANON_KEY // .PUBLISHABLE_KEY // empty')"
}
