import type { RealtimePostgresChangesPayload } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { Department } from '@/lib/types'
import type { QueuedRequest, StaffProfile } from '@/lib/staff-types'
import { usernameToEmail } from '@/lib/operator-login'
import { hotelFilter, realtimeHotelFilter } from '@/lib/hotel-query-scope'

const QUEUE_SELECT =
  '*, request_types(name, name_i18n, allows_quantity, available_quantity, request_categories(name, name_i18n)), accepted_by_staff:staff_profiles!accepted_by(name)'

export async function fetchMyProfile(): Promise<StaffProfile | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return null
  // RLS lets a master see every staff row at every hotel, and any staff
  // member sees the rest of their own hotel's team — so this can never rely
  // on "RLS happens to return one row" once there's more than one account.
  const { data, error } = await supabase.from('staff_profiles').select('*').eq('auth_user_id', user.id).maybeSingle()
  if (error) throw error
  return data
}

export async function signIn(email: string, password: string) {
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
}

export async function signInOperator(username: string, pin: string) {
  const { error } = await supabase.auth.signInWithPassword({ email: usernameToEmail(username), password: pin })
  if (error) throw error
}

export async function signOut() {
  await supabase.auth.signOut()
}

export async function fetchQueue(hotelId: string): Promise<QueuedRequest[]> {
  const { data, error } = await supabase
    .from('guest_requests')
    .select(QUEUE_SELECT)
    .eq(...hotelFilter(hotelId))
    .is('archived_at', null)
    .order('priority')
  if (error) throw error
  return (data ?? []) as unknown as QueuedRequest[]
}

const ARCHIVE_PAGE_SIZE = 15

// The 72h auto-archive job (0012) only hides rows from fetchQueue — RLS
// already lets admin/master read them, this just exposes that in the UI.
export async function fetchArchivedRequests(page: number, hotelId: string): Promise<{ items: QueuedRequest[]; total: number }> {
  const from = page * ARCHIVE_PAGE_SIZE
  const to = from + ARCHIVE_PAGE_SIZE - 1
  const { data, error, count } = await supabase
    .from('guest_requests')
    .select(QUEUE_SELECT, { count: 'exact' })
    .eq(...hotelFilter(hotelId))
    .not('archived_at', 'is', null)
    .order('archived_at', { ascending: false })
    .range(from, to)
  if (error) throw error
  return { items: (data ?? []) as unknown as QueuedRequest[], total: count ?? 0 }
}

export function subscribeToQueue(
  hotelId: string,
  onChange: (payload: RealtimePostgresChangesPayload<Record<string, unknown>>) => void,
) {
  const channel = supabase
    .channel(`guest_requests-queue-${hotelId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'guest_requests', filter: realtimeHotelFilter(hotelId) },
      onChange,
    )
    .subscribe()
  return () => {
    supabase.removeChannel(channel)
  }
}

export async function claimRequest(id: string, staffId: string) {
  const { error } = await supabase
    .from('guest_requests')
    .update({ status: 'in_progress', accepted_by: staffId, accepted_at: new Date().toISOString() })
    .eq('id', id)
    .eq('status', 'requested')
  if (error) throw error
}

export async function completeRequest(id: string) {
  const { error } = await supabase
    .from('guest_requests')
    .update({ status: 'completed', completed_at: new Date().toISOString() })
    .eq('id', id)
  if (error) throw error
}

export async function cancelRequest(id: string) {
  const { error } = await supabase.from('guest_requests').update({ status: 'cancelled' }).eq('id', id)
  if (error) throw error
}

// Steps a request back one stage instead of forward: an accepted job goes
// back to unclaimed, a completed one reopens as in-progress, a cancelled
// one is put back in the active queue. Distinct from deleteRequest, which
// is permanent — this only ever moves within the existing statuses.
export async function revertRequest(id: string, fromStatus: 'in_progress' | 'completed' | 'cancelled') {
  const patch =
    fromStatus === 'in_progress'
      ? { status: 'requested' as const, accepted_by: null, accepted_at: null }
      : fromStatus === 'completed'
        ? { status: 'in_progress' as const, completed_at: null, returned_at: null }
        : { status: 'requested' as const }
  const { error } = await supabase.from('guest_requests').update(patch).eq('id', id)
  if (error) throw error
}

// Only meaningful for a completed request on a trackable item (available_quantity
// set on its request_type) — marks the physical item as back in inventory so
// fetchItemAvailability stops counting it against the room it was delivered to.
export async function markItemReturned(id: string) {
  const { error } = await supabase.from('guest_requests').update({ returned_at: new Date().toISOString() }).eq('id', id)
  if (error) throw error
}

export async function deleteRequest(id: string) {
  const { error } = await supabase.from('guest_requests').delete().eq('id', id)
  if (error) throw error
}

export async function setOnDuty(onDuty: boolean) {
  const { error } = await supabase.rpc('set_on_duty', { p_on_duty: onDuty })
  if (error) throw error
}

// Upserts on endpoint (unique across the table) rather than inserting, so a
// browser that already has a subscription from a previous login just gets
// re-pointed at the current staff row instead of erroring on the unique
// constraint.
export async function savePushSubscription(staffId: string, sub: { endpoint: string; p256dh: string; auth: string }) {
  const { error } = await supabase
    .from('push_subscriptions')
    .upsert({ staff_id: staffId, endpoint: sub.endpoint, p256dh: sub.p256dh, auth: sub.auth }, { onConflict: 'endpoint' })
  if (error) throw error
}

export async function reassignRequest(id: string, department: Department) {
  const { error } = await supabase.from('guest_requests').update({ assigned_department: department }).eq('id', id)
  if (error) throw error
}

// Staff-reported issue, not tied to a guest. The client sends the selected
// hotel explicitly; the DB trigger still derives assigned_department and
// independently validates the room, menu item, and staff tenant references.
export async function createStaffRequest(input: { hotelId: string; roomNumber: string; requestTypeId: string; note: string | null; staffId: string }) {
  const { error } = await supabase.from('guest_requests').insert({
    hotel_id: input.hotelId,
    room_number: input.roomNumber,
    request_type_id: input.requestTypeId,
    note: input.note,
    created_by_staff: input.staffId,
  })
  if (error) throw error
}

// Swaps two requests' priority so one moves ahead of the other in the
// "in carico" column. Two sequential updates rather than one atomic
// statement — a partial failure just leaves the order unchanged, which is
// an acceptable failure mode for a manual reorder action.
export async function swapPriority(a: { id: string; priority: number }, b: { id: string; priority: number }) {
  const { error: e1 } = await supabase.from('guest_requests').update({ priority: b.priority }).eq('id', a.id)
  if (e1) throw e1
  const { error: e2 } = await supabase.from('guest_requests').update({ priority: a.priority }).eq('id', b.id)
  if (e2) throw e2
}
