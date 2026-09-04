-- E2E TEST ONLY -- never run against real legacy. Creates a schema-shape
-- double of legacy's public tables (matching Absnautilus/Housekeeping's
-- migrations closely enough for 00_preflight_checks.sql /
-- 01_validate_legacy.sql / 02_export_legacy.sql to run against it
-- faithfully) plus a minimal `auth.users(id, email)` stub, on a plain
-- disposable Postgres container -- deliberately NOT a full Supabase
-- stack for this side (no triggers/RLS/functions replayed; those are out
-- of scope for testing the migration mechanism itself).
--
-- TWO SEPARATE canary values, deliberately not one, so the log-leak test
-- can tell apart "this is a harmless, expected label" from "this is
-- PII-shaped data that must never be printed":
--
--   1. RUN_CANARY (-v canary=<random-string>, passed on the command line
--      by the workflow): used ONLY for the hotel's own name. A hotel
--      name is a business label, not personal data -- it is expected to
--      appear in HOTEL_NAME env, command echoes and reconciliation
--      output, exactly like "Palazzo Veneziano" would in production.
--
--   2. PII_CANARY: a FIXED literal, hardcoded below, used ONLY inside
--      the fields that stand in for real PII in the legacy schema --
--      staff name, staff login_username, auth.users.email, and
--      stays.guest_last_name. Deliberately NOT passed as a `-v` psql
--      variable and NOT derived from any `${{ }}` GitHub Actions
--      expression anywhere in the workflow -- it lives only in this
--      checked-in file's literal SQL text, so it can never appear on a
--      command line or in a step's env: echo. The E2E workflow's
--      `canary-log-scan` job greps the complete log of every job for
--      this exact literal and fails the run if it finds even one
--      occurrence -- that is the real test of whether the migration
--      mechanism ever lets PII-shaped data reach stdout.
\set pii_canary zzpiicanary7f2e9b4a1c
--
-- Requires -v canary=<random-string> (RUN_CANARY only).
\set ON_ERROR_STOP on

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);

create table hotels (id uuid primary key, name text not null, timezone text not null default 'Europe/Rome', active boolean not null default true, created_at timestamptz not null default now());
create table staff_profiles (id uuid primary key, hotel_id uuid not null references hotels(id), auth_user_id uuid not null unique references auth.users(id), name text not null, role text not null check (role in ('admin','operatore','master')), department text check (department in ('housekeeping','reception','maintenance','porter')), active boolean not null default true, login_username text unique, created_at timestamptz not null default now());
create table rooms (id uuid primary key, hotel_id uuid not null references hotels(id), room_number text not null, active boolean not null default true, unique (hotel_id, room_number));
create table stays (id uuid primary key, hotel_id uuid not null references hotels(id), room_id uuid not null references rooms(id), guest_last_name text not null, check_in_at timestamptz not null, check_out_at timestamptz not null, status text not null default 'active' check (status in ('active','closed','cancelled')), source text not null default 'manual' check (source in ('manual','opera')), external_stay_id text, created_by uuid references staff_profiles(id));
create table request_categories (id uuid primary key, hotel_id uuid not null references hotels(id), name text not null, department text not null check (department in ('housekeeping','reception','maintenance','porter')), icon text, active boolean not null default true, sort_order int not null default 0);
create table request_types (id uuid primary key, category_id uuid not null references request_categories(id), name text not null, description text, allows_quantity boolean not null default false, active boolean not null default true, sort_order int not null default 0, available_quantity int);
create table guest_requests (id uuid primary key, hotel_id uuid not null references hotels(id), stay_id uuid references stays(id), room_number text not null, request_type_id uuid not null references request_types(id), quantity int, status text not null default 'requested' check (status in ('requested','in_progress','completed','cancelled')), assigned_department text not null check (assigned_department in ('housekeeping','reception','maintenance','porter')), accepted_by uuid references staff_profiles(id), created_at timestamptz not null default now(), accepted_at timestamptz, completed_at timestamptz, priority bigint not null default 1, created_by_staff uuid references staff_profiles(id), archived_at timestamptz, returned_at timestamptz);

insert into hotels values ('cccccccc-0000-0000-0000-000000000001', 'ZZCANARY_HOTEL_' || :'canary', 'Europe/Rome', true);

insert into auth.users (id, email) values
  ('cccccccc-0000-0000-0000-0000000000a1', :'pii_canary' || '-master@example.test'),
  ('cccccccc-0000-0000-0000-0000000000a2', :'pii_canary' || '-op1@example.test'),
  ('cccccccc-0000-0000-0000-0000000000a3', :'pii_canary' || '-op2@example.test');

insert into staff_profiles (id, hotel_id, auth_user_id, name, role, department, active, login_username) values
  ('cccccccc-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000a1', 'PIICANARY Master ' || :'pii_canary', 'master', null, true, null),
  ('cccccccc-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000a2', 'PIICANARY Op Reception ' || :'pii_canary', 'operatore', 'reception', true, :'pii_canary' || '-op1'),
  ('cccccccc-0000-0000-0000-0000000000a3', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-0000000000a3', 'PIICANARY Op Housekeeping ' || :'pii_canary', 'operatore', 'housekeeping', true, :'pii_canary' || '-op2');

insert into rooms values
  ('cccccccc-0000-0000-0000-000000001001', 'cccccccc-0000-0000-0000-000000000001', '101', true),
  ('cccccccc-0000-0000-0000-000000001002', 'cccccccc-0000-0000-0000-000000000001', '102', true);

insert into request_categories values
  ('cccccccc-0000-0000-0000-000000002001', 'cccccccc-0000-0000-0000-000000000001', 'Housekeeping', 'housekeeping', null, true, 0);

insert into request_types values
  ('cccccccc-0000-0000-0000-000000003001', 'cccccccc-0000-0000-0000-000000002001', 'Extra towels', null, true, true, 0, null);

insert into stays values
  ('cccccccc-0000-0000-0000-000000004001', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000001001', 'PIICANARY Guest ' || :'pii_canary', now() - interval '1 day', now() + interval '1 day', 'active', 'manual', null, 'cccccccc-0000-0000-0000-0000000000a2');

insert into guest_requests (id, hotel_id, stay_id, room_number, request_type_id, status, assigned_department, priority, created_at) values
  ('cccccccc-0000-0000-0000-000000005001', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000004001', '101', 'cccccccc-0000-0000-0000-000000003001', 'requested', 'housekeeping', 1, now()),
  ('cccccccc-0000-0000-0000-000000005002', 'cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000004001', '101', 'cccccccc-0000-0000-0000-000000003001', 'in_progress', 'housekeeping', 2, now());
