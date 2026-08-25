import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { Membership, ModuleEntitlement, Profile, Property } from './types/domain'
import { getCurrentProfile } from './profile'
import { getAccessibleProperties, getMembership } from './memberships'
import { hasPermission } from './permissions'
import { getEnabledModules } from './modules'

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
  }
}
