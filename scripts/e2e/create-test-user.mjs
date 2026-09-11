#!/usr/bin/env node
// Provisions the one fixed test user the E2E login smoke test needs, against
// a LOCAL Supabase stack only (`supabase start`). Automates what
// supabase/seed.sql's "profiles / memberships" section documents as a
// manual step (auth.users is managed by Supabase Auth/GoTrue, so it can't
// be seeded with a plain SQL insert) -- idempotent, safe to re-run.
//
// Usage:
//   supabase start
//   SUPABASE_SERVICE_ROLE_KEY=<from `supabase status`> node scripts/e2e/create-test-user.mjs
//
// Gives the created user an org-wide admin membership on the seed data's
// "Organization A" (see supabase/seed.sql), enough to reach a working Home
// page after login.

import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321'
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!SERVICE_ROLE_KEY) {
  console.error(
    'Missing SUPABASE_SERVICE_ROLE_KEY. Run `supabase status` (after `supabase start`) and pass its ' +
      '"service_role key" value: SUPABASE_SERVICE_ROLE_KEY=... node scripts/e2e/create-test-user.mjs',
  )
  process.exit(1)
}

export const E2E_TEST_EMAIL = 'e2e-smoke@example.test'
export const E2E_TEST_PASSWORD = 'e2e-smoke-test-password-only'

const ORGANIZATION_A_ID = 'a0000000-0000-0000-0000-000000000001'

async function main() {
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const { data: existingUsers, error: listError } = await admin.auth.admin.listUsers()
  if (listError) throw listError

  let userId = existingUsers.users.find((user) => user.email === E2E_TEST_EMAIL)?.id

  if (!userId) {
    const { data, error } = await admin.auth.admin.createUser({
      email: E2E_TEST_EMAIL,
      password: E2E_TEST_PASSWORD,
      email_confirm: true,
    })
    if (error) throw error
    userId = data.user.id
    console.log(`Created auth user ${E2E_TEST_EMAIL} (${userId})`)
  } else {
    console.log(`Auth user ${E2E_TEST_EMAIL} already exists (${userId})`)
  }

  const { error: profileError } = await admin
    .from('profiles')
    .upsert({ id: userId, full_name: 'E2E Smoke Test User' }, { onConflict: 'id' })
  if (profileError) throw profileError

  const { data: role, error: roleError } = await admin
    .from('roles')
    .select('id')
    .eq('slug', 'organization_admin')
    .single()
  if (roleError) throw roleError

  const { error: membershipError } = await admin.from('memberships').upsert(
    {
      profile_id: userId,
      organization_id: ORGANIZATION_A_ID,
      role_id: role.id,
      status: 'active',
    },
    { onConflict: 'profile_id,organization_id' },
  )
  if (membershipError) throw membershipError

  console.log(`Ready: ${E2E_TEST_EMAIL} / ${E2E_TEST_PASSWORD} -- org-wide admin on Organization A.`)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
