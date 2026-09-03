-- Dry-run only: stands in for "export from the legacy Housekeeping
-- project". Synthetic data, no PII, shaped to match the real production
-- hotel's row counts confirmed in docs/production-data-migration-plan.md
-- §A (1 hotel, 3 staff, 7 rooms, 6 categories, 12 types, 4 stays/1
-- active, 25 requests/2 open). Fixed deterministic ids so reruns and
-- reconciliation queries are stable.
--
-- Schema is `legacy_source` -- the same fixed name the rehearsal's real
-- (anonymized) seed also writes to, so 10_migrate_hotel.sql /
-- 20_reconciliation.sql are one shared script for both, not a duplicate
-- implementation per run.
create schema if not exists legacy_source;

drop table if exists legacy_source.guest_requests, legacy_source.stays,
  legacy_source.request_types, legacy_source.request_categories,
  legacy_source.rooms, legacy_source.staff_profiles, legacy_source.hotels cascade;

create table legacy_source.hotels (id uuid primary key, name text, timezone text, active boolean);
create table legacy_source.staff_profiles (id uuid primary key, hotel_id uuid, email text, name text, role text, department text, active boolean, login_username text, password text);
create table legacy_source.rooms (id uuid primary key, hotel_id uuid, room_number text, active boolean);
create table legacy_source.request_categories (id uuid primary key, hotel_id uuid, name text, department text, icon text, active boolean default true, sort_order int);
create table legacy_source.request_types (id uuid primary key, category_id uuid, name text, description text, allows_quantity boolean, active boolean default true, sort_order int default 0, available_quantity int);
create table legacy_source.stays (id uuid primary key, hotel_id uuid, room_id uuid, guest_last_name text, check_in_at timestamptz, check_out_at timestamptz, status text, source text, external_stay_id text, created_by uuid);
create table legacy_source.guest_requests (id uuid primary key, hotel_id uuid, stay_id uuid, room_number text, request_type_id uuid, quantity int, status text, assigned_department text, accepted_by uuid, created_at timestamptz, accepted_at timestamptz, completed_at timestamptz, priority bigint, created_by_staff uuid, archived_at timestamptz, returned_at timestamptz);

insert into legacy_source.hotels values
  ('99999999-0000-0000-0000-000000000001', 'Hotel Sample E2E Dry-Run', 'Europe/Rome', true);

insert into legacy_source.staff_profiles values
  ('99999999-0000-0000-0000-0000000000a1', '99999999-0000-0000-0000-000000000001', 'dryrun-admin@example.test', 'Dry Run Admin', 'admin', null, true, null, 'DryRunAdmin!234'),
  ('99999999-0000-0000-0000-0000000000a2', '99999999-0000-0000-0000-000000000001', null, 'Dry Run Operatore A', 'operatore', 'reception', true, 'dryrunopa', '135790'),
  ('99999999-0000-0000-0000-0000000000a3', '99999999-0000-0000-0000-000000000001', null, 'Dry Run Operatore B', 'operatore', 'housekeeping', true, 'dryrunopb', '246801');

insert into legacy_source.rooms
  select ('99999999-0000-0000-0000-0000000100' || lpad(n::text, 2, '0'))::uuid,
    '99999999-0000-0000-0000-000000000001', 'R' || (100+n), true
  from generate_series(1,7) n;

insert into legacy_source.request_categories (id, hotel_id, name, department, sort_order) values
  ('99999999-0000-0000-0000-000000020001', '99999999-0000-0000-0000-000000000001', 'Pulizie', 'housekeeping', 1),
  ('99999999-0000-0000-0000-000000020002', '99999999-0000-0000-0000-000000000001', 'Reception', 'reception', 2),
  ('99999999-0000-0000-0000-000000020003', '99999999-0000-0000-0000-000000000001', 'Manutenzione', 'maintenance', 3),
  ('99999999-0000-0000-0000-000000020004', '99999999-0000-0000-0000-000000000001', 'Asciugamani', 'housekeeping', 4),
  ('99999999-0000-0000-0000-000000020005', '99999999-0000-0000-0000-000000000001', 'Cuscini', 'housekeeping', 5),
  ('99999999-0000-0000-0000-000000020006', '99999999-0000-0000-0000-000000000001', 'Info', 'reception', 6);

insert into legacy_source.request_types (id, category_id, name, allows_quantity)
  select ('99999999-0000-0000-0000-0000000300' || lpad(n::text, 2, '0'))::uuid,
    ('99999999-0000-0000-0000-00000002000' || (((n - 1) % 6) + 1))::uuid,
    'Tipo richiesta ' || n, (n % 2 = 0)
  from generate_series(1,12) n;

insert into legacy_source.stays (id, hotel_id, room_id, guest_last_name, check_in_at, check_out_at, status) values
  ('99999999-0000-0000-0000-000000004001', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010001', 'Rossi', now() - interval '1 day', now() + interval '2 days', 'active'),
  ('99999999-0000-0000-0000-000000004002', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010002', 'Bianchi', now() - interval '10 day', now() - interval '8 day', 'closed'),
  ('99999999-0000-0000-0000-000000004003', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010003', 'Verdi', now() - interval '20 day', now() - interval '18 day', 'closed'),
  ('99999999-0000-0000-0000-000000004004', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010004', 'Neri', now() - interval '30 day', now() - interval '28 day', 'cancelled');

-- 2 open (requested/in_progress, tied to the active stay) + 23 historical (completed)
-- priority explicit and non-null: STEP 8 of 10_migrate_hotel.sql forwards
-- gr.priority verbatim into a NOT NULL target column (no default applies
-- once a value, even NULL, is given explicitly in the insert column list).
insert into legacy_source.guest_requests (id, hotel_id, stay_id, room_number, request_type_id, status, assigned_department, priority) values
  ('99999999-0000-0000-0000-000000005001', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000004001', 'R101', '99999999-0000-0000-0000-000000030001', 'requested', 'housekeeping', 1),
  ('99999999-0000-0000-0000-000000005002', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000004001', 'R101', '99999999-0000-0000-0000-000000030002', 'in_progress', 'reception', 2);
insert into legacy_source.guest_requests (id, hotel_id, stay_id, room_number, request_type_id, status, assigned_department, archived_at)
  select ('99999999-0000-0000-0000-000000005' || lpad((10+n)::text, 3, '0'))::uuid,
    '99999999-0000-0000-0000-000000000001',
    ('99999999-0000-0000-0000-00000000400' || (2 + (n % 3)))::uuid,
    'R10' || (2 + (n % 3)),
    ('99999999-0000-0000-0000-0000000300' || lpad((((n - 1) % 12) + 1)::text, 2, '0'))::uuid,
    'completed', 'housekeeping', now()
  from generate_series(1,23) n;
