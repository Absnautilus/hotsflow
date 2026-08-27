-- Row Level Security. Guests never get table grants (see 0002); this file
-- only concerns what `authenticated` (staff) and `anon` (public menu) can
-- see and touch directly on the tables.

alter table hotels enable row level security;
alter table staff_profiles enable row level security;
alter table rooms enable row level security;
alter table stays enable row level security;
alter table guest_requests_guest_sessions enable row level security;
alter table guest_login_attempts enable row level security;
alter table request_categories enable row level security;
alter table request_types enable row level security;
alter table guest_requests enable row level security;

-- guest_requests_guest_sessions: no policies at all — reachable only through
-- the SECURITY DEFINER functions in 0002, which run as the table owner.

-- ---------------------------------------------------------------------------
-- hotels
-- ---------------------------------------------------------------------------
create policy hotels_select_own on hotels for select to authenticated
  using (id = current_staff_hotel());

-- ---------------------------------------------------------------------------
-- staff_profiles
-- ---------------------------------------------------------------------------
create policy staff_profiles_select_same_hotel on staff_profiles for select to authenticated
  using (hotel_id = current_staff_hotel());

create policy staff_profiles_admin_write on staff_profiles for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_role() = 'admin')
  with check (hotel_id = current_staff_hotel() and current_staff_role() = 'admin');

-- ---------------------------------------------------------------------------
-- rooms — admin only writes ("impostare i numeri di camera" is an admin job);
-- every active staff member can still see the room list
-- ---------------------------------------------------------------------------
create policy rooms_select_same_hotel on rooms for select to authenticated
  using (hotel_id = current_staff_hotel());

create policy rooms_admin_write on rooms for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_role() = 'admin')
  with check (hotel_id = current_staff_hotel() and current_staff_role() = 'admin');

-- ---------------------------------------------------------------------------
-- stays — front desk (admin + reception operatore) manage; housekeeping
-- operatore never sees guest identity, only the shared guest_requests queue
-- ---------------------------------------------------------------------------
create policy stays_select_front_desk on stays for select to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_manages_front_desk());

create policy stays_front_desk_write on stays for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_manages_front_desk())
  with check (hotel_id = current_staff_hotel() and current_staff_manages_front_desk());

-- ---------------------------------------------------------------------------
-- guest_login_attempts — visibility for front desk, no direct writes
-- (rows are inserted only by guest_login(), which runs as table owner)
-- ---------------------------------------------------------------------------
create policy guest_login_attempts_select_front_desk on guest_login_attempts for select to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_manages_front_desk());

-- ---------------------------------------------------------------------------
-- request_categories / request_types — non-sensitive, publicly readable so
-- the guest UI can render the menu without a round-trip through a token
-- ---------------------------------------------------------------------------
create policy request_categories_public_read on request_categories for select to anon, authenticated
  using (active);

create policy request_categories_admin_write on request_categories for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_role() = 'admin')
  with check (hotel_id = current_staff_hotel() and current_staff_role() = 'admin');

create policy request_types_public_read on request_types for select to anon, authenticated
  using (
    active
    and exists (select 1 from request_categories rc where rc.id = category_id and rc.active)
  );

create policy request_types_admin_write on request_types for all to authenticated
  using (
    current_staff_role() = 'admin'
    and exists (select 1 from request_categories rc where rc.id = category_id and rc.hotel_id = current_staff_hotel())
  )
  with check (
    current_staff_role() = 'admin'
    and exists (select 1 from request_categories rc where rc.id = category_id and rc.hotel_id = current_staff_hotel())
  );

-- ---------------------------------------------------------------------------
-- guest_requests — the dashboard is deliberately shared: any active staff
-- member (admin or operatore, housekeeping or reception) sees and can act
-- on the full hotel queue. assigned_department is a label/reassignment
-- target, not a visibility boundary.
-- ---------------------------------------------------------------------------
create policy guest_requests_select_hotel on guest_requests for select to authenticated
  using (hotel_id = current_staff_hotel());

create policy guest_requests_update_hotel on guest_requests for update to authenticated
  using (hotel_id = current_staff_hotel())
  with check (hotel_id = current_staff_hotel());

-- ---------------------------------------------------------------------------
-- grants — RLS restricts rows, these grants restrict operations
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select on request_categories, request_types to anon;

grant select on hotels, staff_profiles, rooms, stays, guest_login_attempts to authenticated;
grant insert, update on staff_profiles, rooms, stays to authenticated;
grant select, update on guest_requests to authenticated;
grant select, insert, update on request_categories, request_types to authenticated;
