-- Guest requests app — initial schema
-- See Fase 1 design doc for rationale on hotel_id-everywhere, token hashing,
-- and the checkout-guard pattern used throughout.

create extension if not exists pgcrypto;
create extension if not exists unaccent;
create extension if not exists btree_gist;

create type stay_status as enum ('active', 'closed', 'cancelled');
create type stay_source as enum ('manual', 'opera');
create type request_status as enum ('requested', 'in_progress', 'completed', 'cancelled');
-- categorizes request_categories (label shown on each card) and, loosely,
-- staff_profiles (an operatore is "housekeeping" or "reception" — the
-- other two values only ever apply to requests, never to a staff account)
create type department as enum ('reception', 'housekeeping', 'maintenance', 'porter');
-- an operatore's department decides nothing about what they can see: the
-- guest_requests queue is shared between housekeeping and reception by
-- design (see 0003_rls.sql). Only admin vs operatore is an access boundary.
create type staff_role as enum ('admin', 'operatore');

-- set_updated_at(): legacy duplicate removed during consolidation.
-- canonical owner = core (hotsflow-core migration 0001_organizations_properties.sql).
-- Verified equivalent before removal: identical language (plpgsql), identical
-- volatility (default, neither declares one), identical security mode (default
-- invoker, neither declares SECURITY DEFINER), identical search_path handling
-- (neither sets one), no ALTER FUNCTION/GRANT/OWNER on it anywhere in either
-- repository, and a byte-identical body. behavior unchanged — every trigger
-- below that calls set_updated_at() now resolves to the core's function.

-- unaccent() ships as STABLE, which Postgres won't allow inside a generated
-- column or index expression. Wrapping it IMMUTABLE is the standard,
-- widely-used workaround (the default dictionary doesn't change at
-- runtime in a way that would break this).
-- search_path is pinned explicitly (Supabase installs pgcrypto/unaccent
-- into `extensions`, not `public`) so this resolves regardless of the
-- caller's own search_path.
create function immutable_unaccent(text) returns text
language sql immutable set search_path = public, extensions as $$
  select unaccent('unaccent', $1);
$$;

create function normalize_guest_name(text) returns text
language sql immutable as $$
  select lower(regexp_replace(immutable_unaccent(trim($1)), '\s+', ' ', 'g'));
$$;

-- ---------------------------------------------------------------------------
-- hotels
-- ---------------------------------------------------------------------------
create table hotels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  timezone text not null default 'Europe/Rome',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- staff_profiles
-- ---------------------------------------------------------------------------
create table staff_profiles (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  auth_user_id uuid not null unique references auth.users(id),
  name text not null,
  role staff_role not null,
  department department,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint staff_profiles_department_matches_role check (
    (role = 'admin' and department is null)
    or (role = 'operatore' and department in ('housekeeping', 'reception'))
  )
);

create index staff_profiles_hotel_idx on staff_profiles(hotel_id);

-- ---------------------------------------------------------------------------
-- rooms
-- ---------------------------------------------------------------------------
create table rooms (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  room_number text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (hotel_id, room_number)
);

-- ---------------------------------------------------------------------------
-- stays
-- ---------------------------------------------------------------------------
create table stays (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  room_id uuid not null references rooms(id),
  guest_last_name text not null,
  -- drives both the login lookup and its unique index; normalized once here
  -- instead of on every login attempt.
  guest_last_name_normalized text generated always as (
    normalize_guest_name(guest_last_name)
  ) stored,
  check_in_at timestamptz not null,
  check_out_at timestamptz not null,
  status stay_status not null default 'active',
  source stay_source not null default 'manual',
  external_stay_id text,
  created_by uuid references staff_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint stays_checkout_after_checkin check (check_out_at > check_in_at)
);

-- a room can only have one active stay covering any given moment; this is
-- what makes "camera+cognome" login unambiguous without extra app logic.
alter table stays
  add constraint stays_no_overlapping_active
  exclude using gist (room_id with =, tstzrange(check_in_at, check_out_at) with &&)
  where (status = 'active');

create index stays_login_lookup_idx
  on stays (room_id, guest_last_name_normalized, status);

create trigger stays_set_updated_at
  before update on stays
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- guest_requests_guest_sessions
-- (physical identifier renamed from `guest_sessions` during Fase 2
-- consolidation: hotsflow-core's own, unrelated `guest_sessions` platform
-- primitive — generic, method-agnostic, not yet adopted by any module —
-- already occupies that name in the shared `public` schema. This is a
-- rename of the identifier only: columns, types, constraints, indexes, RLS,
-- triggers, and every RPC's behavior are unchanged. The two tables remain
-- semantically distinct and are NOT being unified in Fase 2.)
-- ---------------------------------------------------------------------------
create table guest_requests_guest_sessions (
  id uuid primary key default gen_random_uuid(),
  stay_id uuid not null references stays(id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz,
  created_ip inet,
  created_at timestamptz not null default now()
);

create index guest_sessions_stay_idx on guest_requests_guest_sessions(stay_id);

-- keeps session validity in lockstep with reception's stay edits, so the
-- checkout guard never has to rely on a cron sweep for correctness.
create function sync_guest_sessions_on_stay_change() returns trigger
language plpgsql as $$
begin
  if new.status <> 'active' then
    update guest_requests_guest_sessions set revoked_at = now()
      where stay_id = new.id and revoked_at is null;
  elsif new.check_out_at <> old.check_out_at then
    if new.check_out_at < old.check_out_at then
      update guest_requests_guest_sessions set revoked_at = now()
        where stay_id = new.id and revoked_at is null and expires_at > new.check_out_at;
    end if;
    update guest_requests_guest_sessions set expires_at = new.check_out_at
      where stay_id = new.id and revoked_at is null;
  end if;
  return new;
end;
$$;

create trigger stays_sync_guest_sessions
  after update of status, check_out_at on stays
  for each row execute function sync_guest_sessions_on_stay_change();

-- ---------------------------------------------------------------------------
-- guest_login_attempts (rate limiting + abuse visibility for reception)
-- ---------------------------------------------------------------------------
create table guest_login_attempts (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  ip_address inet,
  room_number_attempted text,
  succeeded boolean not null,
  created_at timestamptz not null default now()
);

create index guest_login_attempts_ip_idx on guest_login_attempts(hotel_id, ip_address, created_at);
create index guest_login_attempts_room_idx on guest_login_attempts(hotel_id, room_number_attempted, created_at);

-- ---------------------------------------------------------------------------
-- request_categories / request_types
-- ---------------------------------------------------------------------------
create table request_categories (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  name text not null,
  department department not null,
  icon text,
  active boolean not null default true,
  sort_order int not null default 0
);

create table request_types (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references request_categories(id),
  name text not null,
  description text,
  allows_quantity boolean not null default false,
  active boolean not null default true,
  sort_order int not null default 0
);

create index request_types_category_idx on request_types(category_id);

-- ---------------------------------------------------------------------------
-- guest_requests
-- ---------------------------------------------------------------------------
create table guest_requests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  stay_id uuid not null references stays(id),
  -- denormalized from stays/rooms at creation time (a stay's room never
  -- changes) so housekeeping/maintenance/porter can read the queue without
  -- any RLS access to `stays`, which carries the guest's surname.
  room_number text not null,
  request_type_id uuid not null references request_types(id),
  quantity int,
  note text,
  status request_status not null default 'requested',
  assigned_department department not null,
  accepted_by uuid references staff_profiles(id),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  completed_at timestamptz
);

create index guest_requests_queue_idx on guest_requests(hotel_id, status, created_at);
create index guest_requests_stay_idx on guest_requests(stay_id);

-- assigned_department defaults from the category so reception never has to
-- pick it manually (they can still reassign afterwards); room_number is
-- always stamped from the stay, never trusted from the caller.
create function guest_requests_before_insert() returns trigger
language plpgsql as $$
begin
  if new.assigned_department is null then
    select rc.department into new.assigned_department
    from request_types rt
    join request_categories rc on rc.id = rt.category_id
    where rt.id = new.request_type_id;
  end if;

  select r.room_number into new.room_number
  from stays s
  join rooms r on r.id = s.room_id
  where s.id = new.stay_id;

  return new;
end;
$$;

create trigger guest_requests_before_insert
  before insert on guest_requests
  for each row execute function guest_requests_before_insert();
