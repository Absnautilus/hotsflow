import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { deleteDevicePushSubscription, isDevicePushSubscribed, saveDevicePushSubscription } from './devicePush'
import { mockAuthenticatedUser, mockNoUser, mockQueryBuilder } from './testSupport'

describe('saveDevicePushSubscription', () => {
  it('throws when nobody is signed in, without querying the table', async () => {
    const client = {
      auth: { getUser: async () => mockNoUser() },
      from: () => {
        throw new Error('should not query device_push_subscriptions without a signed-in user')
      },
    } as unknown as SupabaseClient<Database>

    await expect(
      saveDevicePushSubscription(client, { endpoint: 'https://push.example/ep', p256dh: 'p', auth: 'a' }),
    ).rejects.toThrow('not_authenticated')
  })

  it('upserts the subscription for the signed-in user', async () => {
    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: () => mockQueryBuilder({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(
      saveDevicePushSubscription(client, { endpoint: 'https://push.example/ep', p256dh: 'p', auth: 'a' }),
    ).resolves.toBeUndefined()
  })
})

describe('deleteDevicePushSubscription', () => {
  it('deletes by endpoint', async () => {
    const client = {
      from: () => mockQueryBuilder({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(deleteDevicePushSubscription(client, 'https://push.example/ep')).resolves.toBeUndefined()
  })
})

describe('isDevicePushSubscribed', () => {
  it('returns true when a row exists for the endpoint', async () => {
    const client = {
      from: () => mockQueryBuilder({ data: { id: 'sub-1' }, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(isDevicePushSubscribed(client, 'https://push.example/ep')).resolves.toBe(true)
  })

  it('returns false when no row exists for the endpoint', async () => {
    const client = {
      from: () => mockQueryBuilder({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(isDevicePushSubscribed(client, 'https://push.example/ep')).resolves.toBe(false)
  })
})
