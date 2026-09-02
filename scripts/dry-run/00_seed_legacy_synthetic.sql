-- Dry-run only: stands in for "export from the legacy Housekeeping
-- project". Synthetic data, no PII, shaped to match the real production
-- hotel's row counts confirmed in docs/production-data-migration-plan.md
-- §A (1 hotel, 3 staff, 7 rooms, 6 categories, 12 types, 4 stays/1
-- active, 25 requests/2 open). Fixed deterministic ids so reruns and
-- reconciliation queries are stable.
create schema if not exists legacy_dryrun;

drop table if exists legacy_dryrun.guest_requests, legacy_dryrun.stays,
  legacy_dryrun.request_types, legacy_dryrun.request_categories,
  legacy_dryrun.rooms, legacy_dryrun.staff_profiles, legacy_dryrun.hotels cascade;

create table legacy_dryrun.hotels (id uuid primary key, name text, timezone text, active boolean);
create table legacy_dryrun.staff_profiles (id uuid primary key, hotel_id uuid, email text, name text, role text, department text, active boolean, login_username text, password text);
create table legacy_dryrun.rooms (id uuid primary key, hotel_id uuid, room_number text, active boolean);
create table legacy_dryrun.request_categories (id uuid primary key, hotel_id uuid, name text, department text, sort_order int);
create table legacy_dryrun.request_types (id uuid primary key, category_id uuid, name text, allows_quantity boolean);
create table legacy_dryrun.stays (id uuid primary key, hotel_id uuid, room_id uuid, guest_last_name text, check_in_at timestamptz, check_out_at timestamptz, status text);
create table legacy_dryrun.guest_requests (id uuid primary key, hotel_id uuid, stay_id uuid, request_type_id uuid, status text, assigned_department text, archived_at timestamptz);

insert into legacy_dryrun.hotels values
  ('99999999-0000-0000-0000-000000000001', 'Hotel Sample E2E Dry-Run', 'Europe/Rome', true);

insert into legacy_dryrun.staff_profiles values
  ('99999999-0000-0000-0000-0000000000a1', '99999999-0000-0000-0000-000000000001', 'dryrun-admin@example.test', 'Dry Run Admin', 'admin', null, true, null, 'DryRunAdmin!234'),
  ('99999999-0000-0000-0000-0000000000a2', '99999999-0000-0000-0000-000000000001', null, 'Dry Run Operatore A', 'operatore', 'reception', true, 'dryrunopa', '135790'),
  ('99999999-0000-0000-0000-0000000000a3', '99999999-0000-0000-0000-000000000001', null, 'Dry Run Operatore B', 'operatore', 'housekeeping', true, 'dryrunopb', '246801');

insert into legacy_dryrun.rooms
  select ('99999999-0000-0000-0000-0000000100' || lpad(n::text, 2, '0'))::uuid,
    '99999999-0000-0000-0000-000000000001', 'R' || (100+n), true
  from generate_series(1,7) n;

insert into legacy_dryrun.request_categories values
  ('99999999-0000-0000-0000-000000020001', '99999999-0000-0000-0000-000000000001', 'Pulizie', 'housekeeping', 1),
  ('99999999-0000-0000-0000-000000020002', '99999999-0000-0000-0000-000000000001', 'Reception', 'reception', 2),
  ('99999999-0000-0000-0000-000000020003', '99999999-0000-0000-0000-000000000001', 'Manutenzione', 'maintenance', 3),
  ('99999999-0000-0000-0000-000000020004', '99999999-0000-0000-0000-000000000001', 'Asciugamani', 'housekeeping', 4),
  ('99999999-0000-0000-0000-000000020005', '99999999-0000-0000-0000-000000000001', 'Cuscini', 'housekeeping', 5),
  ('99999999-0000-0000-0000-000000020006', '99999999-0000-0000-0000-000000000001', 'Info', 'reception', 6);

insert into legacy_dryrun.request_types
  select ('99999999-0000-0000-0000-0000000300' || lpad(n::text, 2, '0'))::uuid,
    ('99999999-0000-0000-0000-00000002000' || (((n - 1) % 6) + 1))::uuid,
    'Tipo richiesta ' || n, (n % 2 = 0)
  from generate_series(1,12) n;

insert into legacy_dryrun.stays values
  ('99999999-0000-0000-0000-000000004001', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010001', 'Rossi', now() - interval '1 day', now() + interval '2 days', 'active'),
  ('99999999-0000-0000-0000-000000004002', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010002', 'Bianchi', now() - interval '10 day', now() - interval '8 day', 'closed'),
  ('99999999-0000-0000-0000-000000004003', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010003', 'Verdi', now() - interval '20 day', now() - interval '18 day', 'closed'),
  ('99999999-0000-0000-0000-000000004004', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000010004', 'Neri', now() - interval '30 day', now() - interval '28 day', 'cancelled');

-- 2 open (requested/in_progress, tied to the active stay) + 23 historical (completed)
insert into legacy_dryrun.guest_requests values
  ('99999999-0000-0000-0000-000000005001', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000004001', '99999999-0000-0000-0000-000000030001', 'requested', 'housekeeping', null),
  ('99999999-0000-0000-0000-000000005002', '99999999-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000004001', '99999999-0000-0000-0000-000000030002', 'in_progress', 'reception', null);
insert into legacy_dryrun.guest_requests
  select ('99999999-0000-0000-0000-000000005' || lpad((10+n)::text, 3, '0'))::uuid,
    '99999999-0000-0000-0000-000000000001',
    ('99999999-0000-0000-0000-00000000400' || (2 + (n % 3)))::uuid,
    ('99999999-0000-0000-0000-0000000300' || lpad((((n - 1) % 12) + 1)::text, 2, '0'))::uuid,
    'completed', 'housekeeping', now()
  from generate_series(1,23) n;
