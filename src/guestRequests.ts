import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'

export async function getGuestRequestsLegacyHotelId(
  client: SupabaseClient<Database>,
  propertyId: string,
): Promise<string | null> {
  const { data, error } = await client.rpc('guest_requests_legacy_hotel_for_property', {
    p_property_id: propertyId,
  })
  if (error) throw error
  return data ?? null
}
