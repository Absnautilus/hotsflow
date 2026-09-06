import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'

type LegacyHotelMappingRpc = (
  fn: 'guest_requests_legacy_hotel_for_property',
  args: { p_property_id: string },
) => Promise<{
  data: string | null
  error: Error | null
}>

export async function getGuestRequestsLegacyHotelId(
  client: SupabaseClient<Database>,
  propertyId: string,
): Promise<string | null> {
  // Database is still a hand-maintained pre-Fase-2 type map; keep this one
  // newly-added RPC narrowly typed here until database.ts is regenerated.
  const rpc = client.rpc as unknown as LegacyHotelMappingRpc
  const { data, error } = await rpc('guest_requests_legacy_hotel_for_property', {
    p_property_id: propertyId,
  })
  if (error) throw error
  return data ?? null
}
