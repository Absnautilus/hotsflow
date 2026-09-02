# Production Data Migration Plan — Guest Requests (Fase 2)

Status as of this plan: **NOT APPROVED, NOT EXECUTED.** No production data has been
read, exported, or written by anything in this document. Every query below is
read-only unless explicitly marked otherwise, and every marked-otherwise step
requires separate, explicit approval before it runs.

This plan exists because the pre-cutover infrastructure gate found that
`hotels` on the shared Hotsflow project contains only the 3 demo/E2E fixture
hotels — the real production hotel (legacy id `25b00bec-1602-46e9-bf52-a4913ebb5bdb`,
the value currently in Vercel's `VITE_HOTEL_ID`) has never been migrated.
Everything validated so far in Fase 2 (194→198 pgTAP tests, the full E2E
suite, the 5-step deploy gate) exercised only the demo hotels. This is the
first time this migration path is designed at all.

Updated Fase 2 status:

```
Platform/schema migration       COMPLETE
Security migration              COMPLETE
Demo/E2E validation             COMPLETE
Production data migration       NOT STARTED
Production cutover              BLOCKED
```

---

## A. Source inventory

Derived from the actual legacy schema (all 18 migrations in
`Housekeeping/supabase/migrations/0001_init.sql` through `0018_...sql`,
read in full — not assumed). This is the complete set of tables; a
repo-wide search for `create table` confirms no others exist.

| Table | Classification | PK | FK / depends on | `auth_user_id`? | secret/token? | personal data? | active vs historical |
|---|---|---|---|---|---|---|---|
| `hotels` | **MUST MIGRATE** | `id` | — (root) | no | no | no | config (1 row) |
| `staff_profiles` | **MUST MIGRATE** | `id` | `hotel_id`→hotels, `auth_user_id`→auth.users (unique) | **yes** | no | yes (`name`) | active roster |
| `rooms` | **MUST MIGRATE** | `id` | `hotel_id`→hotels | no | no | no | config |
| `request_categories` | **MUST MIGRATE** | `id` | `hotel_id`→hotels | no | no | no | config |
| `request_types` | **MUST MIGRATE** | `id` | `category_id`→request_categories | no | no | no | config |
| `stays` | **MUST MIGRATE (scoped)** | `id` | `hotel_id`, `room_id`→rooms, `created_by`→staff_profiles | no | `guest_pin` (login PIN) | yes (`guest_last_name`) | mixed — see §E |
| `guest_requests` | **MUST MIGRATE (scoped)** | `id` | `hotel_id`, `stay_id`→stays (nullable), `request_type_id`, `accepted_by`/`created_by_staff`→staff_profiles | no | no | possibly (`note` free text) | mixed — see §E |
| `pms_integrations` | **MIGRATE IF PRESENT** | `hotel_id` | `hotel_id`→hotels | no | **yes** — `ohip_client_id`/`ohip_client_secret`/`ohip_app_key` | no | current config only, no history |
| `guest_sessions` | **DO NOT MIGRATE** | `id` | `stay_id`→stays | no | `token_hash` + `created_ip` | yes (IP) | ephemeral |
| `guest_login_attempts` | **DO NOT MIGRATE** | `id` | `hotel_id`→hotels | no | no | yes (IP, room attempted) | append-only audit log |
| `push_subscriptions` | **DO NOT MIGRATE** | `id` | `staff_id`→staff_profiles | no | `p256dh`/`auth` (push encryption keys) + `endpoint` | device-identifying | ephemeral, VAPID-bound |
| `auth.users` | separate — see §B | — | — | is | password hash | yes | — |

No values (names, PINs, secrets, IPs) are reproduced in this document —
only column names and structural facts, as requested.

### Row counts (needs a live query — I have no DB access)

Run this once on the **legacy Housekeeping** project (single query, so
Studio's "only shows the last statement" limitation doesn't apply — every
count comes back in one result set):

```sql
select 'hotels' as table_name, count(*) from hotels
union all select 'staff_profiles', count(*) from staff_profiles
union all select 'rooms', count(*) from rooms
union all select 'request_categories', count(*) from request_categories
union all select 'request_types', count(*) from request_types
union all select 'stays', count(*) from stays
union all select 'stays_active', count(*) from stays where status = 'active'
union all select 'guest_requests', count(*) from guest_requests
union all select 'guest_requests_open', count(*) from guest_requests where status in ('requested','in_progress') and archived_at is null
union all select 'pms_integrations', count(*) from pms_integrations
union all select 'guest_sessions', count(*) from guest_sessions
union all select 'guest_login_attempts', count(*) from guest_login_attempts
union all select 'push_subscriptions', count(*) from push_subscriptions
union all select 'auth_users', count(*) from auth.users
order by 1;
```

**Result (run on legacy, 2026-09-02):**

| table | count |
|---|---|
| `hotels` | 1 |
| `staff_profiles` | 3 |
| `rooms` | 7 |
| `request_categories` | 6 |
| `request_types` | 12 |
| `stays` | 4 |
| `stays_active` | 1 |
| `guest_requests` | 25 |
| `guest_requests_open` | 2 |
| `pms_integrations` | 0 |
| `guest_sessions` | 16 |
| `guest_login_attempts` | 18 |
| `push_subscriptions` | 3 |
| `auth_users` | 3 |

Confirmed, not assumed: this is a trivially small, single-hotel dataset.
Concrete implications:
- **Transaction size risk (§K) is resolved, not just mitigated** — every
  table is in the single/low-double digits. One `begin;...commit;`
  transaction for the whole migration is entirely adequate; no batching
  needed.
- **`pms_integrations` = 0** — this hotel has no PMS integration configured
  at all. §A's "MIGRATE IF PRESENT" resolves concretely to "nothing to
  migrate" for now; no OHIP secret exists yet for this hotel to handle
  carefully. (Still true that if one is configured later, the same
  presence-only verification in §G applies.)
- **`auth_users` = 3 exactly matches `staff_profiles` = 3** — clean 1:1,
  no orphan or unrelated Auth users to account for. Only 3 real accounts
  go through the §B Auth-UUID test/remapping.
- **`stays_active` = 1 of 4**, **`guest_requests_open` = 2 of 25** — matches
  §E's active/open-only recommendation closely; only a handful of rows
  actually need transactional migration, the rest is archive-export.

---

## B. Auth users — separate treatment

`profiles.id` on the Hotsflow project is `uuid primary key references
auth.users(id) on delete cascade` (Core schema, `0004_profiles_memberships.sql`).
This means: **a `profiles`/`memberships` row for a staff member cannot exist
at all until a matching `auth.users` row exists on the Hotsflow project with
that exact id.** Copying `staff_profiles` alone, without a real `auth.users`
counterpart on the new project, is not a partial migration — it's not a
migration, the inserts would fail their FK. Flagging this explicitly because
it's the exact gap you said not to consider acceptable.

What's achievable, checked against what Supabase's Auth Admin API actually
supports (not assumed):

| | Preservable? | How |
|---|---|---|
| **email** | Yes | `admin.createUser({ email })` accepts any email, including reusing the legacy one — no conflict risk, no other account uses these emails on Hotsflow yet. |
| **password / login continuity** | **No**, not via the supported path | The Admin API has no endpoint that accepts a pre-computed password hash for import. The only way to set a password through it is to supply a brand-new plaintext one — which neither of us should know the real one to preserve. Writing directly into `auth.users.encrypted_password` via raw SQL is technically possible (it's a normal Postgres column) but is explicitly outside Supabase's supported surface for that schema — I'm not proposing it, same reasoning as never touching other systems' internals directly in this engagement. |
| **user UUID** | **NOT SUPPORTED BY THE DOCUMENTED ADMIN API** | Supabase's current `auth.admin.createUser()` documentation does not document an `id` parameter — there is no supported, documented way to request a specific user UUID. |

**Recommended continuity approach**, split by account type (they have very
different friction profiles):

- **admin accounts** (real people, real email+password): after cutover, send
  a normal Supabase password-reset email (`admin.generateLink({type:'recovery', email})`
  or the standard "forgot password" flow) to each admin. One-time
  inconvenience, a flow these users already know.
- **operatore accounts** (username + 6-digit PIN, not a real personal
  credential — already routinely reset by an admin through the existing
  create-staff-account UI): re-create with a fresh PIN via the same, already-
  existing admin flow. No email involved, low friction, no new capability
  needed.

**Documented/supported vs. undocumented/empirical — kept explicitly
separate, not blurred:**

- **Documented, supported behavior:** the Admin API does not offer a way to
  set the user id. Treat UUID preservation for `auth.users` as unsupported
  for planning purposes.
- **Undocumented, empirical behavior:** the current SDK/GoTrue
  implementation *might* still accept and honor an explicit `id` in the
  request body even though it isn't documented — implementations sometimes
  accept more than their docs describe. A disposable test (create one
  throwaway user with an explicit id, check what actually comes back, then
  delete it) can observe this either way.

**These are not the same thing, and a successful test does not
automatically become the migration strategy.** If the empirical test
succeeds, that is a new fact requiring its own explicit decision — whether
we're willing to depend on undocumented behavior for a production
migration, with the attendant risk that a future Supabase/GoTrue update
silently changes or removes it — not an automatic green light. If it fails
or is unsupported, §D below (explicit UUID remapping) is the fallback path,
designed either way.

**Pre-step (not yet executed, needs its own go-ahead even though it's
small and reversible):** create ONE disposable test user on the Hotsflow
project via the Admin API with an explicit `id`, record only whether the
id was honored or replaced (no other data), then delete it.

**Empirical test result (run 2026-09-02, against the Hotsflow project's
GoTrue Admin endpoint directly):** the explicit `id` was honored — the
created user's `id` came back exactly as requested
(`11111111-1111-1111-1111-111111111111`). This confirms the undocumented
behavior exists on the current implementation. It is classified as
**empirically verified, not contractually guaranteed or documented** — it
does not change the documented/supported status above, and does not by
itself decide whether production depends on it or authorize building the
final migration plan on the assumption that this capability is stable
over time. A supported/documented strategy (§B.1 below) remains
preferable where one exists.

**Cleanup status: not yet confirmed.** The disposable test user
(`auth-uuid-test-disposable@example.test`, id
`11111111-1111-1111-1111-111111111111`) must be deleted from the live
Hotsflow project — this experiment must not leave a residual fixture.
This is a requirement, not an assumption: verify deletion with
```sql
select count(*) from auth.users where id = '11111111-1111-1111-1111-111111111111';
-- expect 0
```
rather than treating "I clicked delete" as sufficient on its own — confirm
the row is actually gone before considering this test closed out.

**Cleanup confirmed (2026-09-02):** the disposable test user was deleted
from the live Hotsflow project via Studio. No residual fixture from this
experiment remains.

### B.1 Before any dry-run: five explicit questions on the UUID dependency

**1. What happens if the API stops accepting an explicit UUID in the
future?** The migration script must not hard-code an assumption either
way — it detects this at runtime, per user, not at design time for the
whole batch: call `createUser()` with the explicit `id`, then read the
`id` actually returned. If it matches, proceed. If it doesn't (behavior
changed or was never available on a given run), fall back automatically
to B.2's remapping table for that user instead of failing the whole
migration. The script works correctly either way without needing to know
in advance which case it's in.

**2. Is there a documented/supported alternative mapping strategy?**
Yes — **explicit remapping, not UUID preservation, is the
documented/supported path.** Call `createUser({ email })` with no `id`
(fully within documented behavior), capture whatever id GoTrue assigns,
and record the pair in a lookup table:
```sql
create temporary table auth_uuid_remap (
  legacy_auth_user_id uuid primary key,
  new_auth_user_id uuid not null
);
```
Every reference this migration writes (`staff_profiles.auth_user_id`,
`profiles.id`, `memberships.profile_id`) uses `new_auth_user_id` from this
table, never the legacy value. This was already sketched as §D's fallback;
here it's confirmed as the actually-preferred, fully-documented default —
not merely a fallback for if the empirical behavior fails, but the
strategy to prefer regardless, per the instruction to favor a
supported/documented approach when one exists.

**3. Which FK/tables actually depend on the `auth.users` UUID being
preserved?** Exactly three, all within Core's own schema, and all
rewritable via the remapping table regardless of which id GoTrue assigns:
`staff_profiles.auth_user_id` (FK → `auth.users.id`, unique),
`profiles.id` (PK, FK → `auth.users.id`), `memberships.profile_id` (FK →
`profiles.id`). Nothing outside this chain touches the Auth id directly —
`guest_requests.accepted_by`/`created_by_staff` reference
`staff_profiles.id` (our own PK, always preservable per §C), not the Auth
id at all.

**4. Is UUID preservation a requirement, or only a simplification?**
**Only a simplification.** Given #3's scope, any value works as the Auth
id as long as it's used consistently across those three columns — the
remapping table guarantees that regardless of the actual id chosen.
Nothing downstream depends on the *value* matching the legacy one, only
on internal consistency. Preserving it saves one translation step; it is
not required for correctness.

**5. Precise rollback if part of the Auth migration succeeds and part
fails** (e.g. 2 of 3 staff accounts created, the 3rd fails): this is not
covered by §I.1's single-transaction rollback, because creating an
`auth.users` row happens through an HTTP call to GoTrue, not a SQL
statement inside the migration's transaction — a Postgres `ROLLBACK`
cannot undo it. Explicit procedure:
- Auth-user creation runs as its own isolated step, strictly *before* the
  SQL provisioning transaction (§D/§I.1) starts, and that transaction only
  begins once all required Auth users are confirmed created with their
  ids captured — an explicit precondition check, not an assumption.
- Track each `createUser()` call's outcome as it happens (not just at the
  end).
- On any failure partway through: **do not proceed to the SQL
  transaction at all.** Delete every Auth user this run already created
  successfully (via `admin.deleteUser()`, using the ids captured in the
  previous step), so no orphaned `auth.users` row is left behind with no
  corresponding application data. Then abort and retry from a clean
  slate.
- The dry-run (§F) should explicitly exercise this failure path — simulate
  a failure partway through, verify the cleanup actually removes what
  succeeded — not just the happy path.

One incidental finding from running this test, unrelated to its result:
the Hotsflow project uses Supabase's newer Publishable/Secret API key
format (`sb_secret_...`), not the legacy `service_role` JWT — same
privilege level, different naming. Also, Supabase's gateway refuses a
secret key on any request whose `User-Agent` looks browser-like (a
deliberate safeguard against a secret key ending up in client-side code) —
the test needed an explicit non-browser `User-Agent` override to get past
it, which is a useful thing to know for §L's real migration script too.

---

## C. Preserve IDs — table by table

| Table | Preserve legacy UUID? | Why |
|---|---|---|
| `hotels.id` | **Yes, recommended** | Fully under our control (our own INSERT). Confirmed zero collision on hosted (the query that found this whole gap returned 0 rows for this id). Preserving it means `VITE_HOTEL_ID` never has to change. |
| `rooms.id` | Yes | Fully under our control, nothing external references a room by UUID. |
| `request_categories.id` / `request_types.id` | Yes | Same — fully under our control, no external reference. |
| `stays.id` | Yes (no compatibility payoff, but no harm) | Guest login is room+surname, not a URL carrying `stays.id` — nothing external needs this preserved, but preserving it costs nothing and keeps FK tracing clean. |
| `guest_requests.id` | Yes | One thing worth noting for completeness: `notify-new-request`'s push payload embeds `requestId: record.id` in already-sent notifications' click-through URL — but those notifications are one-shot and push subscriptions aren't being migrated anyway (see §A), so this creates no ongoing dependency. |
| `staff_profiles.id` | Yes | Our own table, not Auth's — no blocking dependency. |
| `staff_profiles.auth_user_id` / `profiles.id` | **No — simplification only, not required (see §B.1.4)** | The one id genuinely outside our control. The empirical test (§B) showed the current API *can* honor a caller-supplied id, but this is undocumented, not contractually guaranteed, and per §B.1 the documented/supported default is explicit remapping (§B.1.2) rather than depending on it — everything else in this table stays preservable regardless of which path is used. |

Bottom line: every ID we mint ourselves is safe and recommended to preserve.
The single exception is Auth-owned, and is a known open question, not an
assumption either way.

---

## D. Core provisioning — scoped to the production hotel only

**Do not call** `backfill_staff_identity()` or
`backfill_guest_requests_entitlement()` — both are whole-table and have
already caused two real incidents this engagement (the Hotel Demo 2
entitlement collision, and master silently gaining reach into Hotel Demo
3's new organization). The pattern below is the same scoped-INSERT approach
already proven safe for the Hotel Demo 3 fixture, applied to the real hotel
instead of a demo one. Shown for review — **not executed**.

```sql
-- STEP 1 — organization + property + legacy_property_mapping, this hotel only
insert into organizations (name, slug) values ('<hotel name>', '<slug>')
  returning id as v_org_id;
insert into properties (organization_id, name, slug, timezone, status)
  values (v_org_id, '<hotel name>', '<slug>', '<timezone>', 'active')
  returning id as v_property_id;
insert into legacy_property_mapping (legacy_hotel_id, platform_property_id)
  values ('25b00bec-1602-46e9-bf52-a4913ebb5bdb', v_property_id);

-- STEP 2 — one membership per migrated staff_profiles row (after §B is
-- resolved and staff_profiles/profiles/auth.users rows exist)
--   admin      -> role 'property_admin', property_id = v_property_id
--   operatore  -> role 'receptionist',   property_id = v_property_id
--   master     -> role 'organization_admin', organization_id = v_org_id
--                 (only if the real dataset actually has a master row —
--                 unconfirmed, check via the row-count/role query below)
-- status: staff_profiles.active = true -> 'active', false -> 'suspended'
-- (same mapping the whole-table function uses, applied per row here)

-- STEP 3 — entitlement, this property only
insert into property_modules (property_id, module_id, enabled)
select v_property_id, id, true from modules where slug = 'guest_requests';
```

Check now (read-only, safe to run any time) whether production actually has
a `master` account at all, since that changes whether STEP 2 needs the
organization_admin branch:

```sql
select role, count(*) from staff_profiles group by role;
```

No new roles/permissions needed — `property_admin`, `receptionist`,
`organization_admin` already exist as seeded reference data.

### Default plan: explicit Auth UUID remapping (per §B.1.2)

Since UUID preservation for `auth.users` is not supported by the documented
API, the default (not undocumented-behavior-dependent) design — confirmed
preferred, not just a fallback, per §B.1's five points — is an explicit
remapping table built during migration, not a silent id swap. Same table
as §B.1.2:

```sql
create temporary table auth_uuid_remap (
  legacy_auth_user_id uuid primary key,
  new_auth_user_id uuid not null
);
```

For each legacy `staff_profiles` row: create the corresponding user on
Hotsflow via `admin.createUser({ email })` (new, server-generated id),
record the pair in `auth_uuid_remap`, then use `new_auth_user_id` — never
the legacy one — everywhere a migrated row needs to point at Auth:
`staff_profiles.auth_user_id`, `profiles.id`, and `memberships.profile_id`.
`staff_profiles.id` itself (our own PK, not Auth's) is still preserved
per §C regardless of which Auth id ends up attached to it. This is the plan
unless the §B experiment's result changes what we're willing to depend on —
in which case that's a separate decision, made explicitly, not inferred
from the experiment succeeding.

---

## E. Active vs historical data — per dataset

| Dataset | Options considered | Recommendation |
|---|---|---|
| `stays` | (1) all history (2) active only (3) archive + migrate current | **Active only** (`status = 'active'`). Guests mid-stay need to keep logging in after cutover; closed/cancelled stays are pure history with no forward dependency. |
| `guest_requests` | same three | **Open only** (`status in ('requested','in_progress') and archived_at is null`) — whatever's actually in the live queue at cutover, so nothing mid-flight gets lost. Completed/cancelled/archived rows are historical. |
| `guest_login_attempts` | — | **Do not migrate**, any option. It's an append-only rate-limit/abuse log with no "current" concept and no forward dependency. Archive-export only if you have a specific compliance reason to keep it (tell me if so — otherwise it stays in the legacy project until decommission). |
| `guest_sessions` | — | **Do not migrate.** Every token was issued for the legacy project's URL/anon key — it cannot authenticate against a different Supabase project regardless of whether the row exists there. Guests get a fresh session naturally on first visit to the new URL; their *stay* (migrated above) is what matters, not the old token. |
| `push_subscriptions` | — | **Do not migrate** — moot, not a data-loss risk: Web Push subscriptions are cryptographically bound to the VAPID key pair that created them, and VAPID was already decided `ROTATED`. Every existing subscription is invalid the moment the new key pair is live, migrated or not. Staff simply re-enable "on duty" push after cutover — an existing, already-normal action, not new work. |

For anything not migrated into the live transactional database, the
recommendation across the board is the same: a full **archive export**
(schema+data snapshot, e.g. `supabase db dump`) taken once before
decommissioning the legacy project, kept outside git in secure storage —
satisfies "don't lose history" without carrying dead rows (and their PII)
into the new production system.

---

## F. Dry-run strategy

No production PII or secrets are ever written into a file that gets
committed to this repository — the dry run uses synthetic data, not a real
export, for exactly that reason.

```
non-PII config tables (hotels, rooms, request_categories, request_types)
  → safe to use real structure/values as-is in a dry run, nothing personal
       ↓
PII/secret-bearing tables (staff_profiles, stays, guest_requests, pms_integrations)
  → synthetic substitute rows, same shape/constraints, fake content
       ↓
local Supabase stack (same Docker-based `supabase start` CI already uses)
  loaded with the full hotsflow-core migration history
       ↓
migration script run against the synthetic dataset
       ↓
§G integrity checks + existing E2E suite run against this disposable target
```

This reuses infrastructure that already exists (the CI job) rather than
inventing a new environment, and never touches the real legacy or Hotsflow
projects. Only once this passes cleanly does §L's real-data run happen.

---

## G. Integrity verification — concrete reconciliation queries

All read-only. Run source-side counts before migrating, target-side after.

**Row counts** (target, post-migration — compare against §A's source counts,
scoped per §E's active/open filters):
```sql
select
  (select count(*) from hotels where id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as hotels_migrated,
  (select count(*) from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as staff_migrated,
  (select count(*) from rooms where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as rooms_migrated,
  (select count(*) from stays where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as stays_migrated,
  (select count(*) from guest_requests where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb') as requests_migrated;
```

**PK preservation** (no null/duplicate ids post-migration):
```sql
select 'staff_profiles' as t, count(*) - count(distinct id) as dupes from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
union all select 'stays', count(*) - count(distinct id) from stays where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
union all select 'guest_requests', count(*) - count(distinct id) from guest_requests where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';
-- expect 0 everywhere
```

**FK integrity** (orphan checks):
```sql
select 'stays_missing_room' as check_name, count(*) from stays s
  where s.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
  and not exists (select 1 from rooms r where r.id = s.room_id)
union all
select 'requests_missing_type', count(*) from guest_requests gr
  where gr.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb'
  and not exists (select 1 from request_types rt where rt.id = gr.request_type_id)
union all
select 'requests_missing_stay', count(*) from guest_requests gr
  where gr.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb' and gr.stay_id is not null
  and not exists (select 1 from stays s where s.id = gr.stay_id);
-- expect 0 everywhere
```

**Hotel → property mapping:**
```sql
select h.id, h.name, m.platform_property_id, p.name as property_name, p.organization_id
from hotels h
join legacy_property_mapping m on m.legacy_hotel_id = h.id
join properties p on p.id = m.platform_property_id
where h.id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';
-- expect exactly 1 row
```

**Staff → auth user → membership chain** (the check that would have caught
"staff_profiles copied, Auth user missing"):
```sql
select
  sp.id as staff_profile_id, sp.role,
  (au.id is not null) as auth_user_exists,
  (pr.id is not null) as profile_exists,
  (select count(*) from memberships m where m.profile_id = sp.auth_user_id) as membership_count
from staff_profiles sp
left join auth.users au on au.id = sp.auth_user_id
left join profiles pr on pr.id = sp.auth_user_id
where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';
-- expect auth_user_exists=true, profile_exists=true, membership_count>=1 for every row
```

**Entitlement:**
```sql
select pm.enabled from property_modules pm
join legacy_property_mapping m on m.platform_property_id = pm.property_id
join modules mod on mod.id = pm.module_id
where m.legacy_hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb' and mod.slug = 'guest_requests';
-- expect exactly 1 row, enabled = true
```

**PMS configuration** (presence only — never select the secret columns):
```sql
select hotel_id, mode, (ohip_client_id is not null) as has_client_id,
  (ohip_client_secret is not null) as has_secret
from pms_integrations where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb';
```

**Active/suspended staff mapping consistency:**
```sql
select
  (select count(*) from staff_profiles where hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb' and active) as legacy_active,
  (select count(*) from memberships m join staff_profiles sp on sp.auth_user_id = m.profile_id
   where sp.hotel_id = '25b00bec-1602-46e9-bf52-a4913ebb5bdb' and m.status = 'active') as core_active;
-- expect equal
```

---

## H. Delta during cutover

Given a single hotel at this stage, the simplest safe option is the right
one, per your own instruction to prefer that over live replication:

- **A. Short write freeze (recommended).** Put the legacy app in a brief
  maintenance state (a banner, or literally offline) for the migration
  window — export/migrate runs once, atomically, then env vars flip. No
  divergence is possible because nothing writes during the freeze.
- **B. Second delta migration pass.** Diff what changed between export and
  cutover, re-run a partial migration. More moving parts, more failure
  modes, not justified at this scale — not recommended.
- **C. Live replication.** Overkill for one hotel — not recommended.

Runbook for A: announce the window in advance → freeze writes on legacy →
run migration script → run §G checks → run E2E smoke against the migrated
data → flip Vercel env vars → verify production → lift the freeze.

---

## I. Rollback — three scenarios, three different answers

**1. Migration fails before cutover.** Trivial. The script runs inside one
`begin; ... commit;` transaction (same convention as every migration in this
repo) — a failure mid-script rolls back everything on the target
automatically. Legacy was only ever read from. Fix the cause, re-run from a
clean slate.

**2. Cutover fails, no new writes yet landed on the new backend.** Rollback
= point Vercel's env vars back at the legacy project. Legacy was never
touched, so this is instant and lossless.

**3. Cutover fails after real writes exist on the new backend** (a guest
submitted a request, staff accepted one, on Hotsflow). This is the case
where "revert the env vars" is **not** sufficient, exactly as you flagged —
doing that alone silently discards real actions.
- Freeze writes on both backends the moment the problem is found.
- Export the delta: everything on Hotsflow created after the known cutover
  timestamp (`where created_at > '<cutover_time>'`, bounded and small since
  the freeze in §H gives an exact boundary).
- Default to **forward-fix, not backward-revert**: once real writes exist on
  the new backend, fixing the problem there is strictly lower-risk than
  reverting and manually replaying those writes back into legacy. Reverting
  is reserved for a severe/blocking failure, and even then only after the
  delta rows are exported and reviewed by hand — never an automatic revert.
- This step is a judgment call in the moment, not something to fully
  script — flagged as HIGH risk in §K rather than pretending it's solved.

---

## J. Legacy project

Stays fully intact and untouched throughout every step above — nothing in
this plan writes to or modifies the legacy Housekeeping Supabase project at
any point; it is read-only source, until you separately decide to
decommission it (recommend keeping it live-but-frozen for some period after
cutover as a fallback, not deleting immediately).

---

## K. Risks

| Risk | Level | Why |
|---|---|---|
| `auth.users` UUID preservation not supported by the documented API | **HIGH** (unchanged despite a successful empirical test) | The 2026-09-02 test confirmed the current implementation honors an explicit `id`, but this is undocumented behavior that could change without notice. Default plan (§D fallback) is explicit remapping, not dependent on it. Whether to instead depend on the empirical behavior for the real migration is still an open, explicit decision — a successful test doesn't resolve the risk by itself. |
| Password/login continuity requires reset/reinvite | **HIGH** | Real user-facing friction on cutover day — needs to be communicated to staff in advance, not discovered by them. |
| Rollback after new writes land on the new backend | **HIGH** | Inherently a manual judgment call (§I.3) — cannot be fully automated or pre-scripted. |
| `pms_integrations` secret handling | MEDIUM | `ohip_client_secret`/`ohip_client_id`/`ohip_app_key` must never appear in a migration script's committed text, a log, or this document — only presence checks, never values. |
| `guest_requests.note` free text may contain guest PII | MEDIUM | Needs a retention/redaction decision if archived rather than migrated. |
| ~~Transaction size unknown~~ | ~~MEDIUM~~ **RESOLVED** | §A's row counts came back trivially small (max 25 rows in any table) — one single transaction is adequate, no batching needed. |
| Config tables (`hotels`, `rooms`, `request_categories`, `request_types`) | LOW | No PII, no secrets, fully under our control, same pattern already proven 3× this engagement for demo fixtures. |
| Preserving self-owned UUIDs | LOW | Well-precedented, no external system depends on any of them except `hotels.id` (Vercel), which is the one we most want to preserve and can. |

---

## L. Step-by-step execution plan (NOT TO BE EXECUTED until approved)

1. Run §A's row-count query on legacy (read-only).
2. Run §B's disposable Auth-UUID test on Hotsflow, then delete the test user (small, reversible write — needs its own explicit go-ahead even though the rest of this list is blocked pending full plan approval).
3. Finalize §C/§D's exact provisioning script now that §B's answer is known.
4. Build the dry-run per §F.
5. Run §G's checks + existing E2E suite against the dry-run target.
6. Fix anything §5 surfaces; repeat 4–5 until clean.
7. Schedule the maintenance window (§H) and tell staff about the password-reset step (§B) in advance.
8. Freeze writes on legacy.
9. Run the real migration script inside one transaction against Hotsflow.
10. Run §G's checks against the real result.
11. Flip Vercel env vars (only the ones this plan actually requires changing — `VITE_HOTEL_ID` stays the same if §C's preservation holds).
12. Smoke test production for real.
13. Lift the freeze.
14. Monitor; decide legacy's decommission timeline separately (§J).

---

## Decisions — status

1. Active-only / open-only migration for `stays` and `guest_requests` (§E), archive-export the rest. — **APPROVED**
2. Do-not-migrate for `guest_sessions`, `guest_login_attempts`, `push_subscriptions` (§A/§E). — **APPROVED** (no compliance-export need raised for `guest_login_attempts`)
3. Run the one disposable Auth-UUID test (§B/§L step 2). — **APPROVED as an experiment only.** A successful result is a new fact, not a green light: whether to depend on undocumented behavior for the real migration is a separate decision, still open, to be made explicitly once the result is in.
4. Preserve legacy UUIDs for `hotels`/`rooms`/`stays`/`request_categories`/`request_types`/`guest_requests`/`staff_profiles` (§C). — **APPROVED**
5. Write-freeze/maintenance-window approach for cutover (§H). — **APPROVED**; actual date/window still to be scheduled.
6. Forward-fix-not-backward-revert as the default policy once new-backend writes exist (§I.3). — **APPROVED as default**

## PRODUCTION DATA MIGRATION READY TO IMPLEMENT: NO

5 of 6 decisions are unconditionally approved; #3 is approved strictly as an
experiment, not as a strategy commitment. Immediate next actions, per this
approval: (1) commit this document, (2) run §A's row-count query on legacy
(read-only), (3) run the §B disposable Auth-UUID test and record only
whether the id was honored — nothing beyond those three is authorized yet.
Whether the real migration ends up using §D's explicit-remapping fallback or
depends on the empirical test's result is the one decision still open, and
it will be made explicitly once the test result is in — not inferred from
it succeeding.
