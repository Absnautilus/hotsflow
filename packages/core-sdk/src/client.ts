import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { ArchiveTeamMemberInput, CoreRole, CreateTeamMemberWithCredentialsInput, CreateTeamMemberWithCredentialsResult, GrantHousekeepingAccessInput, InviteTeamMemberInput, JobTitle, Membership, ModuleEntitlement, Profile, Property, ResetTeamMemberPasswordInput, RevokeHousekeepingAccessInput, TeamMember, UpdateTeamMemberInput } from './types/domain'
import { getCurrentProfile, updateCurrentProfile } from './profile'
import { deleteDevicePushSubscription, isDevicePushSubscribed, saveDevicePushSubscription, type DevicePushSubscriptionKeys } from './devicePush'
import { getAccessibleProperties, getMembership, updateProperty } from './memberships'
import { hasPermission } from './permissions'
import { getEnabledModules } from './modules'
import { getGuestRequestsLegacyHotelId, getGuestRequestsSlugForProperty } from './guestRequests'
import { archiveTeamMember, createJobTitle, createTeamMemberWithCredentials, getHousekeepingAccessStatus, getJobTitles, getPropertyRoles, getTeamMembers, grantHousekeepingAccess, inviteTeamMember, resetTeamMemberPassword, revokeHousekeepingAccess, updateJobTitle, updateTeamMember } from './team'

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
  getGuestRequestsSlugForProperty: (propertyId: string) => Promise<string | null>
  getTeamMembers: (propertyId: string) => Promise<TeamMember[]>
  getPropertyRoles: () => Promise<CoreRole[]>
  getJobTitles: (propertyId: string) => Promise<JobTitle[]>
  createJobTitle: (propertyId: string, name: string) => Promise<JobTitle>
  updateJobTitle: (id: string, changes: { name?: string; active?: boolean }) => Promise<void>
  inviteTeamMember: (input: InviteTeamMemberInput) => Promise<void>
  createTeamMemberWithCredentials: (input: CreateTeamMemberWithCredentialsInput) => Promise<CreateTeamMemberWithCredentialsResult>
  resetTeamMemberPassword: (input: ResetTeamMemberPasswordInput) => Promise<void>
  grantHousekeepingAccess: (input: GrantHousekeepingAccessInput) => Promise<void>
  revokeHousekeepingAccess: (input: RevokeHousekeepingAccessInput) => Promise<void>
  getHousekeepingAccessStatus: (membershipId: string) => Promise<boolean>
  updateTeamMember: (input: UpdateTeamMemberInput) => Promise<void>
  archiveTeamMember: (input: ArchiveTeamMemberInput) => Promise<void>
  updateCurrentProfile: (changes: { fullName: string; avatarUrl?: string | null }) => Promise<Profile>
  updateProperty: (propertyId: string, changes: { name: string; timezone: string; settings?: Record<string, unknown> }) => Promise<Property>
  saveDevicePushSubscription: (keys: DevicePushSubscriptionKeys) => Promise<void>
  deleteDevicePushSubscription: (endpoint: string) => Promise<void>
  isDevicePushSubscribed: (endpoint: string) => Promise<boolean>
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
    getGuestRequestsSlugForProperty: (propertyId) => getGuestRequestsSlugForProperty(raw, propertyId),
    getTeamMembers: (propertyId) => getTeamMembers(raw, propertyId),
    getPropertyRoles: () => getPropertyRoles(raw),
    getJobTitles: (propertyId) => getJobTitles(raw, propertyId),
    createJobTitle: (propertyId, name) => createJobTitle(raw, propertyId, name),
    updateJobTitle: (id, changes) => updateJobTitle(raw, id, changes),
    inviteTeamMember: (input) => inviteTeamMember(raw, input),
    createTeamMemberWithCredentials: (input) => createTeamMemberWithCredentials(raw, input),
    resetTeamMemberPassword: (input) => resetTeamMemberPassword(raw, input),
    grantHousekeepingAccess: (input) => grantHousekeepingAccess(raw, input),
    revokeHousekeepingAccess: (input) => revokeHousekeepingAccess(raw, input),
    getHousekeepingAccessStatus: (membershipId) => getHousekeepingAccessStatus(raw, membershipId),
    updateTeamMember: (input) => updateTeamMember(raw, input),
    archiveTeamMember: (input) => archiveTeamMember(raw, input),
    updateCurrentProfile: (changes) => updateCurrentProfile(raw, changes),
    updateProperty: (propertyId, changes) => updateProperty(raw, propertyId, changes),
    saveDevicePushSubscription: (keys) => saveDevicePushSubscription(raw, keys),
    deleteDevicePushSubscription: (endpoint) => deleteDevicePushSubscription(raw, endpoint),
    isDevicePushSubscribed: (endpoint) => isDevicePushSubscribed(raw, endpoint),
  }
}
