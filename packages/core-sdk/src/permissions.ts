import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'

// Calls the exact same Postgres function RLS policies use (migration 0006)
// — the answer here and the answer the database enforces can never drift
// apart, because they're the same function. This is a convenience/UI check
// (e.g. "should I show this button?"), never the actual authorization
// boundary: that's always RLS on the real read/write, not this call.
export async function hasPermission(
  client: SupabaseClient<Database>,
  propertyId: string,
  permissionSlug: string,
): Promise<boolean> {
  const { data, error } = await client.rpc('has_permission', {
    p_property_id: propertyId,
    p_permission_slug: permissionSlug,
  })
  if (error) throw error
  return data ?? false
}
