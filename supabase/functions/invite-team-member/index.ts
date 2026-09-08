import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type InviteBody = {
  propertyId?: unknown
  fullName?: unknown
  email?: unknown
  roleId?: unknown
  jobTitleId?: unknown
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'missing_authorization' }, 401)

  try {
    const body = await request.json() as InviteBody
    const propertyId = readUuid(body.propertyId)
    const roleId = readUuid(body.roleId)
    const jobTitleId = body.jobTitleId == null || body.jobTitleId === '' ? null : readUuid(body.jobTitleId)
    const fullName = String(body.fullName ?? '').trim()
    const email = String(body.email ?? '').trim().toLowerCase()

    if (!propertyId || !roleId || body.jobTitleId && !jobTitleId || fullName.length < 2 || fullName.length > 120 || !isEmail(email)) {
      return json({ error: 'invalid_input' }, 400)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: 'server_not_configured' }, 500)

    const caller = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: authorization } },
    })
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: userData, error: userError } = await caller.auth.getUser()
    const actor = userData.user
    if (userError || !actor) return json({ error: 'invalid_session' }, 401)

    const { data: canManage, error: permissionError } = await caller.rpc('has_permission', {
      p_property_id: propertyId,
      p_permission_slug: 'core.staff.manage',
    })
    if (permissionError || !canManage) return json({ error: 'forbidden' }, 403)

    // Validate the initial role with the same hierarchy rule used by the
    // memberships INSERT policy before sending an email or using service role.
    const { data: roleAllowed, error: roleError } = await caller.rpc('role_assignment_allowed', {
      p_new_role_id: roleId,
      p_property_id: propertyId,
      p_organization_id: null,
      p_target_profile_id: crypto.randomUUID(),
    })
    if (roleError || !roleAllowed) return json({ error: 'role_assignment_not_allowed' }, 403)

    if (jobTitleId) {
      const { data: jobTitle, error: jobTitleError } = await caller
        .from('property_job_titles')
        .select('id')
        .eq('id', jobTitleId)
        .eq('property_id', propertyId)
        .eq('active', true)
        .maybeSingle()
      if (jobTitleError || !jobTitle) return json({ error: 'invalid_job_title' }, 400)
    }

    const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { full_name: fullName },
    })
    if (inviteError || !invited.user) {
      const duplicate = /already|registered|exists/i.test(inviteError?.message ?? '')
      return json({ error: duplicate ? 'account_already_exists' : 'invite_failed' }, duplicate ? 409 : 400)
    }

    const profileId = invited.user.id
    const { error: profileError } = await admin.from('profiles').insert({ id: profileId, full_name: fullName })
    if (profileError) {
      await admin.auth.admin.deleteUser(profileId)
      return json({ error: 'profile_creation_failed' }, 400)
    }

    const { data: membership, error: membershipError } = await caller
      .from('memberships')
      .insert({
        profile_id: profileId,
        property_id: propertyId,
        role_id: roleId,
        status: 'active',
        invited_by: actor.id,
      })
      .select('id')
      .single()

    if (membershipError || !membership) {
      await admin.auth.admin.deleteUser(profileId)
      return json({ error: 'membership_creation_failed' }, 400)
    }

    const { error: detailsError } = await caller.from('property_staff_details').insert({
      property_id: propertyId,
      profile_id: profileId,
      job_title_id: jobTitleId,
      created_by: actor.id,
    })
    if (detailsError) {
      await admin.from('memberships').delete().eq('id', membership.id)
      await admin.auth.admin.deleteUser(profileId)
      return json({ error: 'staff_details_creation_failed' }, 400)
    }

    return json({ profileId, membershipId: membership.id }, 201)
  } catch (error) {
    console.error('invite-team-member failed', error)
    return json({ error: 'unexpected_error' }, 500)
  }
})

function readUuid(value: unknown): string | null {
  const candidate = String(value ?? '').trim()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate) ? candidate : null
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
