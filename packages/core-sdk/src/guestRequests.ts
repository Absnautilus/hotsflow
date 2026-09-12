import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'

export async function getGuestRequestsLegacyHotelId(
  client: SupabaseClient<Database>,
  propertyId: string,
): Promise<string | null> {
  // Database is still a hand-maintained pre-Fase-2 type map; keep this one
  // newly-added RPC narrowly typed here until database.ts is regenerated.
  // Call rpc through the Supabase client object so its internal `this` binding
  // is preserved. Extracting client.rpc into a standalone function causes
  // SupabaseClient.rpc() to lose access to its internal `rest` client.
  const { data, error } = await client.rpc(
    'guest_requests_legacy_hotel_for_property' as never,
    { p_property_id: propertyId } as never,
  ) as { data: string | null; error: Error | null }

  if (error) throw error
  return data ?? null
}

export async function getGuestRequestsSlugForProperty(
  client: SupabaseClient<Database>,
  propertyId: string,
): Promise<string | null> {
  // Same reasoning as getGuestRequestsLegacyHotelId above re: narrow typing
  // and calling rpc through the client object directly.
  const { data, error } = await client.rpc(
    'guest_requests_slug_for_property' as never,
    { p_property_id: propertyId } as never,
  ) as { data: string | null; error: Error | null }

  if (error) throw error
  return data ?? null
}
