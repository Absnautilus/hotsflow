import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type ResetBody = {
  membershipId?: unknown
  newPassword?: unknown
}

// Admin-triggered password reset for a credentials-based (username, no
// email) team member -- the counterpart to the member changing their own
// password themselves via supabase.auth.updateUser(). Scoped to
// credentials-based accounts only (membership.username is not null):
// an email-invited account has no admin-facing password to reset here.
Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'missing_authorization' }, 401)

  try {
    const body = await request.json() as ResetBody
    const membershipId = readUuid(body.membershipId)
    const newPassword = String(body.newPassword ?? '')

    if (!membershipId || newPassword.length < 8 || newPassword.length > 72) {
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
    if (userError || !userData.user) return json({ error: 'invalid_session' }, 401)

    const { data: membership, error: membershipError } = await admin
      .from('memberships')
      .select('profile_id, property_id, username')
      .eq('id', membershipId)
      .maybeSingle()
    if (membershipError || !membership) return json({ error: 'membership_not_found' }, 404)
    if (!membership.property_id || !membership.username) return json({ error: 'not_a_credentials_account' }, 400)

    const { data: canManage, error: permissionError } = await caller.rpc('has_permission', {
      p_property_id: membership.property_id,
      p_permission_slug: 'core.staff.manage',
    })
    if (permissionError || !canManage) return json({ error: 'forbidden' }, 403)

    const { error: updateError } = await admin.auth.admin.updateUserById(membership.profile_id, { password: newPassword })
    if (updateError) return json({ error: 'reset_failed' }, 400)

    return json({ ok: true }, 200)
  } catch (error) {
    console.error('reset-team-member-password failed', error)
    return json({ error: 'unexpected_error' }, 500)
  }
})

function readUuid(value: unknown): string | null {
  const candidate = String(value ?? '').trim()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate) ? candidate : null
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
