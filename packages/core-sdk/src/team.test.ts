import { describe, expect, it, vi } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { archiveTeamMember, getTeamMembers, updateJobTitle, updateTeamMember } from './team'
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

describe('Team mutations', () => {
  it('rejects a job-title update silently filtered out by RLS', async () => {
    const builder = mockQueryBuilder({ data: null, error: null })
    const client = { from: vi.fn(() => builder) } as unknown as SupabaseClient<Database>

    await expect(updateJobTitle(client, 'job-1', { active: false }))
      .rejects.toThrow('job_title_update_not_applied')
  })

  it('rejects an archive RPC that reports success without returning the changed membership', async () => {
    const client = {
      rpc: vi.fn(async () => ({ data: null, error: null })),
    } as unknown as SupabaseClient<Database>

    await expect(archiveTeamMember(client, { membershipId: 'membership-1' }))
      .rejects.toThrow('membership_archive_not_applied')
  })

  it('rejects a membership-status update silently filtered out by RLS', async () => {
    const builder = mockQueryBuilder({ data: null, error: null })
    const client = { from: vi.fn(() => builder) } as unknown as SupabaseClient<Database>

    await expect(updateTeamMember(client, {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      membershipStatus: 'suspended',
    })).rejects.toThrow('membership_status_update_not_applied')
  })

  it('rejects a role RPC that reports success without returning the changed membership', async () => {
    const client = {
      rpc: vi.fn(async () => ({ data: null, error: null })),
    } as unknown as SupabaseClient<Database>

    await expect(updateTeamMember(client, {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      roleId: 'role-2',
    })).rejects.toThrow('membership_role_update_not_applied')
  })

  it('rejects an existing staff-details update silently filtered out by RLS', async () => {
    const lookup = mockQueryBuilder({ data: { profile_id: 'profile-1' }, error: null })
    const mutation = mockQueryBuilder({ data: null, error: null })
    const client = {
      from: vi.fn()
        .mockReturnValueOnce(lookup)
        .mockReturnValueOnce(mutation),
    } as unknown as SupabaseClient<Database>

    await expect(updateTeamMember(client, {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      employmentStatus: 'inactive',
    })).rejects.toThrow('staff_details_update_not_applied')
  })

  it('rejects a staff-details insert that returns no visible row', async () => {
    const lookup = mockQueryBuilder({ data: null, error: null })
    const mutation = mockQueryBuilder({ data: null, error: null })
    const client = {
      from: vi.fn()
        .mockReturnValueOnce(lookup)
        .mockReturnValueOnce(mutation),
    } as unknown as SupabaseClient<Database>

    await expect(updateTeamMember(client, {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      jobTitleId: 'job-1',
    })).rejects.toThrow('staff_details_update_not_applied')
  })

  it('accepts mutations only when the changed rows are returned', async () => {
    const membershipMutation = mockQueryBuilder({ data: { id: 'membership-1' }, error: null })
    const detailsLookup = mockQueryBuilder({ data: { profile_id: 'profile-1' }, error: null })
    const detailsMutation = mockQueryBuilder({ data: { profile_id: 'profile-1' }, error: null })
    const client = {
      from: vi.fn()
        .mockReturnValueOnce(membershipMutation)
        .mockReturnValueOnce(detailsLookup)
        .mockReturnValueOnce(detailsMutation),
    } as unknown as SupabaseClient<Database>

    await expect(updateTeamMember(client, {
      membershipId: 'membership-1', profileId: 'profile-1', propertyId: 'property-1',
      membershipStatus: 'suspended', employmentStatus: 'inactive',
    })).resolves.toBeUndefined()
  })
})
