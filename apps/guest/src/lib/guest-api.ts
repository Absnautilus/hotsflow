import { supabase } from '@/lib/supabase'
import { getHotelId, getHotelSlugFromPath, getStoredHotelId, setResolvedHotelId } from '@/lib/env'
import type { GuestRequest, RequestCategory, RequestType } from '@/lib/types'

export function isInvalidSessionError(error: unknown): boolean {
  return error instanceof Error && error.message.includes('invalid_session')
}

// Resolves this visit's hotel from the URL's slug (see
// getHotelSlugFromPath), falling back to a previously resolved id
// (localStorage) for a bare-origin revisit. Returns false when neither
// source yields a real hotel -- the caller should show an invalid-link
// screen rather than a login form that can never succeed.
export async function resolveHotelFromSlug(): Promise<boolean> {
  const slug = getHotelSlugFromPath()
  if (slug) {
    try {
      const { data, error } = await supabase.rpc('resolve_hotel_guest_slug', { p_slug: slug })
      if (!error && data) {
        setResolvedHotelId(data)
        return true
      }
    } catch {
      // network failure resolving the slug -- fall through to a previously
      // resolved id below rather than leaving the caller hanging
    }
  }
  const stored = getStoredHotelId()
  if (stored) {
    setResolvedHotelId(stored)
    return true
  }
  return false
}

export async function guestLogin(roomNumber: string, pin: string): Promise<string | null> {
  const { data, error } = await supabase.rpc('guest_login', {
    p_hotel_id: getHotelId(),
    p_room_number: roomNumber,
    p_pin: pin,
  })
  if (error) throw error
  return data
}

export async function fetchMenu(): Promise<{ categories: RequestCategory[]; types: RequestType[] }> {
  // request_categories/request_types RLS only checks `active`, not
  // hotel_id (a guest session has no per-hotel scope to enforce it with) —
  // this filter is what actually keeps another hotel's menu out of view.
  const categoriesRes = await supabase.from('request_categories').select('*').eq('hotel_id', getHotelId()).order('sort_order')
  if (categoriesRes.error) throw categoriesRes.error
  const categories = categoriesRes.data ?? []

  const categoryIds = categories.map((c) => c.id)
  if (categoryIds.length === 0) return { categories, types: [] }

  const typesRes = await supabase.from('request_types').select('*').in('category_id', categoryIds).order('sort_order')
  if (typesRes.error) throw typesRes.error
  return { categories, types: typesRes.data ?? [] }
}

export async function createGuestRequest(
  token: string,
  requestTypeId: string,
  quantity: number | null,
  note: string | null,
): Promise<GuestRequest> {
  const { data, error } = await supabase.rpc('create_guest_request', {
    p_token: token,
    p_request_type_id: requestTypeId,
    p_quantity: quantity,
    p_note: note,
  })
  if (error) throw error
  return data
}

export async function listMyRequests(token: string): Promise<GuestRequest[]> {
  const { data, error } = await supabase.rpc('list_my_requests', { p_token: token })
  if (error) throw error
  return data ?? []
}

export interface StayInfo {
  room_number: string
  guest_last_name: string
  check_out_at: string
}

export async function getStayInfo(token: string): Promise<StayInfo | null> {
  const { data, error } = await supabase.rpc('guest_stay_info', { p_token: token })
  if (error) throw error
  return data?.[0] ?? null
}

export async function cancelMyRequest(token: string, requestId: string): Promise<GuestRequest> {
  const { data, error } = await supabase.rpc('cancel_my_request', {
    p_token: token,
    p_request_id: requestId,
  })
  if (error) throw error
  return data
}
