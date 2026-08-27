-- Adds "maintenance" as a third operatore department, and lets staff (not
-- just guests) create requests directly — e.g. reporting a broken door in
-- a room with no active stay.

begin;

alter table staff_profiles drop constraint staff_profiles_department_matches_role;
alter table staff_profiles add constraint staff_profiles_department_matches_role check (
  (role in ('admin', 'master') and department is null)
  or (role = 'operatore' and department in ('housekeeping', 'reception', 'maintenance'))
);

-- a staff-reported issue isn't tied to any guest stay
alter table guest_requests alter column stay_id drop not null;
alter table guest_requests add column created_by_staff uuid references staff_profiles(id);

-- room_number was always derived from the stay; now it only is when
-- there's a stay to derive it from — a staff report supplies it directly
create or replace function guest_requests_before_insert() returns trigger
language plpgsql as $$
begin
  if new.assigned_department is null then
    select rc.department into new.assigned_department
    from request_types rt
    join request_categories rc on rc.id = rt.category_id
    where rt.id = new.request_type_id;
  end if;

  if new.stay_id is not null then
    select r.room_number into new.room_number
    from stays s
    join rooms r on r.id = s.room_id
    where s.id = new.stay_id;
  end if;

  return new;
end;
$$;

create trigger guest_requests_default_hotel before insert on guest_requests
  for each row execute function default_hotel_id_from_staff();

create policy guest_requests_staff_insert on guest_requests for insert to authenticated
  with check (hotel_id = current_staff_hotel());

grant insert on guest_requests to authenticated;

commit;
