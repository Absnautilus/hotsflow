import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'

export interface DevicePushSubscriptionKeys {
  endpoint: string
  p256dh: string
  auth: string
}

// Owned by `profiles`, not any module-specific table -- works for any
// signed-in user regardless of module access. `onConflict: 'endpoint'`
// means re-subscribing the same browser/device transfers the row to
// whoever is currently signed in on it, which is the correct behavior for
// a shared device.
export async function saveDevicePushSubscription(
  client: SupabaseClient<Database>,
  keys: DevicePushSubscriptionKeys,
): Promise<void> {
  const { data: userData } = await client.auth.getUser()
  if (!userData.user) throw new Error('not_authenticated')
  const { error } = await client
    .from('device_push_subscriptions')
    .upsert(
      { profile_id: userData.user.id, endpoint: keys.endpoint, p256dh: keys.p256dh, auth: keys.auth },
      { onConflict: 'endpoint' },
    )
  if (error) throw error
}

export async function deleteDevicePushSubscription(client: SupabaseClient<Database>, endpoint: string): Promise<void> {
  const { error } = await client.from('device_push_subscriptions').delete().eq('endpoint', endpoint)
  if (error) throw error
}

export async function isDevicePushSubscribed(client: SupabaseClient<Database>, endpoint: string): Promise<boolean> {
  const { data, error } = await client
    .from('device_push_subscriptions')
    .select('id')
    .eq('endpoint', endpoint)
    .maybeSingle()
  if (error) throw error
  return data !== null
}
