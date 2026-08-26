-- Two foundations the rest of Fase 1.1 builds on:
--   1. roles.rank — lets "can actor X assign role Y" be a single numeric
--      comparison instead of a table of special cases per role pair.
--   2. role.scope <-> membership scope consistency — a property-scoped role
--      must land on a property-scoped membership, never an org-wide one,
--      and vice versa.

alter table roles add column rank smallint not null default 0 check (rank >= 0);

comment on column roles.rank is
  'Gaps left intentionally between seeded values (10/20/30/40) so an '
  'intermediate role can be inserted later without a migration — same '
  'convention as guest_sessions.verification_level. A role''s rank is the '
  'ceiling on what its holders can assign to others: see '
  'role_assignment_allowed() in 0010.';

-- A plain CHECK constraint can't reference another table, and role_id is
-- mutable (a membership's role can change) — so this has to be a trigger,
-- not a constraint. Deliberately plpgsql + a single SELECT, not a
-- generalized validation framework.
create function validate_membership_role_scope() returns trigger
language plpgsql as $$
declare
  v_role_scope text;
begin
  select scope into v_role_scope from roles where id = new.role_id;

  if v_role_scope is null then
    raise exception 'role_not_found' using errcode = '23503';
  end if;

  if v_role_scope = 'property' and new.property_id is null then
    raise exception 'role_scope_mismatch: role % is property-scoped but this membership has no property_id', new.role_id
      using errcode = '23514';
  end if;

  if v_role_scope = 'organization' and new.organization_id is null then
    raise exception 'role_scope_mismatch: role % is organization-scoped but this membership has no organization_id', new.role_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger memberships_validate_role_scope
  before insert or update of role_id, property_id, organization_id on memberships
  for each row execute function validate_membership_role_scope();
