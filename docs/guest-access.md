# Guest access

## The principle

A module should be able to ask "is there a valid guest session for this
property, at this level?" without knowing *how* the guest was verified.
`guest_sessions` is the one thing every current and future verification
method agrees on; the method itself is never implemented here.

## What's in Phase 1

The table, RLS locked all the way down (no policy at all — see `rls.md`),
and one function: `guest_session_is_valid(session_id, property_id,
min_level)`. That's it. No `room + surname`, no `booking reference +
surname`, no QR, no secure link, no PMS-derived verification, and no
function that *creates* a session — those are all module-specific and
arrive with whichever module needs them first (per the migration order,
that's `guest_requests` in Phase 2).

## verification_level: a rank, not an enum

```
10 = low     (e.g. request towels)
20 = medium  (e.g. request/modify a service)
30 = high    (e.g. modify a paid transfer)
```

Stored as `smallint` with `check (verification_level > 0)`, not a Postgres
enum and not a lookup table. The gaps between 10/20/30 are intentional —
inserting an intermediate level later (say 15) is a data change, not a
migration. A module compares with `>=`:
`guest_session_is_valid(id, propertyId, 20)` accepts anything at MEDIUM or
above.

Import the named constants instead of the raw numbers:

```ts
import { GUEST_VERIFICATION_LEVEL } from '@hotsflow/core-sdk'

guest_session_is_valid(sessionId, propertyId, GUEST_VERIFICATION_LEVEL.MEDIUM)
```

## Method-agnostic, without redesigning the table later

`token_hash` is `not null` today because it's the only lookup mechanism
Phase 1 has any use for — every real guest session in the near term will be
created the same way `guest_requests` already does it (a hashed opaque
token, checked on every request). If a future method needs a different
lookup — say, Supabase anonymous auth with a claim carrying the session id —
that's an **additive** `ALTER TABLE guest_sessions ADD COLUMN auth_user_id
uuid` plus making `token_hash` nullable at that point. Not a redesign: the
validity columns (`expires_at`, `revoked_at`, `verification_level`,
`property_id`) don't change, and `guest_session_is_valid()`'s signature
doesn't either.

`reservation_id`, `room_id`, and `guest_id` are opaque `text`, not foreign
keys — the core doesn't own a reservation/room/PMS model (out of scope, see
the Architecture Proposal). Whichever module creates a session is
responsible for whatever those values mean; `issued_by_module_id` records
which module that was, mostly for debugging.

## How a guest-facing module adds its own verification method

None of this is implemented yet — this is the shape it will take, based on
`guest_requests`' own already-proven pattern (see the three-module audit):

1. Write a `SECURITY DEFINER` Postgres function (or an Edge Function) that
   takes whatever the method needs (room number + surname, a booking
   reference, a QR payload...), verifies it against the module's *own*
   tables, and on success generates a token, hashes it, and inserts a
   `guest_sessions` row — `verification_method` records which method this
   was, in plain text (no core migration needed to add a new one).
2. Grant `execute` on that function to `anon` — and only that function.
   `guest_sessions` itself stays with zero `anon` grants, same as it is
   today.
3. Every subsequent guest request calls `guest_session_is_valid()` (directly
   or through another module-owned `SECURITY DEFINER` function) before doing
   anything — re-checked live, every time, not just once at issuance. A
   revoked or expired session stops working immediately.
4. An action with real stakes (cancelling a paid transfer, say) re-validates
   `verification_level` explicitly inside its own function rather than
   trusting that the caller already checked — defense in depth, matching the
   Architecture Proposal's guidance on high-risk guest actions.
