export { createCoreClient } from './client'
export type { CoreClient } from './client'

export type {
  Organization,
  Property,
  PropertyStatus,
  Profile,
  CoreRole,
  JobTitle,
  EmploymentStatus,
  TeamMember,
  InviteTeamMemberInput,
  UpdateTeamMemberInput,
  Membership,
  MembershipStatus,
  RoleScope,
  ModuleSlug,
  ModuleStatus,
  ModuleEntitlement,
  ModuleDescriptor,
} from './types/domain'

export { GUEST_VERIFICATION_LEVEL } from './guestSession'
export type { GuestVerificationLevel } from './guestSession'

export type { Database, Json } from './types/database'
