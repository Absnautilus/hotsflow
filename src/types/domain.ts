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
