-- Single-hotel MVP: staff never type or pick a hotel_id, so every table
-- they write to stamps it from their own staff_profiles row instead of
-- trusting (or requiring) it from the client.

create function default_hotel_id_from_staff() returns trigger
language plpgsql as $$
begin
  if new.hotel_id is null then
    new.hotel_id := current_staff_hotel();
  end if;
  return new;
end;
$$;

create trigger rooms_default_hotel before insert on rooms
  for each row execute function default_hotel_id_from_staff();

create trigger stays_default_hotel before insert on stays
  for each row execute function default_hotel_id_from_staff();

create trigger request_categories_default_hotel before insert on request_categories
  for each row execute function default_hotel_id_from_staff();
