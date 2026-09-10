import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { CoreRole, CreateTeamMemberWithCredentialsInput, CreateTeamMemberWithCredentialsResult, InviteTeamMemberInput, JobTitle, Membership, ModuleEntitlement, Profile, Property, ResetTeamMemberPasswordInput, TeamMember, UpdateTeamMemberInput } from './types/domain'
import { getCurrentProfile, updateCurrentProfile } from './profile'
import { getAccessibleProperties, getMembership, updateProperty } from './memberships'
import { hasPermission } from './permissions'
import { getEnabledModules } from './modules'
import { getGuestRequestsLegacyHotelId } from './guestRequests'
import { createJobTitle, createTeamMemberWithCredentials, getJobTitles, getPropertyRoles, getTeamMembers, inviteTeamMember, resetTeamMemberPassword, updateJobTitle, updateTeamMember } from './team'

export interface CoreClient {
  // Escape hatch for a module that needs the raw Supabase client (e.g. to
  // query its own tables) — the Core SDK deliberately doesn't wrap or proxy
  // module data, only identity/tenant/permission/entitlement concerns.
  raw: SupabaseClient<Database>
  getCurrentProfile: () => Promise<Profile | null>
  getAccessibleProperties: () => Promise<Property[]>
  getMembership: (propertyId: string) => Promise<Membership | null>
  hasPermission: (propertyId: string, permissionSlug: string) => Promise<boolean>
  getEnabledModules: (propertyId: string) => Promise<ModuleEntitlement[]>
  getGuestRequestsLegacyHotelId: (propertyId: string) => Promise<string | null>
  getTeamMembers: (propertyId: string) => Promise<TeamMember[]>
  getPropertyRoles: () => Promise<CoreRole[]>
  getJobTitles: (propertyId: string) => Promise<JobTitle[]>
  createJobTitle: (propertyId: string, name: string) => Promise<JobTitle>
  updateJobTitle: (id: string, changes: { name?: string; active?: boolean }) => Promise<void>
  inviteTeamMember: (input: InviteTeamMemberInput) => Promise<void>
  createTeamMemberWithCredentials: (input: CreateTeamMemberWithCredentialsInput) => Promise<CreateTeamMemberWithCredentialsResult>
  resetTeamMemberPassword: (input: ResetTeamMemberPasswordInput) => Promise<void>
  updateTeamMember: (input: UpdateTeamMemberInput) => Promise<void>
  updateCurrentProfile: (changes: { fullName: string; avatarUrl?: string | null }) => Promise<Profile>
  updateProperty: (propertyId: string, changes: { name: string; timezone: string }) => Promise<Property>
}

export function createCoreClient(supabaseUrl: string, supabaseAnonKey: string): CoreClient {
  const raw = createClient<Database>(supabaseUrl, supabaseAnonKey)
  return {
    raw,
    getCurrentProfile: () => getCurrentProfile(raw),
    getAccessibleProperties: () => getAccessibleProperties(raw),
    getMembership: (propertyId) => getMembership(raw, propertyId),
    hasPermission: (propertyId, permissionSlug) => hasPermission(raw, propertyId, permissionSlug),
    getEnabledModules: (propertyId) => getEnabledModules(raw, propertyId),
    getGuestRequestsLegacyHotelId: (propertyId) => getGuestRequestsLegacyHotelId(raw, propertyId),
    getTeamMembers: (propertyId) => getTeamMembers(raw, propertyId),
    getPropertyRoles: () => getPropertyRoles(raw),
    getJobTitles: (propertyId) => getJobTitles(raw, propertyId),
    createJobTitle: (propertyId, name) => createJobTitle(raw, propertyId, name),
    updateJobTitle: (id, changes) => updateJobTitle(raw, id, changes),
    inviteTeamMember: (input) => inviteTeamMember(raw, input),
    createTeamMemberWithCredentials: (input) => createTeamMemberWithCredentials(raw, input),
    resetTeamMemberPassword: (input) => resetTeamMemberPassword(raw, input),
    updateTeamMember: (input) => updateTeamMember(raw, input),
    updateCurrentProfile: (changes) => updateCurrentProfile(raw, changes),
    updateProperty: (propertyId, changes) => updateProperty(raw, propertyId, changes),
  }
}
