-- Enforce the tenant invariants that row-level policies alone cannot express.
--
-- RLS correctly limits each operational row to current_staff_hotel(), but the
-- original schema used single-column foreign keys. That allowed a row stamped
-- for hotel A to reference a room, stay, menu item, or staff profile belonging
-- to hotel B when a caller already knew the referenced UUID. Besides producing
-- misleading labels, such a relationship can route work to the wrong
-- department. These triggers reject new cross-hotel relationships and changes
-- to tenant-bearing references without rewriting historical data.

begin;

create function enforce_stay_hotel_integrity() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_room_hotel_id uuid;
  v_creator_hotel_id uuid;
begin
  if tg_op = 'INSERT'
     or new.hotel_id is distinct from old.hotel_id
     or new.room_id is distinct from old.room_id then
    select hotel_id into v_room_hotel_id
    from rooms
    where id = new.room_id;

    if v_room_hotel_id is null or v_room_hotel_id is distinct from new.hotel_id then
      raise exception using errcode = '23514', message = 'stays_room_hotel_mismatch';
    end if;
  end if;

  if new.created_by is not null
     and (tg_op = 'INSERT'
          or new.hotel_id is distinct from old.hotel_id
          or new.created_by is distinct from old.created_by) then
    select hotel_id into v_creator_hotel_id
    from staff_profiles
    where id = new.created_by;

    if v_creator_hotel_id is null or v_creator_hotel_id is distinct from new.hotel_id then
      raise exception using errcode = '23514', message = 'stays_creator_hotel_mismatch';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function enforce_stay_hotel_integrity() from public;

create trigger stays_tenant_integrity
  before insert or update of hotel_id, room_id, created_by on stays
  for each row execute function enforce_stay_hotel_integrity();

create function enforce_guest_request_hotel_integrity() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_stay_hotel_id uuid;
  v_stay_room_number text;
  v_request_type_hotel_id uuid;
  v_creator_hotel_id uuid;
  v_acceptor_hotel_id uuid;
begin
  if tg_op = 'INSERT'
     or new.hotel_id is distinct from old.hotel_id
     or new.stay_id is distinct from old.stay_id
     or new.room_number is distinct from old.room_number then
    if new.stay_id is not null then
      select s.hotel_id, r.room_number
      into v_stay_hotel_id, v_stay_room_number
      from stays s
      join rooms r on r.id = s.room_id
      where s.id = new.stay_id;

      if v_stay_hotel_id is null
         or v_stay_hotel_id is distinct from new.hotel_id
         or v_stay_room_number is distinct from new.room_number then
        raise exception using errcode = '23514', message = 'guest_request_stay_hotel_mismatch';
      end if;
    elsif not exists (
      select 1
      from rooms r
      where r.hotel_id = new.hotel_id
        and r.room_number = new.room_number
    ) then
      raise exception using errcode = '23514', message = 'guest_request_room_hotel_mismatch';
    end if;
  end if;

  if tg_op = 'INSERT'
     or new.hotel_id is distinct from old.hotel_id
     or new.request_type_id is distinct from old.request_type_id then
    select rc.hotel_id into v_request_type_hotel_id
    from request_types rt
    join request_categories rc on rc.id = rt.category_id
    where rt.id = new.request_type_id;

    if v_request_type_hotel_id is null or v_request_type_hotel_id is distinct from new.hotel_id then
      raise exception using errcode = '23514', message = 'guest_request_type_hotel_mismatch';
    end if;
  end if;

  if new.created_by_staff is not null
     and (tg_op = 'INSERT'
          or new.hotel_id is distinct from old.hotel_id
          or new.created_by_staff is distinct from old.created_by_staff) then
    select hotel_id into v_creator_hotel_id
    from staff_profiles
    where id = new.created_by_staff;

    if v_creator_hotel_id is null or v_creator_hotel_id is distinct from new.hotel_id then
      raise exception using errcode = '23514', message = 'guest_request_creator_hotel_mismatch';
    end if;
  end if;

  if new.accepted_by is not null
     and (tg_op = 'INSERT'
          or new.hotel_id is distinct from old.hotel_id
          or new.accepted_by is distinct from old.accepted_by) then
    select hotel_id into v_acceptor_hotel_id
    from staff_profiles
    where id = new.accepted_by;

    if v_acceptor_hotel_id is null or v_acceptor_hotel_id is distinct from new.hotel_id then
      raise exception using errcode = '23514', message = 'guest_request_acceptor_hotel_mismatch';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function enforce_guest_request_hotel_integrity() from public;

-- Trigger names sort after the existing *_default_hotel triggers, so inserts
-- that omit hotel_id are stamped first and validated second.
create trigger guest_requests_tenant_integrity
  before insert or update of hotel_id, stay_id, room_number, request_type_id, created_by_staff, accepted_by
  on guest_requests
  for each row execute function enforce_guest_request_hotel_integrity();

commit;
