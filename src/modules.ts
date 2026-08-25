import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { ModuleEntitlement } from './types/domain'

interface PropertyModuleWithModule {
  enabled: boolean
  modules: {
    id: string
    slug: string
    display_name: string
  } | null
}

// Only enabled modules — this answers "what should this property see at
// all?", not "what exists on the platform". A module that's registered but
// switched off for this property is simply absent from the result, same as
// property_modules.enabled = false is meant to behave everywhere else.
export async function getEnabledModules(client: SupabaseClient<Database>, propertyId: string): Promise<ModuleEntitlement[]> {
  const { data, error } = await client
    .from('property_modules')
    .select('enabled, modules(id, slug, display_name)')
    .eq('property_id', propertyId)
    .eq('enabled', true)
    .returns<PropertyModuleWithModule[]>()
  if (error) throw error

  return (data ?? [])
    .filter((row): row is PropertyModuleWithModule & { modules: NonNullable<PropertyModuleWithModule['modules']> } => row.modules !== null)
    .map((row) => ({
      moduleId: row.modules.id,
      slug: row.modules.slug,
      displayName: row.modules.display_name,
      enabled: row.enabled,
    }))
}
