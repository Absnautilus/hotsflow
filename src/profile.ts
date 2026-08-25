import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import type { Profile } from './types/domain'

function mapProfileRow(row: Database['public']['Tables']['profiles']['Row']): Profile {
  return {
    id: row.id,
    fullName: row.full_name,
    avatarUrl: row.avatar_url,
  }
}

// Returns null both when nobody is signed in and when a session exists but
// no profile row exists yet for it — the two aren't distinguished because no
// module should be branching on that difference; both mean "nothing to show
// yet".
export async function getCurrentProfile(client: SupabaseClient<Database>): Promise<Profile | null> {
  const {
    data: { user },
  } = await client.auth.getUser()
  if (!user) return null

  const { data, error } = await client.from('profiles').select('*').eq('id', user.id).maybeSingle()
  if (error) throw error
  return data ? mapProfileRow(data) : null
}
