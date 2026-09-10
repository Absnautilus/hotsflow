import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getCurrentProfile } from './profile'
import { mockAuthenticatedUser, mockNoUser, mockQueryBuilder } from './testSupport'

describe('getCurrentProfile', () => {
  it('returns null when nobody is signed in, without querying profiles', async () => {
    const client = {
      auth: { getUser: async () => mockNoUser() },
      from: () => {
        throw new Error('should not query profiles without a signed-in user')
      },
    } as unknown as SupabaseClient<Database>

    await expect(getCurrentProfile(client)).resolves.toBeNull()
  })

  it('maps a profile row to the domain shape', async () => {
    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: () =>
        mockQueryBuilder({
          data: { id: 'user-1', full_name: 'Ada Lovelace', avatar_url: null, created_at: '', updated_at: '' },
          error: null,
        }),
    } as unknown as SupabaseClient<Database>

    await expect(getCurrentProfile(client)).resolves.toEqual({
      id: 'user-1',
      fullName: 'Ada Lovelace',
      avatarUrl: null,
    })
  })

  it('returns null when a session exists but no profile row does yet', async () => {
    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: () => mockQueryBuilder({ data: null, error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getCurrentProfile(client)).resolves.toBeNull()
  })
})
