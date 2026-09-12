-- Reservations: a booking that exists before the guest physically checks
-- in, distinct from `stays` (an in-house occupancy). stays.room_id is
-- not-null and its exclusion constraint assumes real, current occupancy --
-- neither holds for a reservation, which may exist for weeks before a room
-- is ever assigned. This is schema-only scaffolding: no guest-facing login,
-- no pre-arrival requests, and no staff UI yet. Room+PIN access and the
-- existing manual check-in flow (creating a `stays` row directly) are
-- completely unchanged; a reservation today is just a record front desk can
-- create by hand.
--
-- Deliberately shaped to be filled by a future PMS sync instead of by hand:
-- `source` and `external_reservation_id` mirror the same fields already on
-- `stays` for exactly that reason (see stay_source, external_stay_id) --
-- when a real PMS integration exists, it becomes the thing writing these
-- rows (source = 'opera', external_reservation_id = the PMS's own booking
-- id) instead of front desk typing them in. Promoting a reservation to a
-- real stay at actual check-in (assigning a room, setting reservations.
-- stay_id) is a future PR, not built here.

begin;

create type reservation_status as enum ('upcoming', 'checked_in', 'cancelled', 'no_show');

create table reservations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references hotels(id),
  -- Null until a room is assigned -- normally at or shortly before
  -- check-in, never required to exist for the reservation itself.
  room_id uuid references rooms(id),
  guest_last_name text not null,
  -- Unique per hotel, not globally: what the guest would quote to front
  -- desk or (once it exists) use with reservation_login instead of a room
  -- number, which isn't assigned yet.
  confirmation_code text not null,
  arrival_date date not null,
  departure_date date not null,
  status reservation_status not null default 'upcoming',
  source stay_source not null default 'manual',
  external_reservation_id text,
  -- Set once this reservation is promoted to a real stay at check-in
  -- (future work) -- historical link, not read by anything yet.
  stay_id uuid references stays(id),
  created_by uuid references staff_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservations_departure_after_arrival check (departure_date > arrival_date),
  constraint reservations_hotel_confirmation_code_key unique (hotel_id, confirmation_code)
);

create index reservations_hotel_status_idx on reservations(hotel_id, status, arrival_date);

create trigger reservations_default_hotel before insert on reservations
  for each row execute function default_hotel_id_from_staff();

create trigger reservations_set_updated_at before update on reservations
  for each row execute function set_updated_at();

alter table reservations enable row level security;

-- Mirrors stays_select_front_desk / stays_front_desk_write exactly -- same
-- staff, same access rule, since this is the same front-desk domain.
create policy reservations_select_front_desk on reservations for select to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_manages_front_desk());

create policy reservations_front_desk_write on reservations for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_manages_front_desk())
  with check (hotel_id = current_staff_hotel() and current_staff_manages_front_desk());

grant select, insert, update on reservations to authenticated;

commit;
