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

## The six functions (migration `0006`)

| function | answers |
|---|---|
| `has_property_access(property_id)` | can this profile see this property at all? (direct or org-wide membership) |
| `has_organization_access(organization_id)` | can this profile see this organization at all? |
| `has_permission(property_id, permission_slug)` | role grants the permission, membership covers this property, and (if module-owned) the module is enabled here |
| `has_organization_permission(organization_id, permission_slug)` | same, for actions on the organization itself, where there's no property_id yet (e.g. creating a new property) |
| `has_module(property_id, module_slug)` | pure entitlement, no authorization: is the module switched on here at all? |
| `guest_session_is_valid(session_id, property_id, min_level)` | is this guest session real, live, scoped to this property, at this level? |

Each answers exactly one question — see migration `0006`'s own header and
inline comments for the full reasoning and SQL.

## Per-table policy summary (migration `0007`)

| table | select | write |
|---|---|---|
| organizations | `has_organization_access` | update only, via `has_organization_permission(..., 'core.organization.manage')` — no insert/delete for `authenticated` |
| properties | `has_property_access` | insert via `has_organization_permission(organization_id, 'core.property.manage')` (no property_id exists yet); update via `has_permission(id, 'core.property.manage')` |
| modules | `true` (reference data) | none — service-role/migration managed |
| property_modules | `has_property_access` | insert/update via `has_permission(property_id, 'core.property.manage')` |
| roles / permissions / role_permissions | `true` (reference data) | none |
| profiles | `true` — no tenant data lives here, same low-risk tradeoff already made by `guest_requests`/`shifts` | update own row only (`auth.uid() = id`); no insert (no self-service signup, see `auth.md`) |
| memberships | own rows, or any row you have `core.staff.manage` over | insert/update via `core.staff.manage`, **not** self-service (no `profile_id = auth.uid()` branch on writes) |
| guest_sessions | nothing, for anyone | nothing, for anyone — see `guest-access.md` |

No `anon` grants exist anywhere in Phase 1 — there's no guest-facing flow
yet to grant them for (see `guest-access.md`).

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
