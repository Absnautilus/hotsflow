-- Restricts guest_requests visibility by department: everyone kept seeing
-- the full hotel queue until now (see 0003's comment "the dashboard is
-- deliberately shared"), but that's no longer wanted — only front desk
-- (admin, master, and reception operatori) should see every request.
-- Housekeeping/maintenance/porter operatori now only see requests assigned
-- to their own department.
--
-- WITH CHECK stays hotel-only (no department clause): an operatore who can
-- currently see a request must still be able to reassign it to another
-- department (e.g. mis-routed to housekeeping, actually maintenance's job)
-- even though, the moment that reassignment lands, the row leaves their own
-- visibility — that's the intended outcome, not a bug to guard against.

begin;

drop policy guest_requests_select_hotel on guest_requests;
create policy guest_requests_select_hotel on guest_requests for select to authenticated
  using (
    hotel_id = current_staff_hotel()
    and (current_staff_manages_front_desk() or assigned_department = current_staff_department())
  );

drop policy guest_requests_update_hotel on guest_requests;
create policy guest_requests_update_hotel on guest_requests for update to authenticated
  using (
    hotel_id = current_staff_hotel()
    and (current_staff_manages_front_desk() or assigned_department = current_staff_department())
  )
  with check (hotel_id = current_staff_hotel());

drop policy guest_requests_delete_hotel on guest_requests;
create policy guest_requests_delete_hotel on guest_requests for delete to authenticated
  using (
    hotel_id = current_staff_hotel()
    and (current_staff_manages_front_desk() or assigned_department = current_staff_department())
  );

commit;
