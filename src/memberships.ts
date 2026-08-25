import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { Membership, Property } from './types/domain'

function mapPropertyRow(row: Database['public']['Tables']['properties']['Row']): Property {
  return {
    id: row.id,
    organizationId: row.organization_id,
    name: row.name,
    slug: row.slug,
    timezone: row.timezone,
    status: row.status as Property['status'],
    settings: (row.settings as Record<string, unknown>) ?? {},
  }
}

function mapMembershipRow(row: Database['public']['Tables']['memberships']['Row']): Membership {
  return {
    id: row.id,
    profileId: row.profile_id,
    propertyId: row.property_id,
    organizationId: row.organization_id,
    roleId: row.role_id,
    status: row.status as Membership['status'],
  }
}

// No property_id filter here: RLS (has_property_access) already returns
// exactly the rows this profile can see, whether via a direct membership or
// an org-wide one. The query doesn't need to know which.
export async function getAccessibleProperties(client: SupabaseClient<Database>): Promise<Property[]> {
  const { data, error } = await client.from('properties').select('*').order('name')
  if (error) throw error
  return (data ?? []).map(mapPropertyRow)
}

// Prefers a membership scoped directly to this property; falls back to an
// org-wide one covering it if no direct row exists. Mirrors has_property_access's
// own OR-branch (migration 0006) — this is for display ("what's my role
// here?"), has_permission/hasPermission is what actually gates anything.
export async function getMembership(client: SupabaseClient<Database>, propertyId: string): Promise<Membership | null> {
  const {
    data: { user },
  } = await client.auth.getUser()
  if (!user) return null

  const direct = await client
    .from('memberships')
    .select('*')
    .eq('profile_id', user.id)
    .eq('property_id', propertyId)
    .eq('status', 'active')
    .maybeSingle()
  if (direct.error) throw direct.error
  if (direct.data) return mapMembershipRow(direct.data)

  const property = await client.from('properties').select('organization_id').eq('id', propertyId).maybeSingle()
  if (property.error) throw property.error
  if (!property.data) return null

  const orgWide = await client
    .from('memberships')
    .select('*')
    .eq('profile_id', user.id)
    .eq('organization_id', property.data.organization_id)
    .eq('status', 'active')
    .maybeSingle()
  if (orgWide.error) throw orgWide.error
  return orgWide.data ? mapMembershipRow(orgWide.data) : null
}
