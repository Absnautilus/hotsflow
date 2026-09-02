# Production Migration Rehearsal — plan (pre-execution documentation)

Status: **NOT STARTED.** Nothing in this document has been executed. No
real legacy data has been read, exported, or transferred anywhere. This is
the documentation required before any real-data step runs, per explicit
instruction.

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
