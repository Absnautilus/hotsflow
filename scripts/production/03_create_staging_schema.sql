-- Production migration -- creates the `legacy_source` staging schema on
-- the TARGET (Hotsflow) database, run before importing the file
-- 02_export_legacy.sql generated. Same fixed shape already used by the
-- dry-run's and the rehearsal's seed scripts (see
-- scripts/dry-run/00_seed_legacy_synthetic.sql) -- one shared shape, not
-- a second definition. No `password` column here: production never
-- carries a legacy password anywhere (a fresh, deterministic one is
-- generated at Auth-creation time instead), so the staging schema never
-- has a place to put one.
\set ON_ERROR_STOP on

create schema if not exists legacy_source;

drop table if exists legacy_source.guest_requests, legacy_source.stays,
  legacy_source.request_types, legacy_source.request_categories,
  legacy_source.rooms, legacy_source.staff_profiles cascade;

create table legacy_source.staff_profiles (id uuid primary key, hotel_id uuid, email text, name text, role text, department text, active boolean, login_username text);
create table legacy_source.rooms (id uuid primary key, hotel_id uuid, room_number text, active boolean);
create table legacy_source.request_categories (id uuid primary key, hotel_id uuid, name text, department text, icon text, active boolean default true, sort_order int);
create table legacy_source.request_types (id uuid primary key, category_id uuid, name text, description text, allows_quantity boolean, active boolean default true, sort_order int default 0, available_quantity int);
create table legacy_source.stays (id uuid primary key, hotel_id uuid, room_id uuid, guest_last_name text, check_in_at timestamptz, check_out_at timestamptz, status text, source text, external_stay_id text, created_by uuid);
create table legacy_source.guest_requests (id uuid primary key, hotel_id uuid, stay_id uuid, room_number text, request_type_id uuid, quantity int, status text, assigned_department text, accepted_by uuid, created_at timestamptz, accepted_at timestamptz, completed_at timestamptz, priority bigint, created_by_staff uuid, archived_at timestamptz, returned_at timestamptz);
