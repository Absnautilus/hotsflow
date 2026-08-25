import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { hasPermission } from './permissions'

describe('hasPermission', () => {
  it('calls the has_permission RPC with the given property and permission slug', async () => {
    let calledWith: unknown
    const client = {
      rpc: async (name: string, args: unknown) => {
        calledWith = { name, args }
        return { data: true, error: null }
      },
    } as unknown as SupabaseClient<Database>

    await expect(hasPermission(client, 'property-1', 'core.property.manage')).resolves.toBe(true)
    expect(calledWith).toEqual({
      name: 'has_permission',
      args: { p_property_id: 'property-1', p_permission_slug: 'core.property.manage' },
    })
  })

  it('returns false when the RPC returns false', async () => {
    const client = {
      rpc: async () => ({ data: false, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(hasPermission(client, 'property-1', 'core.property.manage')).resolves.toBe(false)
  })

  it('throws when the RPC errors, rather than silently treating it as false', async () => {
    const client = {
      rpc: async () => ({ data: null, error: { message: 'boom' } }),
    } as unknown as SupabaseClient<Database>

    await expect(hasPermission(client, 'property-1', 'core.property.manage')).rejects.toBeTruthy()
  })
})
