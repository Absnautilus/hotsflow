import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type CreateBody = {
  propertyId?: unknown
  fullName?: unknown
  username?: unknown
  password?: unknown
  roleId?: unknown
  jobTitleId?: unknown
}

// The credentials alternative to invite-team-member: no email, no invite
// mail. Supabase Auth still requires a globally-unique email internally, so
// one is synthesized from username + property slug + organization slug --
// invisible to the admin and the staff member, who only ever see/type the
// plain username and password. username itself is only required to be
// unique per property (memberships_property_username_unique), which is why
// the synthetic email must fold in both slugs: two properties are free to
// both hand out the username "mario".
Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'missing_authorization' }, 401)

  try {
    const body = await request.json() as CreateBody
    const propertyId = readUuid(body.propertyId)
    const roleId = readUuid(body.roleId)
    const jobTitleId = body.jobTitleId == null || body.jobTitleId === '' ? null : readUuid(body.jobTitleId)
    const fullName = String(body.fullName ?? '').trim()
    const username = String(body.username ?? '').trim().toLowerCase()
    const password = String(body.password ?? '')

    if (
      !propertyId || !roleId || (body.jobTitleId && !jobTitleId) ||
      fullName.length < 2 || fullName.length > 120 ||
      !isUsername(username) || password.length < 8 || password.length > 72
    ) {
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
    // memberships INSERT policy before creating any account.
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

    const { data: property, error: propertyError } = await admin
      .from('properties')
      .select('slug, organizations(slug)')
      .eq('id', propertyId)
      .single()
    if (propertyError || !property) return json({ error: 'invalid_property' }, 400)
    const organizationSlug = (property.organizations as { slug: string } | null)?.slug
    if (!organizationSlug) return json({ error: 'invalid_property' }, 400)

    // Best-effort pre-check for a friendlier error than the partial unique
    // index's 23505 -- the index is still the source of truth (see the
    // insert below), this just avoids creating an orphan auth user first.
    const { data: existingUsername } = await admin
      .from('memberships')
      .select('id')
      .eq('property_id', propertyId)
      .eq('username', username)
      .maybeSingle()
    if (existingUsername) return json({ error: 'username_already_exists' }, 409)

    const loginIdentifier = `${username}@${property.slug}.${organizationSlug}.staff.hotsflow.internal`

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: loginIdentifier,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    })
    if (createError || !created.user) {
      const duplicate = /already|registered|exists/i.test(createError?.message ?? '')
      return json({ error: duplicate ? 'account_already_exists' : 'create_failed' }, duplicate ? 409 : 400)
    }

    const profileId = created.user.id
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
        username,
      })
      .select('id')
      .single()

    if (membershipError || !membership) {
      await admin.auth.admin.deleteUser(profileId)
      const duplicate = (membershipError as { code?: string } | null)?.code === '23505'
      return json({ error: duplicate ? 'username_already_exists' : 'membership_creation_failed' }, duplicate ? 409 : 400)
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

    return json({ profileId, membershipId: membership.id, loginIdentifier }, 201)
  } catch (error) {
    console.error('create-team-member-credentials failed', error)
    return json({ error: 'unexpected_error' }, 500)
  }
})

function readUuid(value: unknown): string | null {
  const candidate = String(value ?? '').trim()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate) ? candidate : null
}

// Mirrors memberships_username_format's check constraint exactly.
function isUsername(value: string): boolean {
  return /^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$/.test(value)
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
