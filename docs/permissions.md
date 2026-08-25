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
configuration).

## The seeded roles

`supabase/seed.sql` ships the four roles from the Architecture Proposal's
own examples:

| role | scope | can do |
|---|---|---|
| `organization_admin` | organization | everything: `core.organization.manage`, `core.property.manage`, `core.staff.manage`, and every module permission |
| `property_admin` | property | everything except organization-level administration |
| `manager` | property | every module, plus `core.staff.manage` — matches "Manager -> puo usare tutti i moduli -> puo gestire staff" |
| `receptionist` | property | `transfers.use`, `guest_requests.view` only — no configuration, matches "Receptionist -> non puo modificare configurazione hotel" |

Extending this is additive: a new permission slug, a new `role_permissions`
row, or (rarely) a new role — never a redesign.

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
