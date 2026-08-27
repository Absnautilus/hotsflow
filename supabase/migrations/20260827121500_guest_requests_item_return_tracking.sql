-- Explicit "returned" step for trackable items (request_types with
-- available_quantity set, e.g. irons, hairdryers): a completed request for
-- one of those no longer frees up the item automatically — it stays
-- counted as "out" in fetchItemAvailability until someone marks it
-- returned, or until the guest's stay ends (whichever comes first).
--
-- The automatic half: when a stay's status moves away from 'active' (guest
-- checked out — today that's the "Disattiva" action; 'closed' is covered
-- too in case a future flow ever sets it directly), any of that stay's
-- completed-but-not-yet-returned trackable-item requests are auto-marked
-- returned. A guest doesn't take the hotel's iron home; once the stay is
-- over the item is back in inventory whether or not anyone explicitly
-- picked it up from the room.

begin;

alter table guest_requests add column returned_at timestamptz;

create function auto_return_items_on_stay_end() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'active' and new.status <> 'active' then
    update guest_requests gr
    set returned_at = now()
    from request_types rt
    where gr.request_type_id = rt.id
      and gr.stay_id = new.id
      and gr.status = 'completed'
      and gr.returned_at is null
      and rt.available_quantity is not null;
  end if;
  return new;
end;
$$;

create trigger stays_auto_return_items_after_update
  after update on stays
  for each row execute function auto_return_items_on_stay_end();

commit;
