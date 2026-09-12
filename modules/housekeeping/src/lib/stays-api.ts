import { supabase } from '@/lib/supabase'
import type { Room } from '@/lib/admin-api'
import type { Department } from '@/lib/types'
import { hotelFilter } from '@/lib/hotel-query-scope'

export interface Stay {
  id: string
  room_id: string
  guest_last_name: string
  guest_pin: string
  check_in_at: string
  check_out_at: string
  status: 'active' | 'closed' | 'cancelled'
  rooms: Pick<Room, 'room_number'> | null
}

export async function listStays(hotelId: string): Promise<Stay[]> {
  const { data, error } = await supabase
    .from('stays')
    .select('id, room_id, guest_last_name, guest_pin, check_in_at, check_out_at, status, rooms(room_number)')
    .eq(...hotelFilter(hotelId))
    .eq('status', 'active')
    .order('check_in_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as unknown as Stay[]
}

export async function createStay(input: {
  hotelId: string
  roomId: string
  guestLastName: string
  checkInAt: string
  checkOutAt: string
}): Promise<Stay> {
  const { data, error } = await supabase
    .from('stays')
    .insert({
      hotel_id: input.hotelId,
      room_id: input.roomId,
      guest_last_name: input.guestLastName,
      check_in_at: input.checkInAt,
      check_out_at: input.checkOutAt,
    })
    .select('id, room_id, guest_last_name, guest_pin, check_in_at, check_out_at, status, rooms(room_number)')
    .single()
  if (error) throw error
  return data as unknown as Stay
}

export async function updateCheckout(id: string, checkOutAt: string): Promise<void> {
  const { data, error } = await supabase.from('stays').update({ check_out_at: checkOutAt }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('stay_checkout_update_not_applied')
}

export async function updateStay(
  id: string,
  input: { roomId: string; guestLastName: string; checkInAt: string; checkOutAt: string },
): Promise<void> {
  const { data, error } = await supabase
    .from('stays')
    .update({ room_id: input.roomId, guest_last_name: input.guestLastName, check_in_at: input.checkInAt, check_out_at: input.checkOutAt })
    .eq('id', id)
    .select('id')
    .maybeSingle()
  if (error) throw error
  if (!data) throw new Error('stay_update_not_applied')
}

// Distinct from updateCheckout (used by "Estendi", which only ever pushes
// check_out_at later and must never touch status): a guest checking out
// early has genuinely finished their stay, so this also closes it --
// status: 'closed', not 'cancelled' (cancelStay's own meaning, reserved for
// an administrative cancellation, e.g. a booking mistake). Closing is what
// makes listStays() (status = 'active') drop the row, and what makes
// sync_guest_sessions_on_stay_change revoke every one of the guest's
// sessions unconditionally rather than only those expiring after the new
// checkout time.
export async function checkOutStayNow(id: string): Promise<void> {
  const { data, error } = await supabase
    .from('stays')
    .update({ check_out_at: new Date().toISOString(), status: 'closed' })
    .eq('id', id)
    .select('id')
    .maybeSingle()
  if (error) throw error
  if (!data) throw new Error('stay_checkout_now_not_applied')
}

export async function cancelStay(id: string): Promise<void> {
  const { data, error } = await supabase.from('stays').update({ status: 'cancelled' }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('stay_cancel_not_applied')
}

export interface StayRequest {
  id: string
  status: 'requested' | 'in_progress' | 'completed' | 'cancelled'
  created_at: string
  completed_at: string | null
  assigned_department: Department
  request_types: { name: string; name_i18n: Record<string, string> } | null
}

export async function fetchRequestsForStay(stayId: string, hotelId: string): Promise<StayRequest[]> {
  const { data, error } = await supabase
    .from('guest_requests')
    .select('id, status, created_at, completed_at, assigned_department, request_types(name, name_i18n)')
    .eq(...hotelFilter(hotelId))
    .eq('stay_id', stayId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as unknown as StayRequest[]
}
