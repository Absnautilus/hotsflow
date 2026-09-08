-- Two fixes found by audit against the "definitiva" Team functional
-- decisions (see docs/permissions.md and the Team directory migrations):
--
-- 1. memberships_select (0007) only ever let a profile see its own row, or
--    someone else's row if it held core.staff.manage over that scope. There
--    was no branch for "can see this property/organization at all" -- so a
--    receptionist calling getTeamMembers() got back an array of exactly one
--    membership (their own), and the Team page rendered as if they were the
--    only person on the property. The read-only Team view the decision log
--    requires for everyone was never actually reachable for anyone without
--    core.staff.manage. This adds the missing read branch, symmetric to the
--    one property_staff_details_select/property_job_titles_select already
--    have. Write policies (insert/update) are untouched -- still
--    core.staff.manage-gated, still hierarchy-checked via
--    role_assignment_allowed()/assign_membership_role().
--
-- 2. property_staff_details_insert/_update (team_directory_and_job_titles)
--    required only core.staff.manage on the property, with no
--    "not your own row" guard -- unlike memberships_update, which added
--    exactly that guard in 0010 for the same reason (self-service on
--    something an admin action covers should never be default-allow). A
--    property_admin could silently reassign their own job title or flip
--    their own employment_status back to 'active' after a peer had marked
--    them 'inactive', with no rank check at all. This does not touch
--    software access (memberships already fully protects that) but it is
--    the one piece of "who manages me" left unprotected. Mirrors
--    memberships_update's fix exactly: add `profile_id <> auth.uid()`.

drop policy memberships_select on memberships;
create policy memberships_select on memberships for select to authenticated
  using (
    profile_id = auth.uid()
    or (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
    or (property_id is not null and has_property_access(property_id))
    or (organization_id is not null and has_organization_access(organization_id))
  );

drop policy property_staff_details_insert on property_staff_details;
create policy property_staff_details_insert on property_staff_details for insert to authenticated
  with check (
    profile_id <> auth.uid()
    and has_permission(property_id, 'core.staff.manage')
  );

drop policy property_staff_details_update on property_staff_details;
create policy property_staff_details_update on property_staff_details for update to authenticated
  using (
    profile_id <> auth.uid()
    and has_permission(property_id, 'core.staff.manage')
  )
  with check (
    profile_id <> auth.uid()
    and has_permission(property_id, 'core.staff.manage')
  );
