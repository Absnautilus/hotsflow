import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type {
  CoreRole,
  CreateTeamMemberWithCredentialsInput,
  CreateTeamMemberWithCredentialsResult,
  EmploymentStatus,
  InviteTeamMemberInput,
  JobTitle,
  Membership,
  Profile,
  ResetTeamMemberPasswordInput,
  TeamMember,
  UpdateTeamMemberInput,
} from './types/domain'

type MembershipRow = Database['public']['Tables']['memberships']['Row']

function mapMembership(row: MembershipRow): Membership {
  return {
    id: row.id,
    profileId: row.profile_id,
    propertyId: row.property_id,
    organizationId: row.organization_id,
    roleId: row.role_id,
    status: row.status as Membership['status'],
    username: row.username,
  }
}

function mapProfile(row: Database['public']['Tables']['profiles']['Row']): Profile {
  return { id: row.id, fullName: row.full_name, avatarUrl: row.avatar_url }
}

function mapRole(row: Database['public']['Tables']['roles']['Row']): CoreRole {
  return {
    id: row.id,
    slug: row.slug,
    displayName: row.display_name,
    scope: row.scope as CoreRole['scope'],
    rank: row.rank,
  }
}

function mapJobTitle(row: Database['public']['Tables']['property_job_titles']['Row']): JobTitle {
  return { id: row.id, propertyId: row.property_id, name: row.name, active: row.active }
}

export async function getPropertyRoles(client: SupabaseClient<Database>): Promise<CoreRole[]> {
  const { data, error } = await client.from('roles').select('*').eq('scope', 'property').order('rank')
  if (error) throw error
  return (data ?? []).map(mapRole)
}

export async function getJobTitles(client: SupabaseClient<Database>, propertyId: string): Promise<JobTitle[]> {
  const { data, error } = await client
    .from('property_job_titles')
    .select('*')
    .eq('property_id', propertyId)
    .order('name')
  if (error) throw error
  return (data ?? []).map(mapJobTitle)
}

export async function getTeamMembers(client: SupabaseClient<Database>, propertyId: string): Promise<TeamMember[]> {
  const propertyResult = await client.from('properties').select('organization_id').eq('id', propertyId).maybeSingle()
  if (propertyResult.error) throw propertyResult.error
  if (!propertyResult.data) return []

  const membershipsResult = await client
    .from('memberships')
    .select('*')
    .or(`property_id.eq.${propertyId},organization_id.eq.${propertyResult.data.organization_id}`)
  if (membershipsResult.error) throw membershipsResult.error
  const memberships = membershipsResult.data ?? []
  if (memberships.length === 0) return []

  const profileIds = [...new Set(memberships.map((row) => row.profile_id))]
  const roleIds = [...new Set(memberships.map((row) => row.role_id))]
  const [profilesResult, rolesResult, detailsResult, titlesResult] = await Promise.all([
    client.from('profiles').select('*').in('id', profileIds),
    client.from('roles').select('*').in('id', roleIds),
    client.from('property_staff_details').select('*').eq('property_id', propertyId),
    client.from('property_job_titles').select('*').eq('property_id', propertyId),
  ])
  if (profilesResult.error) throw profilesResult.error
  if (rolesResult.error) throw rolesResult.error
  if (detailsResult.error) throw detailsResult.error
  if (titlesResult.error) throw titlesResult.error

  const profiles = new Map((profilesResult.data ?? []).map((row) => [row.id, mapProfile(row)]))
  const roles = new Map((rolesResult.data ?? []).map((row) => [row.id, mapRole(row)]))
  const details = new Map((detailsResult.data ?? []).map((row) => [row.profile_id, row]))
  const titles = new Map((titlesResult.data ?? []).map((row) => [row.id, mapJobTitle(row)]))

  // A profile can have both an org-wide and a direct membership reaching the
  // same property. Render it once, preferring the more specific direct row.
  const uniqueMemberships = [...memberships]
    .sort((left, right) => Number(right.property_id === propertyId) - Number(left.property_id === propertyId))
    .filter((row, index, rows) => rows.findIndex((candidate) => candidate.profile_id === row.profile_id) === index)

  return uniqueMemberships.flatMap((membershipRow) => {
    const profile = profiles.get(membershipRow.profile_id)
    const role = roles.get(membershipRow.role_id)
    if (!profile || !role) return []
    const detail = details.get(membershipRow.profile_id)
    return [{
      profile,
      membership: mapMembership(membershipRow),
      role,
      jobTitle: detail?.job_title_id ? titles.get(detail.job_title_id) ?? null : null,
      employmentStatus: (detail?.employment_status ?? 'active') as EmploymentStatus,
    }]
  }).sort((left, right) => left.profile.fullName.localeCompare(right.profile.fullName))
}

export async function createJobTitle(client: SupabaseClient<Database>, propertyId: string, name: string): Promise<JobTitle> {
  const { data: userData } = await client.auth.getUser()
  const { data, error } = await client.from('property_job_titles').insert({
    property_id: propertyId,
    name: name.trim(),
    created_by: userData.user?.id ?? null,
  }).select('*').single()
  if (error) throw error
  return mapJobTitle(data)
}

export async function updateJobTitle(client: SupabaseClient<Database>, id: string, changes: { name?: string; active?: boolean }): Promise<void> {
  const { data, error } = await client.from('property_job_titles').update(changes).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('job_title_update_not_applied')
}

export async function inviteTeamMember(client: SupabaseClient<Database>, input: InviteTeamMemberInput): Promise<void> {
  const { error } = await client.functions.invoke('invite-team-member', { body: input })
  if (error) throw error
}

export async function createTeamMemberWithCredentials(client: SupabaseClient<Database>, input: CreateTeamMemberWithCredentialsInput): Promise<CreateTeamMemberWithCredentialsResult> {
  const { data, error } = await client.functions.invoke('create-team-member-credentials', { body: input })
  if (error) throw error
  return data as CreateTeamMemberWithCredentialsResult
}

export async function resetTeamMemberPassword(client: SupabaseClient<Database>, input: ResetTeamMemberPasswordInput): Promise<void> {
  const { error } = await client.functions.invoke('reset-team-member-password', { body: input })
  if (error) throw error
}

export async function updateTeamMember(client: SupabaseClient<Database>, input: UpdateTeamMemberInput): Promise<void> {
  if (input.roleId) {
    const { data, error } = await client.rpc('assign_membership_role', {
      p_membership_id: input.membershipId,
      p_new_role_id: input.roleId,
    })
    if (error) throw error
    if (!data) throw new Error('membership_role_update_not_applied')
  }

  if (input.membershipStatus) {
    const { data, error } = await client.from('memberships')
      .update({ status: input.membershipStatus })
      .eq('id', input.membershipId)
      .select('id')
      .maybeSingle()
    if (error) throw error
    if (!data) throw new Error('membership_status_update_not_applied')
  }

  if (input.jobTitleId !== undefined || input.employmentStatus !== undefined) {
    const existing = await client.from('property_staff_details')
      .select('profile_id')
      .eq('property_id', input.propertyId)
      .eq('profile_id', input.profileId)
      .maybeSingle()
    if (existing.error) throw existing.error

    const changes = {
      ...(input.jobTitleId !== undefined ? { job_title_id: input.jobTitleId } : {}),
      ...(input.employmentStatus !== undefined ? { employment_status: input.employmentStatus } : {}),
    }
    const result = existing.data
      ? await client.from('property_staff_details').update(changes)
        .eq('property_id', input.propertyId).eq('profile_id', input.profileId)
        .select('profile_id').maybeSingle()
      : await client.from('property_staff_details').insert({
        property_id: input.propertyId,
        profile_id: input.profileId,
        ...changes,
      }).select('profile_id').maybeSingle()
    if (result.error) throw result.error
    if (!result.data) throw new Error('staff_details_update_not_applied')
  }
}
