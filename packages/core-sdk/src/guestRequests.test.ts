import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getGuestRequestsLegacyHotelId, getGuestRequestsSlugForProperty } from './guestRequests'

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

describe('getGuestRequestsSlugForProperty', () => {
  it('returns the mapped hotel\'s guest slug', async () => {
    const client = {
      rpc: async () => ({ data: 'palazzo-veneziano', error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getGuestRequestsSlugForProperty(client, 'property-1')).resolves.toBe('palazzo-veneziano')
  })

  it('returns null when the resolver fails closed', async () => {
    const client = {
      rpc: async () => ({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getGuestRequestsSlugForProperty(client, 'property-1')).resolves.toBeNull()
  })
})
