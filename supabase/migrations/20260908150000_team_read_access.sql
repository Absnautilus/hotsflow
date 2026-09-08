-- memberships_select (0007) only ever let a profile see its own row, or
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
-- Operational metadata is deliberately not changed here. A caller with
-- core.staff.manage may edit their own or another member's local job title
-- and employment status; neither field grants software access. Membership
-- role/status remain protected separately, including the existing self-edit
-- guard on memberships_update.

drop policy memberships_select on memberships;
create policy memberships_select on memberships for select to authenticated
  using (
    profile_id = auth.uid()
    or (property_id is not null and has_permission(property_id, 'core.staff.manage'))
    or (organization_id is not null and has_organization_permission(organization_id, 'core.staff.manage'))
    or (property_id is not null and has_property_access(property_id))
    or (organization_id is not null and has_organization_access(organization_id))
  );
