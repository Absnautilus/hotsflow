// Application-facing types. Everything the SDK returns is one of these, never
// a raw Database['public']['Tables'][...]['Row'] — see database.ts's header
// for why. Field names are camelCase here on purpose, to make "this is a
// mapped domain type, not a DB row" visible at a glance.

export type MembershipStatus = 'invited' | 'active' | 'suspended'
export type PropertyStatus = 'active' | 'suspended'
export type ModuleStatus = 'active' | 'beta' | 'deprecated'
export type RoleScope = 'organization' | 'property'

export interface Organization {
  id: string
  name: string
  slug: string
}

export interface Property {
  id: string
  organizationId: string
  name: string
  slug: string
  timezone: string
  status: PropertyStatus
  settings: Record<string, unknown>
}

export interface Profile {
  id: string
  fullName: string
  avatarUrl: string | null
}

export interface CoreRole {
  id: string
  slug: string
  displayName: string
  scope: RoleScope
  rank: number
}

export interface JobTitle {
  id: string
  propertyId: string
  name: string
  active: boolean
}

export type EmploymentStatus = 'active' | 'inactive'

export interface TeamMember {
  profile: Profile
  membership: Membership
  role: CoreRole
  jobTitle: JobTitle | null
  employmentStatus: EmploymentStatus
}

export interface InviteTeamMemberInput {
  propertyId: string
  fullName: string
  email: string
  roleId: string
  jobTitleId?: string | null
}

// The credentials alternative to InviteTeamMemberInput -- no email, no
// invite mail sent. username is scoped unique per property (see
// memberships_property_username_unique); the account's real auth.users
// email is a synthetic, globally-unique value the Edge Function derives
// from username + property + organization, invisible to both the admin
// and the staff member (who log in with plain username + password).
export interface CreateTeamMemberWithCredentialsInput {
  propertyId: string
  fullName: string
  username: string
  password: string
  roleId: string
  jobTitleId?: string | null
}

// loginIdentifier is the synthesized auth.users email -- opaque to the
// caller, shown once so the admin can hand it to the new team member
// alongside the password they just chose (same "shown once" pattern as a
// guest stay's PIN).
export interface CreateTeamMemberWithCredentialsResult {
  profileId: string
  membershipId: string
  loginIdentifier: string
}

export interface ResetTeamMemberPasswordInput {
  membershipId: string
  newPassword: string
}

export interface RemoveTeamMemberInput {
  membershipId: string
}

export interface UpdateTeamMemberInput {
  membershipId: string
  profileId: string
  propertyId: string
  roleId?: string
  membershipStatus?: MembershipStatus
  jobTitleId?: string | null
  employmentStatus?: EmploymentStatus
}

export interface Membership {
  id: string
  profileId: string
  // Exactly one of these two is set — mirrors the database's own
  // memberships_exactly_one_scope check. propertyId set = a single-property
  // grant; organizationId set = an org-wide grant covering every property
  // under it.
  propertyId: string | null
  organizationId: string | null
  roleId: string
  status: MembershipStatus
  // Set only for a credentials-based (no email) account -- null for every
  // membership created via the email-invite flow.
  username: string | null
}

// Deliberately a plain string, not a union of literal slugs: a new module
// shouldn't require a Core SDK release to be recognized. The `modules`
// table is the source of truth for which slugs exist — see
// docs/module-integration.md (Step 5).
export type ModuleSlug = string

export interface ModuleEntitlement {
  moduleId: string
  slug: ModuleSlug
  displayName: string
  enabled: boolean
}

// What a module declares about itself. A compile-time contract only — see
// src/moduleContract.ts. The `modules` table row is the actual runtime
// registration; this type has no connection to it beyond convention.
export interface ModuleDescriptor {
  slug: ModuleSlug
  displayName: string
  requiredPermissions: string[]
}
