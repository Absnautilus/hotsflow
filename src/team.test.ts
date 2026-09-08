import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getTeamMembers } from './team'
import { mockQueryBuilder } from './testSupport'

describe('getTeamMembers', () => {
  it('combines Core access with property job metadata and deduplicates direct + org-wide access', async () => {
    const rows = {
      memberships: [
        { id: 'org-membership', profile_id: 'profile-1', property_id: null, organization_id: 'org-1', role_id: 'role-org', status: 'active', invited_by: null, created_at: '', updated_at: '' },
        { id: 'direct-membership', profile_id: 'profile-1', property_id: 'property-1', organization_id: null, role_id: 'role-property', status: 'active', invited_by: null, created_at: '', updated_at: '' },
      ],
      profiles: [{ id: 'profile-1', full_name: 'Ada Lovelace', avatar_url: null, created_at: '', updated_at: '' }],
      roles: [
        { id: 'role-org', slug: 'organization_admin', display_name: 'Organization Admin', scope: 'organization', rank: 40, is_system: true, created_at: '' },
        { id: 'role-property', slug: 'manager', display_name: 'Manager', scope: 'property', rank: 20, is_system: true, created_at: '' },
      ],
      property_staff_details: [{ property_id: 'property-1', profile_id: 'profile-1', job_title_id: 'job-1', employment_status: 'active', created_by: null, created_at: '', updated_at: '' }],
      property_job_titles: [{ id: 'job-1', property_id: 'property-1', name: 'Reception', active: true, created_by: null, created_at: '', updated_at: '' }],
    }
    const client = {
      from: (table: string) => table === 'properties'
        ? mockQueryBuilder({ data: { organization_id: 'org-1' }, error: null })
        : mockQueryBuilder({ data: rows[table as keyof typeof rows], error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getTeamMembers(client, 'property-1')).resolves.toEqual([{
      profile: { id: 'profile-1', fullName: 'Ada Lovelace', avatarUrl: null },
      membership: { id: 'direct-membership', profileId: 'profile-1', propertyId: 'property-1', organizationId: null, roleId: 'role-property', status: 'active' },
      role: { id: 'role-property', slug: 'manager', displayName: 'Manager', scope: 'property', rank: 20 },
      jobTitle: { id: 'job-1', propertyId: 'property-1', name: 'Reception', active: true },
      employmentStatus: 'active',
    }])
  })
})
