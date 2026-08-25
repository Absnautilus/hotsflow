import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getAccessibleProperties, getMembership } from './memberships'
import { mockAuthenticatedUser, mockNoUser, mockQueryBuilder } from './testSupport'

const membershipRow = {
  id: 'm-1',
  profile_id: 'user-1',
  property_id: 'property-1',
  organization_id: null,
  role_id: 'role-1',
  status: 'active' as const,
  invited_by: null,
  created_at: '',
  updated_at: '',
}

describe('getAccessibleProperties', () => {
  it('maps every row RLS returns, without filtering by property_id itself', async () => {
    const client = {
      from: () =>
        mockQueryBuilder({
          data: [
            {
              id: 'property-1',
              organization_id: 'org-1',
              name: 'Property A1',
              slug: 'a1',
              timezone: 'Europe/Rome',
              status: 'active' as const,
              settings: {},
              created_at: '',
              updated_at: '',
            },
          ],
          error: null,
        }),
    } as unknown as SupabaseClient<Database>

    await expect(getAccessibleProperties(client)).resolves.toEqual([
      {
        id: 'property-1',
        organizationId: 'org-1',
        name: 'Property A1',
        slug: 'a1',
        timezone: 'Europe/Rome',
        status: 'active',
        settings: {},
      },
    ])
  })
})

describe('getMembership', () => {
  it('returns null when nobody is signed in', async () => {
    const client = {
      auth: { getUser: async () => mockNoUser() },
    } as unknown as SupabaseClient<Database>

    await expect(getMembership(client, 'property-1')).resolves.toBeNull()
  })

  it('returns the direct property membership when one exists, without checking org-wide', async () => {
    let propertiesQueried = false
    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: (table: string) => {
        if (table === 'memberships') return mockQueryBuilder({ data: membershipRow, error: null })
        if (table === 'properties') propertiesQueried = true
        return mockQueryBuilder({ data: null, error: null })
      },
    } as unknown as SupabaseClient<Database>

    await expect(getMembership(client, 'property-1')).resolves.toEqual({
      id: 'm-1',
      profileId: 'user-1',
      propertyId: 'property-1',
      organizationId: null,
      roleId: 'role-1',
      status: 'active',
    })
    expect(propertiesQueried).toBe(false)
  })

  it('falls back to an org-wide membership when no direct one exists', async () => {
    let membershipCall = 0
    const orgWideRow = { ...membershipRow, id: 'm-2', property_id: null, organization_id: 'org-1' }

    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: (table: string) => {
        if (table === 'properties') return mockQueryBuilder({ data: { organization_id: 'org-1' }, error: null })
        membershipCall += 1
        // first call: no direct membership. second call: the org-wide one.
        return membershipCall === 1
          ? mockQueryBuilder({ data: null, error: null })
          : mockQueryBuilder({ data: orgWideRow, error: null })
      },
    } as unknown as SupabaseClient<Database>

    await expect(getMembership(client, 'property-1')).resolves.toEqual({
      id: 'm-2',
      profileId: 'user-1',
      propertyId: null,
      organizationId: 'org-1',
      roleId: 'role-1',
      status: 'active',
    })
  })

  it('returns null when there is neither a direct nor an org-wide membership', async () => {
    let membershipCall = 0
    const client = {
      auth: { getUser: async () => mockAuthenticatedUser('user-1') },
      from: (table: string) => {
        if (table === 'properties') return mockQueryBuilder({ data: { organization_id: 'org-1' }, error: null })
        membershipCall += 1
        return mockQueryBuilder({ data: null, error: null })
      },
    } as unknown as SupabaseClient<Database>

    await expect(getMembership(client, 'property-1')).resolves.toBeNull()
    expect(membershipCall).toBe(2)
  })
})
