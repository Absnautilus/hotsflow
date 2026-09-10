-- The Team page's "remove" action had no backing delete: authenticated was
-- never granted DELETE on memberships, so a member removed from the list
-- reappeared on the next reload/reload of the page. This adds the missing
-- grant and RLS policy, scoped the same way memberships_update already is
-- (core.staff.manage on the membership's own property/organization, never
-- your own row) plus one extra restriction: only a direct, property-scoped
-- membership can be deleted this way. An org-wide membership reaches every
-- property in the organization, so removing it from a single property's
-- Team page would silently deactivate that person everywhere -- that's an
-- organization-level decision, out of scope for this policy.
create policy memberships_delete on memberships for delete to authenticated
  using (
    profile_id <> auth.uid()
    and property_id is not null
    and has_permission(property_id, 'core.staff.manage')
  );

grant delete on memberships to authenticated;
