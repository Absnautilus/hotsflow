# Turni → Hotsflow integration plan

Status: implementation plan only. No production database changes are made by this document.

## Verified current state

The standalone Planner Turni application already persists operational data in its own Supabase project. The live schema currently contains:

- `profiles` — 11 rows; also acts as the module's employee record and is keyed directly to the Planner project's `auth.users.id`
- `turni` — 1,357 rows
- `richieste_swap`
- `richieste_assenza`
- `richieste_preassegnazione`
- `stato_mese`
- `impostazioni`
- `preferenze`
- `notifiche_lette`
- `push_subscriptions`

The shared Hotsflow production project does not currently contain these Turni-owned tables. It does contain the Core tenant/identity model (`organizations`, `properties`, `profiles`, `memberships`, roles/permissions, module entitlements) and the Housekeeping module tables.

The Planner frontend currently queries its tables without a tenant key. This is safe only while the module is effectively single-property. It cannot be mounted against the shared Hotsflow database as-is.

A technical module boundary now exists in the Planner repository: Hotsflow can inject its already-authenticated Supabase client and the embedded build can omit duplicate Planner chrome. That boundary must remain disconnected from Hotsflow production until the data and RLS work below is complete.

## Target contract

Core continues to own identity, property access, roles/permissions and module entitlement. Turni owns its business tables.

Every Turni-owned business row must be property-scoped. The canonical rule is:

```text
Turni row -> property_id -> properties.id
```

The module must never infer tenant scope from a module-local user row, an email address, or the currently selected employee.

## Schema transition

### Employee data

Do not reuse Core `profiles` as the Planner employee/business record. Core profiles are platform identity; Planner profiles contain module-specific fields such as employee type, rest rotation, annual quotas, operational ordering and shift extras.

Create a Turni-owned employee table, recommended name `shift_staff_profiles`:

```text
shift_staff_profiles
- id uuid primary key
- property_id uuid not null references properties(id)
- profile_id uuid not null references profiles(id)
- employee_type
- rest_type
- fixed_rest_day
- rotation_slot
- active
- color
- extra_shifts
- annual_leave_quota
- annual_permission_hours
- team_member
- display_order
- credentials_to_set (temporary compatibility only, if still required)
- created_at
- unique(property_id, profile_id)
```

Core role/membership remains authoritative for authorization. The legacy Planner `is_admin` flag is migration input only and must not remain an independent security authority.

### Operational tables

Create shared-project Turni tables with a mandatory `property_id` on each tenant-owned row. Preserve the current business payload initially to minimize application changes:

- `shifts` (legacy `turni`)
- `shift_month_states` (legacy `stato_mese`)
- `shift_swap_requests`
- `shift_absence_requests`
- `shift_preassignment_requests`
- `shift_preferences`
- `shift_read_notifications`
- `shift_settings`
- Turni push subscriptions should use either a module-owned property-scoped table or a later shared notification contract; do not collide with Housekeeping's current `push_subscriptions` table by name.

All uniqueness constraints that are currently global must include `property_id`. Examples:

```text
shifts: unique(property_id, staff_profile_id, year, month, day)
shift_month_states: primary key(property_id, year, month)
shift_settings: primary key(property_id, key)
shift_preferences: primary key(property_id, staff_profile_id)
```

## Authorization target

Turni UI and RLS must use Core capability checks, not the legacy `is_admin` boolean.

Initial capability set should be deliberately small and business-oriented. Recommended baseline:

- `shifts.view`
- `shifts.manage`
- `shifts.requests.manage`

`shifts.view` is enough for ordinary staff to see the roster and their own workflow. `shifts.manage` covers roster generation/manual assignment, employee configuration and coverage rules. `shifts.requests.manage` covers administrative approval of leave/preassignment/swap workflows where elevated approval is required.

Exact grants should be reviewed against current Planner behavior before deployment. Hiding controls in React is not security; RLS remains authoritative.

Every policy also checks module entitlement for the selected property.

## Identity migration

Planner Auth UUIDs cannot be copied blindly into Hotsflow because they belong to a different Supabase Auth project.

For each legacy Planner employee:

1. resolve the person to an existing Hotsflow Auth/Core profile where possible;
2. create or reconcile the Hotsflow identity only through the migration identity workflow;
3. ensure an active membership exists for the target property;
4. create the `shift_staff_profiles` row using the Hotsflow Core `profile_id`;
5. record an explicit old-Planner-profile-id → new-Hotsflow-profile-id mapping for migration/reconciliation;
6. remap all foreign keys in shifts and request tables through that mapping.

Never use names as the final identity key. Email may be used as a controlled reconciliation signal, but migration output must resolve to UUID mappings and report ambiguities instead of guessing.

## Existing data migration

The current production Planner database has 11 employee rows and 1,357 shift rows. The migration must preserve those historical shifts rather than starting the shared module empty.

Migration order:

1. identify the target Hotsflow property (currently the Palazzo Veneziano operational dataset unless explicitly changed);
2. reconcile all legacy employee identities;
3. insert `shift_staff_profiles`;
4. copy historical shifts using the identity map and target `property_id`;
5. copy month states, preferences, settings and request data;
6. reconcile row counts and broken references;
7. only after successful reconciliation, enable the `shifts` entitlement and point the shell module at the shared client.

Minimum reconciliation gates:

- legacy employee count = mapped + explicitly excluded count
- all migrated staff rows reference an accessible Hotsflow profile/membership
- legacy shift count = migrated shift count unless exclusions are explicitly documented
- zero shifts referencing an unmapped employee
- zero rows with null/foreign `property_id`
- zero cross-property reads/writes in RLS regression tests

## Frontend transition

The first embedded implementation should remain deliberately thin:

1. Hotsflow shell supplies the shared Supabase client and active `propertyId`.
2. Turni module receives both values from its module gate.
3. All module queries include/derive the selected property scope.
4. Module-local login, logout and account chrome remain available only in standalone mode.
5. Internal Turni operational navigation stays module-owned.
6. Legacy `is_admin` UI checks are replaced incrementally with capability props/checks from Core.
7. Local-storage keys that represent business/user state must be property-scoped before multi-property switching is enabled.

The shell must fail closed when:

- the `shifts` entitlement is disabled;
- the active user has no membership/access for the selected property;
- Turni's staff-profile mapping is absent when the requested screen requires one.

## Delivery sequence

### T0 — module packaging

Completed in Planner Turni: injectable Supabase client, embeddable entry point, library build and embedded chrome suppression.

### T1 — additive shared schema

Add Turni-owned property-scoped tables, permissions and RLS to the Hotsflow repository, with pgTAP regression tests. No legacy data is modified.

### T2 — migration tooling and rehearsal

Build read-only export/reconciliation tooling for the legacy Planner project and migration scripts against a non-production target/rehearsal environment. Explicitly test identity remapping.

### T3 — production data migration

Requires explicit production authorization. Copy data into the shared project and run reconciliation. Keep the standalone Planner production system intact until acceptance.

### T4 — shell mount

Pin the reviewed Turni module in `hotsflow-app`, add a `/turni/*` gate using active property + `shifts` entitlement, and deploy first to preview. Perform authenticated functional smoke testing before production acceptance.

### T5 — authorization/UI cleanup

Replace remaining legacy admin booleans and standalone-only account logic with Core capabilities, then converge visual primitives with the Hotsflow design system without rewriting the scheduling domain logic.

## Non-goals for the first migration

- rewriting the scheduling algorithm;
- redesigning the entire Planner UI before technical integration;
- merging Turni business tables into Core tables;
- sharing Housekeeping tables directly;
- deleting the legacy Planner project immediately after cutover;
- introducing multi-property aggregate planning in the first release.
