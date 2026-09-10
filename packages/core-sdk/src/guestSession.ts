// No verification flow lives here yet (see migration 0005's header and the
// Architecture Proposal's decision to keep Guest Auth open) — this is just
// the one thing every future method needs to agree on: what a level *means*.
// Ranks, not a fixed enum, with gaps left on purpose so an intermediate
// level (e.g. 15) can be introduced later without a migration. A module
// compares with >=, e.g. requiring at least MEDIUM for an action.
export const GUEST_VERIFICATION_LEVEL = {
  LOW: 10,
  MEDIUM: 20,
  HIGH: 30,
} as const

export type GuestVerificationLevel = number
