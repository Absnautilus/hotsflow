# Permissions

Deliberately minimal RBAC — no policy engine, no ABAC, no dynamic
conditions, no permission inheritance beyond the one org-wide/property-wide
distinction described below.

## The model

```
roles  <--  role_permissions  -->  permissions  -->  modules (nullable)
  ^
  |
memberships  -->  properties / organizations
```

A profile's effective permission on a property is:

> their role (via an active membership covering that property, directly or
> org-wide) grants the permission slug, **and** — only if that permission
> belongs to a module — the property actually has that module enabled.

That's `has_permission(property_id, permission_slug)`, migration `0006`.
Nothing else computes authorization; the Core SDK's `hasPermission()` calls
this exact function via RPC, so the app-side check and the database's own
enforcement can never drift apart.

## Why entitlement and permission stay separate

```
property_modules  =  does this property have the module at all?
permissions        =  is this role allowed to do this, assuming it does?
```

A `manager` role can hold `transfers.use` and still get `false` from
`has_permission(propertyId, 'transfers.use')` if that property's
`property_modules` row for `transfers` has `enabled = false`. Collapsing
these into one table would make "the hotel hasn't purchased this module"
indistinguishable from "this role isn't allowed to use it" — two different
facts with different owners (billing/product vs. the hotel's own staff
configuration). As of Fase 1.1 this isn't just a data-model distinction:
`property_modules` has no write policy for `authenticated` at all (migration
`0013`) — not even `core.property.manage` reaches it. Entitlement changes
are service-role/billing-tooling only; see `rls.md`.

## The system roles

As of Fase 1.1, the four roles, the core permissions, and the
`role_permissions` grants connecting them are bootstrapped by migration
`0009` — not `supabase/seed.sql`. This wasn't cosmetic: `properties_update`
and other policies hardcode slugs like `core.property.manage`, so those
permission rows have to exist on *every* environment, including a real
hosted project that `seed.sql` (dev-only, see its own header) never
touches. `seed.sql` now only adds demo organizations/properties and a
couple of illustrative module-specific permissions on top.

| role | scope | rank | core permissions | can do |
|---|---|---|---|---|
| `organization_admin` | organization | 40 | `core.organization.manage`, `core.property.manage`, `core.staff.manage`, `core.roles.assign` | everything, on every property under its organization |
| `property_admin` | property | 30 | `core.property.manage`, `core.staff.manage`, `core.roles.assign` | everything on its property except organization-level administration |
| `manager` | property | 20 | `core.staff.manage`, `core.roles.assign` | every module (via demo `*.use`/`*.view` grants), manages staff and their roles below its own rank — matches "Manager -> puo usare tutti i moduli -> puo gestire staff" |
| `receptionist` | property | 10 | *(none)* | module use only, no configuration — matches "Receptionist -> non puo modificare configurazione hotel" |

Extending this is additive: a new permission slug, a new `role_permissions`
row, or (rarely) a new role — never a redesign. A genuinely new *system*
role (one every environment needs, not a per-hotel custom one) belongs in a
migration alongside these four, for the same reason they are.

## Staff management hierarchy

Two permissions govern staff, deliberately kept separate:

```
core.staff.manage  =  invite, suspend, reactivate, view — never touches role_id
core.roles.assign  =  change which role a membership carries
```

`core.staff.manage` alone was the whole story in Fase 1 — and turned out to
be a privilege escalation: nothing stopped someone holding it from rewriting
their *own* `role_id` via a plain `UPDATE`, or promoting anyone else to any
role. `core.roles.assign` plus `roles.rank` (migration `0008`) close that,
via one rule in `role_assignment_allowed()` (migration `0010`):

> an actor can never assign a role whose `rank` is `>=` their own, and never
> to their own membership, period.

No per-role special case is needed beyond that — the rank ordering alone
produces every row of this table:

| Actor | Gestisce staff inferiore | Assegna manager | Assegna property_admin | Assegna org_admin |
|---|---:|---:|---:|---:|
| Manager (20) | sì | no | no | no |
| Property Admin (30) | sì | sì | no *(rank 30 not < 30)* | no |
| Organization Admin (40) | sì | sì | sì | no *(rank 40 not < 40 — service-role only, §below)* |

An actor also can never promote themselves, under any role — checked
unconditionally in `role_assignment_allowed()`, no self-service exception.
See `rls.md` for how this is enforced structurally (a dedicated function,
not a generic `UPDATE`), and `auth.md` for how inviting staff (which also
assigns an initial role) goes through the same rule.

**Managing other `organization_admin`s stays service-role only** — not because
of a special rule, but because the rank comparison (`40 < 40`) is false for
every organization_admin, including against another organization_admin.
Documenting this explicitly since you asked for it: the alternative would be
a carve-out letting some organization_admins outrank others, which is exactly
the kind of special-casing the rank model exists to avoid. If that's ever
needed, it means introducing a rank above 40 for a "super admin" tier, not
threading an exception through this function.

## Organization-level access

An `organization_admin` doesn't get one membership row per property under
their org. Their single org-wide membership (`memberships.organization_id`
set, `property_id` null) is resolved by an OR-branch inside both
`has_property_access()` and `has_permission()`:

```sql
m.property_id = p_property_id
or m.organization_id = (select organization_id from properties where id = p_property_id)
```

**Trade-off, as requested to document explicitly:** this is one extra
condition in two functions, plus the `memberships_exactly_one_scope` check
constraint and two partial unique indexes (see `data-model.md`) — against
the alternative of duplicating a membership row per property for every
org-wide admin. Given how often organization-level roles are expected to
exist relative to property-level ones, the extra condition is cheap and the
duplication would only grow more tedious to keep in sync (add a property,
remember to add every org admin's membership to it too). Verified in
`supabase/tests/009_organization_level_access.test.sql`.

Actions on the organization *itself* (renaming it, creating a new property
under it) use a separate, org-scoped-only function,
`has_organization_permission()` — a property-scoped membership doesn't grant
organization-level authority; only `has_permission`'s OR-branch runs in that
direction, not the reverse.
