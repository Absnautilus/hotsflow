# Architecture

This repository is the platform core for the hotel SaaS suite: the shared
layer of identity, tenant, permissions, module entitlement, and guest
sessions that the three existing applications (`guest_requests`, `shifts`,
`transfers`) will migrate onto progressively. It owns none of their business
logic and, as of Phase 1, none of them have been touched — see the
Architecture Proposal (approved separately) for the full rationale, the
three-module audit, and the migration order.

## The shape

```
Organization
    |
Properties
    |
Memberships --- Roles --- Permissions
    |
Enabled Modules (property_modules)
    |
Module data (owned by guest_requests / shifts / transfers, not this repo)
```

Staff and guests reach module data through the same gate
(`property_modules`), under different conditions:

- **Staff**: membership -> role -> permission, checked via `has_permission()`.
- **Guest**: a `guest_sessions` row that is not expired, not revoked, and
  meets whatever `verification_level` the action requires, checked via
  `guest_session_is_valid()`.

Neither path reaches a module's own tables directly through this repo —
those stay inside each module's own database. What this repo provides is
the *answer* to "who is this, what property, what can they do, is this
guest session real" — see `module-integration.md` for how a module actually
consumes those answers.

## What's implemented in Phase 1

- `organizations`, `properties`, `modules`, `property_modules`, `roles`,
  `permissions`, `role_permissions`, `profiles`, `memberships`,
  `guest_sessions` — full schema, RLS, and six SQL helper functions.
- A dev-only seed (`supabase/seed.sql`) and a minimal TypeScript SDK
  (`src/`).
- 9 pgTAP test files (`supabase/tests/`) proving tenant isolation,
  multi-property access, role-based authorization, module entitlement,
  membership revocation, guest session expiry/revocation/cross-property
  rejection, and organization-level access.

## What's deliberately not here yet

- `invitations`, `audit_logs` — no concrete need for either surfaced during
  Phase 1's own success criteria; added when a real module migration
  actually needs them, not speculatively.
- Any guest verification flow (room+surname, booking+surname, QR, secure
  link) — `guest_sessions` is built to hold them, none is implemented (see
  `guest-access.md`).
- Billing, Stripe, PMS/Opera/Mews integration, a shared dashboard,
  cross-module notifications, a design system, SSO, a monorepo, or
  microservices — all explicitly out of scope for this phase.
- Any change to `guest_requests`, `shifts`, or `transfers` — those start in
  Phase 2, one at a time, `guest_requests` first.
