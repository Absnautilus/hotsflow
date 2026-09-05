# Hotsflow — current state

Last updated: 2026-09-05.

This file is the short authoritative snapshot of the platform after the first production cutover. Historical Fase 2 documents describe the migration as it evolved and can contain pre-cutover statements; when they conflict with this file, this file wins.

## Production

Housekeeping / `guest_requests` for Palazzo Veneziano is running against the shared Hotsflow Supabase backend. The Vercel production deployment was repointed from the legacy Supabase project to the shared project and validated after cutover. The legacy backend is frozen and retained only as a safety net.

The production migration moved the real hotel dataset and staff identities into the shared platform. Reconciliation completed without PK/FK anomalies; the migrated staff have Core profiles/memberships and the property has the module entitlement enabled.

## Authorization

Database authorization for `guest_requests` is already Core-backed through the Fase 2 compatibility wrapper. `staff_profiles.role` is not the authoritative database authorization source. Legacy module helpers such as `current_staff_hotel()`, `current_staff_role()` and `current_staff_is_master()` are compatibility surfaces whose decisions are derived from Core memberships/roles/permissions while preserving transitional module semantics where documented.

The approved legacy bootstrap mapping is:

- `admin` → `property_admin`
- `operatore` → `receptionist`
- `master` → `organization_admin`

This mapping is a migration/compatibility decision, not a statement that legacy `master` and Core `organization_admin` are generally equivalent concepts.

Staff management uses `core.staff.manage`; PMS management uses `guest_requests.pms.manage`. Operational Housekeeping tables remain intentionally constrained by the module's transitional single-hotel operational context.

## PR0 security correction

After cutover, the legacy `hotels_select_master` policy was found to retain a platform-wide visibility assumption from the old `master` model. PR #4 changed that policy so hotel visibility is scoped to the organization actually covered by the caller's Core authority, with a pgTAP cross-organization regression test.

The repository change is merged to `main`. Applying a repository migration to the live Supabase project remains a separate explicit deployment action; a merge alone must never be interpreted as a production database deploy.

## Remaining frontend migration

Housekeeping still owns legacy frontend concerns that the App Shell work will progressively remove or centralize, including session/bootstrap presentation, global navigation/account UI, build-time hotel context, and several UI decisions based on legacy role labels.

The target is capability-driven frontend behavior using the shared Core runtime context. Hidden UI is never the security boundary; database RLS remains enforcement.

A key integration blocker is the current build-time `VITE_HOTEL_ID` assumption. Shell-integrated Housekeeping must receive property context at runtime and resolve the corresponding legacy hotel through the authoritative mapping while the compatibility model exists.

## App Shell direction

The next product phase is a unified Hotsflow App Shell. The current preferred topology is a separate shell frontend rather than turning the Core SDK/database repository into a large monorepo. Existing modules remain independently owned while consuming shared identity, tenant, entitlement and authorization context.

Initial shell responsibilities:

- authenticated session and profile;
- accessible properties and active property;
- membership and permission context;
- module entitlements;
- global navigation and account UI;
- explicit shared states such as no property, module unavailable, permission denied and recoverable network error;
- deep-link restoration with property/entitlement/permission validation.

The first module integration pilot is Housekeeping. `shifts` and `transfers` remain outside the first shell integration PR.

## Source-of-truth rules

- Shared Supabase migration history: this repository (`hotsflow`).
- Housekeeping's old `supabase/migrations/`: frozen legacy history; do not add shared-production migrations there.
- Core authorization: memberships → roles → role_permissions → permissions, with entitlement checked separately through `property_modules`.
- Module-specific operational data/business logic remains owned by the module.
- Production database mutations and deployment are explicit operations, separate from merging code.
