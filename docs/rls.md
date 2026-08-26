# Row Level Security

## Two layers, both required

Every table has RLS enabled, policies, **and** grants — deliberately
separate mechanisms:

- **Policies** restrict which *rows* a query can see or touch.
- **Grants** restrict which *operations* a role can attempt on the table at
  all.

A permissive policy with no matching grant still fails closed. This is
exactly how `guest_sessions` ends up fully locked down: RLS enabled, zero
policies, zero grants, for both `anon` and `authenticated` — reachable only
through `SECURITY DEFINER` functions, which run as the function owner and
bypass RLS entirely.

## Why every helper is a SECURITY DEFINER function

A policy on table X that queries table Y directly re-triggers Y's own RLS
during evaluation. Query X itself inside X's own policy and you get
infinite recursion; query a table whose policy hasn't resolved yet and you
get a wrong answer, silently. This is not a hypothetical — it's the exact
bug both `guest_requests` and `plannerturni` hit and fixed the same way (see
the three-module audit; `plannerturni`'s own migration is literally named
`0003_fix_admin_policy_recursion.sql`).

The fix: wrap the check in a function that's `security definer` (runs with
the function owner's privileges, bypassing RLS on whatever it queries
internally), `stable` (safe to call repeatedly in one statement), and pins
`search_path = public` explicitly. That last part isn't optional — without
it, the function resolves unqualified table names using the *caller's*
search_path, which the caller controls.

## The eleven functions

From migration `0006`:

| function | answers |
|---|---|
| `has_property_access(property_id)` | can this profile see this property at all? (direct or org-wide membership) |
| `has_organization_access(organization_id)` | can this profile see this organization at all? |
| `has_permission(property_id, permission_slug)` | role grants the permission, membership covers this property, and (if module-owned) the module is enabled here |
| `has_organization_permission(organization_id, permission_slug)` | same, for actions on the organization itself, where there's no property_id yet (e.g. creating a new property) |
| `has_module(property_id, module_slug)` | pure entitlement, no authorization: is the module switched on here at all? |
| `guest_session_is_valid(session_id, property_id, min_level)` | is this guest session real, live, scoped to this property, at this level? — no grant exists for it yet, see §PUBLIC below |

Added in Fase 1.1, migrations `0010`/`0012`:

| function | answers |
|---|---|
| `current_actor_role_rank(property_id)` | the rank of the caller's own active membership covering this property (direct or org-wide; higher wins if both exist) |
| `current_actor_role_rank_for_organization(organization_id)` | same, org-wide membership only |
| `role_assignment_allowed(new_role_id, property_id, organization_id, target_profile_id)` | the entire staff-management hierarchy rule — see `permissions.md` |
| `assign_membership_role(membership_id, new_role_id)` | the only sanctioned way to change an existing membership's role |
| `shares_accessible_property(target_profile_id)` | does the caller have `has_property_access` to any property where this target profile also has an active membership? — powers `profiles_select` |

Each answers exactly one question — see the relevant migration's own header
and inline comments for the full reasoning and SQL.

## Per-table policy summary (current, after Fase 1.1)

| table | select | write |
|---|---|---|
| organizations | `has_organization_access` | update only, via `has_organization_permission(..., 'core.organization.manage')` — no insert/delete for `authenticated` |
| properties | `has_property_access` | insert via `has_organization_permission(organization_id, 'core.property.manage')` (no property_id exists yet); update via `has_permission(id, 'core.property.manage')` |
| modules | `true` (reference data) | none — migration managed (`0009`) |
| property_modules | `has_property_access` | **none** — dropped in `0013`; commercial entitlement, service-role only, see `permissions.md` |
| roles / permissions / role_permissions | `true` (reference data) | none — system rows come from `0009`, not runtime writes |
| profiles | own row, or `shares_accessible_property(id)` (`0012`) — no more platform-wide enumeration | update own row only (`auth.uid() = id`); no insert (no self-service signup, see `auth.md`) |
| memberships | own rows, or any row you have `core.staff.manage` over | insert (with `role_assignment_allowed`, `0010`) / update **status only** via column grant, and never your own row — role changes go through `assign_membership_role()` exclusively |
| guest_sessions | nothing, for anyone | nothing, for anyone — see `guest-access.md` |
| audit_logs (`0014`) | any row you have `core.staff.manage` over | none for `authenticated` — written only by the triggers/functions that produce it |

No `anon` grants exist anywhere in this project yet — there's no
guest-facing flow to grant them for (see `guest-access.md`).

## Column-level grants: a second layer under `memberships`

RLS policies restrict *rows*; they can't restrict *which columns* an
`UPDATE` touches. Before Fase 1.1, anyone passing the `memberships_update`
policy (i.e. holding `core.staff.manage`) could set `role_id` to anything —
including their own row — via a plain `UPDATE`. The fix isn't a smarter
policy (RLS can't express "this column, not that one"); it's a real
Postgres privilege:

```sql
revoke update on memberships from authenticated;
grant update (status) on memberships to authenticated;
```

`role_id`/`property_id`/`organization_id`/`profile_id` are now unwritable
from any client role through any path, full stop — not "the policy happens
to deny it today." `assign_membership_role()` still changes `role_id`
because it's `SECURITY DEFINER` and runs as its owner, which this grant
doesn't apply to.

## PUBLIC still gets EXECUTE by default — revoke it explicitly

`CREATE FUNCTION` grants `EXECUTE` to `PUBLIC` automatically; a later
`GRANT ... TO authenticated` does not undo that. Every `SECURITY DEFINER`
function here was therefore callable by `anon` from the moment it was
created, silently, until migration `0011`:

```sql
revoke all on function has_permission(uuid, text) from public;
grant execute on function has_permission(uuid, text) to authenticated;
```

This bit for real during testing: `guest_session_is_valid` had been granted
to `authenticated` in `0006`, and `REVOKE ALL ... FROM PUBLIC` does **not**
touch a grant made to a different, specific role — it took an explicit
`revoke all on function guest_session_is_valid(...) from authenticated`
to actually make it unreachable. Test `016_security_definer_grants.test.sql`
checks this for `anon` on the staff helpers, `assign_membership_role`, and
for `authenticated` on `guest_session_is_valid` specifically.

Calling one `SECURITY DEFINER` function from inside another's body needs no
grant of its own — the check runs against the *owner's* privileges (all
these functions share an owner), and an owner's rights on its own objects
survive any `REVOKE` aimed at a different role.

## A trigger, not a policy: role.scope vs. membership scope

`roles.scope` (`organization`/`property`) has to agree with which column a
`memberships` row actually populates — a plain `CHECK` constraint can't
express that (it can't query another table). Migration `0008`'s
`validate_membership_role_scope()` is a `BEFORE INSERT OR UPDATE` trigger
instead, not `SECURITY DEFINER` (it only reads `roles`, which is
open-`SELECT` reference data — no RLS to bypass) and not callable directly
(Postgres refuses to invoke a trigger function outside a trigger context).
`role_assignment_allowed()` checks the same thing again before calling
`assign_membership_role()` — belt and suspenders, since the trigger alone
wouldn't produce a clean, catchable error from inside that function's own
control flow.

## Worked example: a new module's own RLS

A module's own table (say `guest_requests.requests`) with a `property_id`
column reuses these same functions directly — it does not need its own
recursion-safe helpers, because it's calling functions that already are:

```sql
alter table requests enable row level security;

create policy requests_select on requests for select to authenticated
  using (has_property_access(property_id));

create policy requests_update on requests for update to authenticated
  using (has_permission(property_id, 'guest_requests.manage'))
  with check (has_permission(property_id, 'guest_requests.manage'));
```

That's the entire integration surface for staff access — see
`module-integration.md` for the rest (entitlement checks, guest access,
what a module must never do).
