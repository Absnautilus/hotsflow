-- Guest access — one concept (guest_sessions) covering every verification
-- method, present or future. A module asks "is there a valid guest session
-- for this property, at this level?" without knowing how the guest proved
-- who they are. The validity check itself is a Step 3 concern (migration
-- 0006's guest_session_is_valid); this migration only lays the table down.
--
-- No verification flow (room+surname, booking+surname, secure link, QR) is
-- implemented here — those belong to the module that migrates first and
-- actually needs one. See docs/guest-access.md (Step 5) for how a new
-- method plugs in later without touching this table's shape.

create table guest_sessions (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  -- Opaque references, deliberately not foreign keys: the core does not own
  -- a reservation/room/guest model (that's PMS territory, out of scope — see
  -- the Architecture Proposal). Whatever module creates the session is
  -- responsible for these meaning something.
  reservation_id text,
  room_id text,
  guest_id text,
  -- Free text, not an enum: new methods (QR, PMS-derived, ...) get added by
  -- whichever module needs them, without a core migration.
  verification_method text not null,
  -- Rank, not a fixed enum: 10/20/30 map to low/medium/high (see
  -- docs/guest-access.md, Step 5) with gaps left on purpose so an
  -- intermediate level can be inserted later (e.g. 15) without a migration
  -- or an ALTER TYPE. A module compares with >=, e.g. "this action needs at
  -- least 20".
  verification_level smallint not null check (verification_level > 0),
  -- The only lookup mechanism Phase 1 needs (matches the proven pattern
  -- already in guest_requests: never store the raw token, only its hash).
  -- Not null for now because no other lookup path exists yet; if an
  -- anonymous-auth-based method is added later, its own lookup column
  -- (e.g. auth_user_id) is an additive ALTER TABLE, and this column would
  -- become nullable at that point — not a redesign.
  token_hash text not null unique,
  -- Which module created this session — useful for debugging/audit even
  -- though the reading module doesn't need to care.
  issued_by_module_id uuid references modules(id) on delete set null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint guest_sessions_expires_after_created check (expires_at > created_at)
);

create index guest_sessions_property_idx on guest_sessions (property_id);
-- Supports a future cleanup sweep of expired sessions.
create index guest_sessions_expires_at_idx on guest_sessions (expires_at);

-- No updated_at trigger: last_seen_at and revoked_at are set explicitly by
-- whatever function touches them, not implied by "the row changed".
