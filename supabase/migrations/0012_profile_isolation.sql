-- profiles_select (0007) was `using (true)` — any authenticated user could
-- enumerate every profile on the platform, across every hotel. Restricts it
-- to: your own profile, or a profile that shares at least one accessible
-- property with you (directly, or via either side's org-wide membership).
-- No social graph, no per-property allowlist to maintain — one SECURITY
-- DEFINER helper, reusing has_property_access rather than re-querying
-- memberships raw (which would risk exactly the recursion has_property_access
-- itself exists to avoid).

create function shares_accessible_property(p_target_profile_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships target_m
    where target_m.profile_id = p_target_profile_id
      and target_m.status = 'active'
      and (
        (target_m.property_id is not null and has_property_access(target_m.property_id))
        or (
          target_m.organization_id is not null
          and exists (
            select 1 from properties p
            where p.organization_id = target_m.organization_id
              and has_property_access(p.id)
          )
        )
      )
  );
$$;

drop policy profiles_select on profiles;
create policy profiles_select on profiles for select to authenticated
  using (
    auth.uid() = id
    or shares_accessible_property(id)
  );

revoke all on function shares_accessible_property(uuid) from public;
grant execute on function shares_accessible_property(uuid) to authenticated;
