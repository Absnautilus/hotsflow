import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type GrantBody = {
  membershipId?: unknown
  action?: unknown
}

// Bridges (action: 'grant', the default) or removes (action: 'revoke') a
// Hotsflow membership's row in Housekeeping's own legacy staff_profiles
// table -- the "transitional compatibility gate" described in
// fase2-guest-requests-migration.md was backfilled once, for staff who
// already existed at migration time, and never extended to anyone created
// afterward through Team's own credentials/invite flow. Explicit and
// per-member on purpose (not automatic on every team-member creation): not
// every team member does housekeeping work, and an admin should decide who
// actually needs it -- toggled from the Modules popup on the Team page.
Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  if (!authorization) return json({ error: 'missing_authorization' }, 401)

  try {
    const body = await request.json() as GrantBody
    const membershipId = readUuid(body.membershipId)
    if (!membershipId) return json({ error: 'invalid_input' }, 400)
    const action = body.action === 'revoke' ? 'revoke' : 'grant'

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

    // profiles!profile_id -- memberships has two FKs into profiles
    // (profile_id and invited_by), so the plain embed profiles(full_name)
    // is ambiguous to PostgREST and errors out (silently mapped below to
    // membership_not_found, indistinguishable from a genuinely missing
    // membership until this comment was written -- confirmed live against
    // production, not assumed).
    const { data: membership, error: membershipError } = await admin
      .from('memberships')
      .select('profile_id, property_id, profiles!profile_id(full_name)')
      .eq('id', membershipId)
      .maybeSingle()
    if (membershipError || !membership || !membership.property_id) return json({ error: 'membership_not_found' }, 404)
    const fullName = (membership.profiles as { full_name: string } | null)?.full_name
    if (!fullName) return json({ error: 'membership_not_found' }, 404)

    const { data: canManage, error: permissionError } = await caller.rpc('has_permission', {
      p_property_id: membership.property_id,
      p_permission_slug: 'core.staff.manage',
    })
    if (permissionError || !canManage) return json({ error: 'forbidden' }, 403)

    // caller, not admin -- guest_requests_legacy_hotel_for_property is
    // SECURITY DEFINER but still calls has_property_access() internally,
    // which reads auth.uid() from the calling role's own JWT. The
    // service-role admin client carries no user JWT, so auth.uid() is
    // always null there and the RPC always returns null regardless of
    // whether a real mapping/entitlement exists -- confirmed live in
    // production (property_not_mapped on a property that *is* mapped).
    const { data: hotelId, error: hotelError } = await caller.rpc('guest_requests_legacy_hotel_for_property', {
      p_property_id: membership.property_id,
    })
    if (hotelError) return json({ error: 'lookup_failed' }, 500)
    if (!hotelId) return json({ error: 'property_not_mapped' }, 400)

    const { data: existing, error: existingError } = await admin
      .from('staff_profiles')
      .select('id, hotel_id')
      .eq('auth_user_id', membership.profile_id)
      .maybeSingle()
    if (existingError) return json({ error: 'lookup_failed' }, 500)

    if (action === 'revoke') {
      // No row at all -- the desired end state (no access) already holds;
      // idempotent, matching grant's own reactivate-if-exists idempotency.
      if (!existing) return json({ ok: true }, 200)
      if (existing.hotel_id !== hotelId) return json({ error: 'profile_exists_at_different_hotel' }, 409)
      const { error: revokeError } = await admin
        .from('staff_profiles')
        .update({ active: false })
        .eq('id', existing.id)
      if (revokeError) return json({ error: 'revoke_failed' }, 400)
      return json({ ok: true }, 200)
    }

    if (existing) {
      if (existing.hotel_id !== hotelId) return json({ error: 'profile_exists_at_different_hotel' }, 409)
      const { error: reactivateError } = await admin
        .from('staff_profiles')
        .update({ active: true })
        .eq('id', existing.id)
      if (reactivateError) return json({ error: 'grant_failed' }, 400)
      return json({ ok: true }, 200)
    }

    // role: 'admin' -- not 'operatore'. staff_profiles_login_username_matches_role
    // requires a non-null login_username (Housekeeping's own PIN-login
    // identifier, unrelated to Hotsflow's auth) for 'operatore'; a Hotsflow
    // Team member bridged in here already has a real Hotsflow login and
    // needs full internal visibility, not a PIN-scoped line-worker account.
    const { error: insertError } = await admin.from('staff_profiles').insert({
      hotel_id: hotelId,
      auth_user_id: membership.profile_id,
      name: fullName,
      role: 'admin',
      active: true,
    })
    if (insertError) return json({ error: 'grant_failed' }, 400)

    return json({ ok: true }, 200)
  } catch (error) {
    console.error('grant-housekeeping-access failed', error)
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
