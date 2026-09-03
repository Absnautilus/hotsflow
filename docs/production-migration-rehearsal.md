# Production Migration Rehearsal — plan and results

Status: **COMPLETE — all checks PASS.** Executed 2026-09-03 against a
disposable local Supabase stack inside a GitHub Actions runner
(`.github/workflows/rehearsal-migration.yml`, run
[33757292899](https://github.com/Absnautilus/hotsflow/actions/runs/33757292899),
attempt 2). Results in "Rehearsal Results" at the end of this document. No
production data migration has started; no cutover has occurred.

## Access constraint that shapes this whole design

I have no direct credentials to the legacy Housekeeping Supabase project —
confirmed by checking Housekeeping's own GitHub Actions workflows
(`e2e-smoke.yml`, `deploy-functions.yml`): both target `SUPABASE_PROJECT_REF`,
which is the *shared Hotsflow* project ref (set up earlier in Fase 2), not
the legacy one. There is no `deploy-migrations.yml` in Housekeeping and no
legacy DB secret anywhere in either repo's CI configuration. Every read of
the legacy project in this entire engagement has gone through you — running
queries in Studio, pasting results back. This rehearsal's export step is no
exception: **I cannot query the legacy project myself.** The design below
routes around that by having anonymization happen inline in the export
query itself, on your side, before anything leaves the legacy project's
trust boundary — never as a separate step I perform on raw data.

## 1. Tables read from legacy

| Table | Rows expected (from the plan's §A count) | Read for |
|---|---|---|
| `hotels` | 1 (the real hotel, filtered by id) | export |
| `staff_profiles` | 3 | export |
| `rooms` | 7 | export |
| `request_categories` | 6 | export |
| `request_types` | 12 | export |
| `stays` | 4 total (validation reads all 4; export takes only the active one) | validation + export |
| `guest_requests` | 25 total (validation reads all 25; export takes only the 2 open ones) | validation + export |
| `pms_integrations` | 0 | validation only (confirm still 0 — never assumed) |
| `auth.users` | 3 (matching staff_profiles) | validation only, via count — not bulk-exported as a table; handled by §6 |

`guest_sessions`, `guest_login_attempts`, `push_subscriptions` are **not
read at all** — same as the main plan, no export, no validation needed
since they're never migrated.

## 2. Export method

You run SQL in the legacy project's Studio SQL Editor (same tool you've
used for every legacy read in this engagement) — I cannot run it myself.
Two distinct query sets, run in this order:

1. **Validation queries** (§2 below, read-only, no anonymization needed —
   they only return counts/flags, not raw personal data) — run first,
   always, before any export query.
2. **Export queries** (§4) — anonymization happens *inside* the SELECT
   itself (case/hash expressions on the PII columns), so what Studio
   returns and what you download is already anonymized; the real values
   are never selected into the result set at all, not merely hidden
   afterward.

Studio's query result view has a CSV export button — that's the transfer
mechanism, given how small every one of these tables is (max 25 rows).

## 3. Intermediate artifact format

CSV, one file per table, downloaded directly from Studio's result view.
These get converted into SQL `INSERT` statements against a
`legacy_rehearsal` staging schema — the same shape as the dry-run's
`legacy_dryrun` schema (`scripts/dry-run/00_seed_legacy_synthetic.sql`),
just populated from the real (anonymized) export instead of synthetic
generation. No new staging schema design — reusing the dry-run's exact
table shapes is the point (§3 of your instructions: don't build a second
implementation).

## 4. Anonymization — applied inline in the export SELECT, per table

| Column | Treatment |
|---|---|
| `staff_profiles.name` | Replaced with `'Staff ' \|\| row_number() over (order by id)` in the query itself |
| `staff_profiles` email (via `auth.users.email` for that `auth_user_id`) | Replaced with a synthetic address preserving only the pattern needed for the test (`admin@...` shape for admin, `...@staff.local` shape for operatore) — real address never selected |
| `stays.guest_last_name` | Replaced with a fixed placeholder surname (e.g. `'Rehearsal'`) |
| `stays.guest_pin` | **Not exported at all** — the column has a default generator; the rehearsal target gets a fresh one, same as any new stay |
| `guest_requests.note` | **Not exported at all** (excluded, see §5) — free text a guest wrote, unstructured PII risk, not needed to validate the mechanism |
| all `id` columns (hotels, staff_profiles, rooms, request_categories, request_types, stays, guest_requests) | **Preserved real** — these are structural, not personal, and preserving them is exactly what's under test (ID preservation, per the main plan §C) |
| timestamps (`created_at`, `check_in_at`, `check_out_at`, etc.) | **Preserved real** — needed to validate timezone/ordering behavior, not personal data |
| status/enum/department/role columns | **Preserved real** — needed to validate unexpected enum values (§2 of your instructions) |
| `pms_integrations.ohip_*` secret columns | Never read, regardless of row count |

## 5. Import order

Identical to the dry-run's validated sequence — no second implementation:
`hotels` → `organizations`/`properties`/`legacy_property_mapping` →
`property_modules` → Auth users (remapping) → `profiles`/`memberships` →
`staff_profiles` → `rooms`/`request_categories`/`request_types` →
`stays` (active only) → `guest_requests` (open only) → reconciliation →
application/E2E verification. Same `scripts/dry-run/10_migrate_hotel.sql`
logic, parameterized to read from `legacy_rehearsal.*` instead of
`legacy_dryrun.*`.

## 6. Auth users treatment

Same remapping strategy validated in the dry-run (no explicit id
dependency). Emails used for the 3 rehearsal Auth accounts are the
**anonymized** ones from §4, never the real legacy emails — creating
accounts with real email addresses on a disposable, non-production target
is an unnecessary real-world side effect (those addresses could receive
real mail from a misconfigured local stack) with no test value.

## 7. Secrets/password handling

No real password is ever recoverable from legacy (bcrypt hash, confirmed
non-exportable in the main plan's §B) — this was never in scope. Rehearsal
account passwords are freshly generated synthetic values, same as the
dry-run's. `pms_integrations` secret columns are never read (§1, §4) —
moot in any case since that table currently has 0 rows.

## 8. Intentionally excluded

- `guest_sessions`, `guest_login_attempts`, `push_subscriptions` — full
  tables, never read (main plan §A/§E).
- `guest_requests.note` — column excluded even for the 2 open rows that do
  get migrated (freetext risk, no test value).
- All historical/closed `stays` and non-open `guest_requests` — read
  during validation (to check their shape isn't anomalous) but not
  exported/imported, per the main plan's active/open-only strategy (§E).
- `pms_integrations.ohip_*` — never read regardless of whether rows exist.

## 9. Where exports are temporarily kept

The CSV files Studio produces exist only on your local machine until you
provide their (already-anonymized) content for the rehearsal — never
committed to the repository. To get them into the GitHub Actions runner
that executes the rehearsal (a remote machine, not your computer), the
path is: you provide the anonymized content, I write it to this session's
own local scratchpad (outside any git working tree, never committed),
package it as a GitHub Actions **workflow artifact** (upload only,
auto-expiring, not part of git history — distinct from a commit) for the
rehearsal job to download and import. At no point does raw/non-anonymized
data touch the repository, a persistent artifact, or a CI log.

## 10. Destruction procedure after the rehearsal

1. Delete the GitHub Actions artifact explicitly (not just let it expire) —
   verified via the Actions API, not assumed.
2. Delete the local scratchpad copy in this session.
3. The disposable target itself needs no separate cleanup — same as the
   dry-run, it's a Docker stack inside the runner, destroyed automatically
   when the job ends.
4. Ask you to delete the CSV files Studio downloaded to your own machine,
   once you've confirmed the rehearsal is done and nothing else is needed
   from them.
5. Confirmation of all four steps goes into the final rehearsal report,
   not assumed silently done.

---

## Next real step: validation queries (read-only, run before any export)

Per instruction 2 — checking whether legacy actually matches the fixture
shape, not assuming it does. All read-only, return only counts/flags, no
raw personal data in the result sets (safe to paste back here). Run on the
**legacy** project:

```sql
-- unexpected NULLs on columns the schema marks not null in practice
select 'staff_profiles.name' as check_name, count(*) from staff_profiles where name is null or trim(name) = ''
union all select 'staff_profiles.auth_user_id', count(*) from staff_profiles where auth_user_id is null
union all select 'rooms.room_number', count(*) from rooms where room_number is null or trim(room_number) = ''
union all select 'stays.guest_last_name', count(*) from stays where guest_last_name is null or trim(guest_last_name) = ''
union all select 'guest_requests.request_type_id', count(*) from guest_requests where request_type_id is null;

-- duplicates where uniqueness is expected
select 'staff_profiles.auth_user_id' as check_name, count(*) - count(distinct auth_user_id) as dupes from staff_profiles
union all select 'staff_profiles.login_username (non-null only)', count(login_username) - count(distinct login_username) from staff_profiles
union all select 'rooms (hotel_id, room_number)', count(*) - count(distinct (hotel_id, room_number)) from rooms;

-- duplicate emails on auth.users for these 3 staff specifically
select au.email, count(*) from staff_profiles sp
  join auth.users au on au.id = sp.auth_user_id
  group by au.email having count(*) > 1;

-- orphaned FKs
select 'stays_missing_room' as check_name, count(*) from stays s where not exists (select 1 from rooms r where r.id = s.room_id)
union all select 'requests_missing_type', count(*) from guest_requests gr where not exists (select 1 from request_types rt where rt.id = gr.request_type_id)
union all select 'requests_missing_stay_when_set', count(*) from guest_requests gr where gr.stay_id is not null and not exists (select 1 from stays s where s.id = gr.stay_id)
union all select 'types_missing_category', count(*) from request_types rt where not exists (select 1 from request_categories rc where rc.id = rt.category_id);

-- unexpected enum values (compares actual distinct values against the documented set)
select distinct role from staff_profiles where role not in ('admin','operatore','master');
select distinct department from staff_profiles where department is not null and department not in ('housekeeping','reception','maintenance','porter');
select distinct status from stays where status not in ('active','closed','cancelled');
select distinct status from guest_requests where status not in ('requested','in_progress','completed','cancelled');
select distinct assigned_department from guest_requests where assigned_department not in ('housekeeping','reception','maintenance','porter');

-- inactive staff, for awareness (not an anomaly by itself, but must be known before import)
select count(*) as inactive_staff from staff_profiles where not active;

-- timestamp sanity: any stay where checkout is not after checkin (should be impossible, there's a check constraint -- but confirm nothing bypassed it)
select count(*) as bad_stay_range from stays where check_out_at <= check_in_at;

-- stays without any relationship a migrated stay would need (a room that doesn't belong to this hotel)
select count(*) as stay_room_hotel_mismatch from stays s join rooms r on r.id = s.room_id where r.hotel_id <> s.hotel_id;

-- guest_requests in a status outside the ones the app's own request_status enum defines (schema-level check, not just app logic)
select distinct gr.status from guest_requests gr
  where gr.status::text not in (select enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'request_status');
```

**If any of these return non-zero/unexpected rows: stop, do not
normalize silently, report exactly what was found here so we can decide
the right transformation together** — per instruction 2.

Run these first and paste me the results (they contain only counts and
enum labels, no personal data) — I'll confirm whether legacy matches the
documented shape before we design the anonymized export queries in detail.

---

# Rehearsal Results

**Source used:** legacy Housekeeping project, hotel id
`25b00bec-1602-46e9-bf52-a4913ebb5bdb` ("Palazzo Veneziano"). Read entirely
by the user directly in Studio; every value the export queries returned
was already anonymized inline (no real name/email/PIN ever left legacy).

**Target used:** disposable local Supabase stack inside a GitHub Actions
runner (`ubuntu-latest`), destroyed when the job ended. Never the real
legacy or Hotsflow projects.

**Schema/version/commit:** hotsflow-core `main` @ `2347f68` (migrations
through `20260827122700`). Scripts: `scripts/dry-run/00_seed_legacy_synthetic.sql`
(dry-run only), `01_seed_legacy_rehearsal.sql` (real, anonymized — never
committed), `10_migrate_hotel.sql`, `20_reconciliation.sql`,
`orchestrate_rehearsal.sh`, `lib.sh`. Same `10_migrate_hotel.sql`/
`20_reconciliation.sql` the dry-run used — no second implementation.

**Legacy anomalies found (§2 validation, run before any export):** none.
NULLs, duplicates, orphaned FKs, unexpected enum values, timestamp
sanity, hotel/room consistency — all 0/clean across every check. One
finding that isn't an "anomaly" but changed the migration script: a
`master`-role staff member exists among the 3 real staff (the dry-run's
synthetic data only had admin/operatore) — `10_migrate_hotel.sql` was
extended with a master → `organization_admin` membership branch before
this rehearsal ran, and the reconciliation script gained a dedicated
check for it.

**Transformations applied:** per docs §4 — `staff_profiles.name`,
`login_username`, and email replaced inline in the export query;
`stays.guest_last_name` replaced with a fixed placeholder; `guest_pin` and
`guest_requests.note` never read at all. Every id, timestamp, role/
department/status/enum value, room number, and category/type name
preserved real (structural, not personal).

**Row reconciliation — legacy total / migrated / intentionally excluded / unexpected loss:**

| Table | legacy total | migrated | intentionally excluded | unexpected loss |
|---|---|---|---|---|
| hotels | 1 | 1 | 0 | 0 |
| staff_profiles | 3 | 3 | 0 | 0 |
| rooms | 7 | 7 | 0 | 0 |
| request_categories | 6 | 6 | 0 | 0 |
| request_types | 12 | 12 | 0 | 0 |
| stays | 4 (1 active) | 1 | 3 (historical) | 0 |
| guest_requests | 25 (2 open) | 2 | 23 (historical) | 0 |
| guest_sessions | 16 | 0 | 16 (never migrated, by design) | 0 |
| guest_login_attempts | 18 | 0 | 18 (never migrated, by design) | 0 |
| push_subscriptions | 3 | 0 | 3 (moot — VAPID rotated) | 0 |
| pms_integrations | 0 | 0 | 0 | 0 |

PK preservation: 0 duplicates (staff_profiles, stays, guest_requests). FK
integrity: 0 orphans (stays→room, requests→type, requests→stay). Hotel→
property mapping: exactly 1 row, correct organization. Entitlement:
`guest_requests` enabled=true for the real property. Active/suspended
consistency: legacy_active=3, core_active=3 (equal).

**Auth reconciliation:**

| | count |
|---|---|
| legacy staff eligible | 3 |
| Auth users created (remapping, no explicit id) | 3 (+1 for the synthetic "Hotel X" cross-property fixture) |
| legacy_id → new_id mappings | 3 |
| profiles created | 3 |
| memberships created | 3 (2 property-scoped for admin/operatore-equivalent roles, 1 organization-scoped for the master role) |
| staff_profiles migrated with correct auth_user_id | 3/3 |
| login (real password grant) | 3/3 succeeded |
| suspended/inactive staff | 0 among the 3 (none to test — real roster is 100% active) |

**E2E results (real REST/RPC network calls against the disposable target, not raw SQL):**
```
login master                          PASS
login operatore (reception)           PASS
login operatore (housekeeping)        PASS
roster (master sees all 3 staff)      PASS
guest request queue (housekeeping)    PASS (2 visible, matches migrated count)
status change (real PATCH via REST)   PASS (204)
entitlement + PMS permission path     PASS (master has guest_requests.pms.manage)
cross-property denial                 PASS (master denied on a separate synthetic org)
```
**Coverage gap, reported not hidden:** department-isolation could only be
tested positively (housekeeping operatore correctly sees the 2
housekeeping-assigned open requests) — real data has no open request
assigned to a different department, so the negative case ("an operatore
must NOT see another department's request") isn't exercisable with real
data alone. Not a failure; a limit of this dataset's shape.

**Rollback/idempotency results:**
```
idempotent full rerun                 PASS (no duplicate Auth user, guest_requests still =2)
mid-Auth failure injection            PASS (0 orphaned rows, SQL phase correctly never ran)
post-Auth SQL failure + rollback      PASS (transaction rolled back to 0 rows, orphaned Auth user cleaned up)
```
Both failure injections used entirely synthetic, throwaway accounts/hotels
— per instruction, never risked real source data to simulate a failure.

**Timing (ms, single run, local disposable stack — not representative of
network latency to the real hosted projects):**

| Phase | ms |
|---|---|
| export/seed | 480 |
| Hotel X fixture seed | 44 |
| Auth migration (3 real + 1 fixture user) | 679 |
| SQL import | 112 |
| reconciliation | 50 |
| E2E (8 real network calls) | 496 |
| idempotent rerun | 181 |
| mid-Auth failure injection | 254 |
| post-Auth SQL failure + rollback | 281 |
| **total** | **2597** |

At this data volume the actual migration work is trivial (under 3
seconds); real production cutover timing will be dominated by the
maintenance-window process (announcement, freeze, verification, DNS/env
propagation — plan §H), not by the migration script itself.

**Temporary artifacts created and destruction confirmed:**
- `scripts/dry-run/01_seed_legacy_rehearsal.sql` (real anonymized seed):
  never committed (confirmed — `.gitignore`'d, absent from every commit in
  this repo's history); existed transiently on the runner's disk, removed
  by an explicit `rm -f` step (confirmed in the job log) and again when
  the runner itself was destroyed at job end.
- Workflow_dispatch input carrying the base64-encoded anonymized seed:
  not written into any step's log line (consumed via `env:`, not direct
  interpolation) — the one residual exposure is that GitHub's own "run
  inputs" metadata panel for this dispatch retains the value, a
  limitation of the available channel (no secrets-management tool was
  available to this session), not of the design; the data itself is
  already anonymized, not raw legacy content.
- Local scratchpad copies (base64 intermediate files) on this session's
  own disk: deleted.
- Disposable Supabase stack + everything created on it: destroyed
  automatically when the GitHub Actions runner terminated.

**Differences between this rehearsal and the future production execution:**
1. This rehearsal's target was a disposable local stack, not the real
   Hotsflow project — production execution talks to the real hosted
   database over the network, with real latency and real connection
   limits neither exercised here.
2. The Auth-creation step here used GoTrue running inside the local
   stack; production talks to the real hosted project's GoTrue instance —
   same API, different network path and possibly different response
   timing.
3. The `master`-role handling (added specifically because this rehearsal
   found it) has now been exercised end-to-end for the first time — no
   longer an unknown, but this is its first and only real run so far.
4. Department-isolation's negative case remains unverified (see the E2E
   coverage-gap note above) — real production data doesn't currently
   exercise it either, so this gap carries forward, not something the
   rehearsal introduced.
5. Timing here (2.6s total) reflects a tiny dataset on zero-latency
   localhost; it is not a projection for a maintenance-window duration —
   see plan §H for that runbook, informed by but not equal to this number.

**Residual technical risks:**
- HIGH (unchanged from the main plan, not resolved by this rehearsal):
  rollback after real writes land on the new backend post-cutover is
  still a manual judgment call (plan §I.3) — this rehearsal validated the
  *pre-cutover* rollback paths (mid-Auth, post-Auth-SQL), not that one,
  which by its nature can't be rehearsed against synthetic data.
- MEDIUM: department-isolation negative case unverified (see above).
- MEDIUM: the workflow_dispatch input channel used to move anonymized
  data onto the runner has a residual metadata-visibility limitation (see
  "Temporary artifacts" above) — acceptable for anonymized data, would
  need a different mechanism (e.g. a proper secrets API) if ever reused
  for less-anonymized content.
- LOW: `pms_integrations` had 0 rows to migrate — the presence-only
  verification path (plan §G) remains logically sound but has never
  actually run against a non-empty row.

**Runbook changes needed:** none to the migration script itself — it ran
correctly on the first successful attempt against real data (after the
master-role extension made before this run). Two operational notes for
the real cutover runbook (plan §L), not code changes:
1. Confirm no suspended/inactive staff exist among the real 3 before
   cutover (already known: 0), so the "suspended staff" reconciliation
   check has a real assertion to make on the day, not just an equality
   that happens to hold vacuously.
2. Budget the maintenance window around process/verification time, not
   migration execution time — the script itself is sub-3-second at this
   data volume.

## PRODUCTION DATA MIGRATION REHEARSAL: GO

For preparing the production cutover — **not for executing it.** All
requested checks passed, using real (anonymized) data through the actual
migration mechanism, including both failure/rollback paths. No cutover
has been performed. Awaiting explicit approval before any further step.
