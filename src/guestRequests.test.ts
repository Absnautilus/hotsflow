import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getGuestRequestsLegacyHotelId } from './guestRequests'

describe('getGuestRequestsLegacyHotelId', () => {
  it('returns the mapped legacy hotel id', async () => {
    const client = {
      rpc: async () => ({ data: 'hotel-1', error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getGuestRequestsLegacyHotelId(client, 'property-1')).resolves.toBe('hotel-1')
  })

  it('returns null when the resolver fails closed', async () => {
    const client = {
      rpc: async () => ({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getGuestRequestsLegacyHotelId(client, 'property-1')).resolves.toBeNull()
  })
})
