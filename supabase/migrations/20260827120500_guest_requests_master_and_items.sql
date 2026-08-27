-- master: an account not scoped to a single hotel for staff/hotel visibility
-- purposes, on top of the existing admin/operatore split. Also adds
-- inventory metadata to request_types (name/description already existed).

begin;

-- ---------------------------------------------------------------------------
-- staff_profiles: master allowed with department null, same as admin
-- ---------------------------------------------------------------------------
alter table staff_profiles drop constraint staff_profiles_department_matches_role;
alter table staff_profiles add constraint staff_profiles_department_matches_role check (
  (role in ('admin', 'master') and department is null)
  or (role = 'operatore' and department in ('housekeeping', 'reception'))
);

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
create function current_staff_is_master() returns boolean
language sql security definer stable set search_path = public as $$
  select current_staff_role() = 'master';
$$;

create or replace function current_staff_manages_front_desk() returns boolean
language sql security definer stable set search_path = public as $$
  select current_staff_role() in ('admin', 'master')
    or (current_staff_role() = 'operatore' and current_staff_department() = 'reception');
$$;

-- ---------------------------------------------------------------------------
-- hotels: master sees every hotel (needed to pick one when creating an admin)
-- ---------------------------------------------------------------------------
create policy hotels_select_master on hotels for select to authenticated
  using (current_staff_is_master());

-- ---------------------------------------------------------------------------
-- staff_profiles: master sees/manages staff across every hotel
-- ---------------------------------------------------------------------------
drop policy staff_profiles_select_same_hotel on staff_profiles;
create policy staff_profiles_select_scoped on staff_profiles for select to authenticated
  using (hotel_id = current_staff_hotel() or current_staff_is_master());

drop policy staff_profiles_admin_write on staff_profiles;
create policy staff_profiles_write_scoped on staff_profiles for all to authenticated
  using ((hotel_id = current_staff_hotel() and current_staff_role() = 'admin') or current_staff_is_master())
  with check ((hotel_id = current_staff_hotel() and current_staff_role() = 'admin') or current_staff_is_master());

-- ---------------------------------------------------------------------------
-- rooms / request_categories / request_types admin write: master counts too
-- ---------------------------------------------------------------------------
drop policy rooms_admin_write on rooms;
create policy rooms_admin_write on rooms for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_role() in ('admin', 'master'))
  with check (hotel_id = current_staff_hotel() and current_staff_role() in ('admin', 'master'));

drop policy request_categories_admin_write on request_categories;
create policy request_categories_admin_write on request_categories for all to authenticated
  using (hotel_id = current_staff_hotel() and current_staff_role() in ('admin', 'master'))
  with check (hotel_id = current_staff_hotel() and current_staff_role() in ('admin', 'master'));

drop policy request_types_admin_write on request_types;
create policy request_types_admin_write on request_types for all to authenticated
  using (
    current_staff_role() in ('admin', 'master')
    and exists (select 1 from request_categories rc where rc.id = category_id and rc.hotel_id = current_staff_hotel())
  )
  with check (
    current_staff_role() in ('admin', 'master')
    and exists (select 1 from request_categories rc where rc.id = category_id and rc.hotel_id = current_staff_hotel())
  );

-- ---------------------------------------------------------------------------
-- request_types: how many the hotel actually has, distinct from
-- allows_quantity (whether a guest may ask for more than one)
-- ---------------------------------------------------------------------------
alter table request_types add column available_quantity int;
alter table request_types add constraint request_types_available_quantity_non_negative
  check (available_quantity is null or available_quantity >= 0);

-- ---------------------------------------------------------------------------
-- operatore accounts log in with a username + PIN, not a real email/password;
-- the login identifier is still stored here so it shows up in the staff list
-- (the auth.users row underneath uses a synthesized @staff.local address —
-- see the create-staff-account function)
-- ---------------------------------------------------------------------------
alter table staff_profiles add column login_username text;
alter table staff_profiles add constraint staff_profiles_login_username_unique unique (login_username);
alter table staff_profiles add constraint staff_profiles_login_username_matches_role check (
  (role = 'operatore' and login_username is not null)
  or (role in ('admin', 'master') and login_username is null)
);

commit;
