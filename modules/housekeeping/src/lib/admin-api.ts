import { supabase } from '@/lib/supabase'
import { hotelFilter } from '@/lib/hotel-query-scope'
import type { Department, StaffDepartment, StaffRole } from '@/lib/types'

export interface Room {
  id: string
  room_number: string
  active: boolean
}

export async function listRooms(hotelId: string): Promise<Room[]> {
  const query = supabase.from('rooms').select('id, room_number, active').order('room_number')
  const { data, error } = await query.eq(...hotelFilter(hotelId))
  if (error) throw error
  return data ?? []
}

export async function createRoom(roomNumber: string): Promise<void> {
  const { error } = await supabase.from('rooms').insert({ room_number: roomNumber })
  if (error) throw error
}

export async function setRoomActive(id: string, active: boolean): Promise<void> {
  const { data, error } = await supabase.from('rooms').update({ active }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('room_active_update_not_applied')
}

// stays.room_id has a plain foreign key with no ON DELETE clause, so Postgres
// rejects (23503) deleting a room that any stay -- current or historical --
// still references. That's the intended guardrail: a room with usage
// history should be deactivated, not deleted.
export async function deleteRoom(id: string): Promise<void> {
  const { data, error } = await supabase.from('rooms').delete().eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('room_delete_not_applied')
}

export interface Hotel {
  id: string
  name: string
}

export async function listHotels(): Promise<Hotel[]> {
  const { data, error } = await supabase.from('hotels').select('id, name').order('name')
  if (error) throw error
  return data ?? []
}

export interface OperatorSummary {
  id: string
  name: string
  role: StaffRole
  department: StaffDepartment | null
  login_username: string | null
  active: boolean
}

// hotelId scopes the roster to a single hotel -- required by embedded mode,
// where the shell has already selected one property and a master's RLS-wide
// read access must not leak other properties' rosters into that view.
// Standalone mode omits it deliberately: a master there manages every hotel
// from one screen, which is the existing, intended standalone behavior.
export async function listStaff(hotelId?: string): Promise<OperatorSummary[]> {
  const query = supabase
    .from('staff_profiles')
    .select('id, name, role, department, login_username, active')
    .order('name')
  const { data, error } = await (hotelId ? query.eq(...hotelFilter(hotelId)) : query)
  if (error) throw error
  return data ?? []
}

export async function setStaffActive(id: string, active: boolean): Promise<void> {
  const { data, error } = await supabase.from('staff_profiles').update({ active }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('staff_active_update_not_applied')
}

export async function createStaffAccount(
  input:
    | { name: string; role: 'admin'; email: string; password: string; hotelId: string }
    | { name: string; role: 'operatore'; username: string; pin: string; department: StaffDepartment; hotelId?: string },
): Promise<void> {
  const { error } = await supabase.functions.invoke('create-staff-account', { body: input })
  if (error) throw error
}

export interface RequestTypeAdmin {
  id: string
  category_id: string
  name: string
  name_i18n: Record<string, string>
  description: string | null
  description_i18n: Record<string, string>
  allows_quantity: boolean
  available_quantity: number | null
  active: boolean
  sort_order: number
}

export interface RequestCategoryAdmin {
  id: string
  name: string
  name_i18n: Record<string, string>
  department: Department
  active: boolean
}

export async function listMenu(hotelId: string): Promise<{ categories: RequestCategoryAdmin[]; types: RequestTypeAdmin[] }> {
  const categoriesRes = await supabase
    .from('request_categories')
    .select('id, name, name_i18n, department, active')
    .order('sort_order')
    .eq(...hotelFilter(hotelId))
  if (categoriesRes.error) throw categoriesRes.error
  const categories = categoriesRes.data ?? []
  if (categories.length === 0) return { categories, types: [] }

  const typesRes = await supabase
    .from('request_types')
    .select('*')
    .in('category_id', categories.map((category) => category.id))
    .order('sort_order')
  if (typesRes.error) throw typesRes.error
  return { categories, types: typesRes.data ?? [] }
}

export async function createRequestCategory(input: { name: string; department: Department }): Promise<void> {
  const { error } = await supabase.from('request_categories').insert({ name: input.name, department: input.department })
  if (error) throw error
}

export async function setRequestCategoryActive(id: string, active: boolean): Promise<void> {
  const { data, error } = await supabase.from('request_categories').update({ active }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('request_category_active_update_not_applied')
}

export async function updateRequestCategoryTranslations(id: string, name_i18n: Record<string, string>): Promise<void> {
  const { error } = await supabase.from('request_categories').update({ name_i18n }).eq('id', id)
  if (error) throw error
}

export async function updateRequestTypeTranslations(
  id: string,
  translations: { name_i18n: Record<string, string>; description_i18n: Record<string, string> },
): Promise<void> {
  const { error } = await supabase.from('request_types').update(translations).eq('id', id)
  if (error) throw error
}

export async function createRequestType(input: {
  categoryId: string
  name: string
  description: string | null
  allowsQuantity: boolean
  availableQuantity: number | null
}): Promise<void> {
  const { error } = await supabase.from('request_types').insert({
    category_id: input.categoryId,
    name: input.name,
    description: input.description,
    allows_quantity: input.allowsQuantity,
    available_quantity: input.availableQuantity,
  })
  if (error) throw error
}

export async function setRequestTypeActive(id: string, active: boolean): Promise<void> {
  const { data, error } = await supabase.from('request_types').update({ active }).eq('id', id).select('id').maybeSingle()
  if (error) throw error
  if (!data) throw new Error('request_type_active_update_not_applied')
}

export interface DepartmentStat {
  department: Department
  count: number
  avgMinutes: number
}

export interface OperatorStat {
  staffId: string
  name: string
  count: number
  avgExecMinutes: number
}

export interface StatsSummary {
  overallCount: number
  overallAvgMinutes: number | null
  // "resolution time" (created -> completed) splits into two very
  // different things: how long a request sat waiting for someone to claim
  // it (created -> accepted, nobody's fault in particular — it's a
  // staffing/coverage question) versus how fast the person who claimed it
  // actually finished (accepted -> completed, an individual execution-speed
  // question). Rows with no accepted_at (e.g. completed via a path that
  // skipped claiming) are excluded from these two and from byOperator, but
  // still count toward overallCount/overallAvgMinutes.
  overallAvgWaitMinutes: number | null
  overallAvgExecMinutes: number | null
  byDepartment: DepartmentStat[]
  byOperator: OperatorStat[]
}

// All-time, computed client-side over every completed row — small enough at
// hotel scale that a dedicated aggregate query/materialized view isn't
// worth the added moving part yet.
export async function fetchCompletionStats(hotelId: string): Promise<StatsSummary> {
  const { data, error } = await supabase
    .from('guest_requests')
    .select('assigned_department, created_at, accepted_at, completed_at, accepted_by, accepted_by_staff:staff_profiles!accepted_by(name)')
    .eq(...hotelFilter(hotelId))
    .eq('status', 'completed')
    .not('completed_at', 'is', null)
  if (error) throw error
  const rows = (data ?? []) as unknown as {
    assigned_department: Department
    created_at: string
    accepted_at: string | null
    completed_at: string
    accepted_by: string | null
    accepted_by_staff: { name: string } | null
  }[]
  if (rows.length === 0) {
    return { overallCount: 0, overallAvgMinutes: null, overallAvgWaitMinutes: null, overallAvgExecMinutes: null, byDepartment: [], byOperator: [] }
  }

  const minutesBetween = (from: string, to: string) => (new Date(to).getTime() - new Date(from).getTime()) / 60_000
  const totalMinutesFor = (r: (typeof rows)[number]) => minutesBetween(r.created_at, r.completed_at)
  const avg = (values: number[]) => values.reduce((a, b) => a + b, 0) / values.length

  const overallAvgMinutes = avg(rows.map(totalMinutesFor))

  const withAcceptance = rows.filter((r): r is typeof r & { accepted_at: string } => r.accepted_at !== null)
  const overallAvgWaitMinutes = withAcceptance.length > 0 ? avg(withAcceptance.map((r) => minutesBetween(r.created_at, r.accepted_at))) : null
  const overallAvgExecMinutes = withAcceptance.length > 0 ? avg(withAcceptance.map((r) => minutesBetween(r.accepted_at, r.completed_at))) : null

  const byDeptGroups = new Map<Department, number[]>()
  for (const r of rows) {
    const list = byDeptGroups.get(r.assigned_department) ?? []
    list.push(totalMinutesFor(r))
    byDeptGroups.set(r.assigned_department, list)
  }
  const byDepartment = Array.from(byDeptGroups.entries())
    .map(([department, minutes]) => ({ department, count: minutes.length, avgMinutes: avg(minutes) }))
    .sort((a, b) => b.avgMinutes - a.avgMinutes)

  const byOperatorGroups = new Map<string, { name: string; minutes: number[] }>()
  for (const r of withAcceptance) {
    if (!r.accepted_by) continue
    const entry = byOperatorGroups.get(r.accepted_by) ?? { name: r.accepted_by_staff?.name ?? '—', minutes: [] }
    entry.minutes.push(minutesBetween(r.accepted_at, r.completed_at))
    byOperatorGroups.set(r.accepted_by, entry)
  }
  const byOperator = Array.from(byOperatorGroups.entries())
    .map(([staffId, { name, minutes }]) => ({ staffId, name, count: minutes.length, avgExecMinutes: avg(minutes) }))
    .sort((a, b) => a.avgExecMinutes - b.avgExecMinutes)

  return { overallCount: rows.length, overallAvgMinutes, overallAvgWaitMinutes, overallAvgExecMinutes, byDepartment, byOperator }
}

export interface ItemAvailability {
  requestTypeId: string
  name: string
  name_i18n: Record<string, string>
  categoryName: string
  categoryName_i18n: Record<string, string>
  totalQuantity: number
  activeCount: number
  remaining: number
  rooms: string[]
}

// "Remaining" for a trackable item (available_quantity set) = the total
// minus whatever is either still an open request (reserved but not yet
// delivered) or delivered-and-completed but not yet marked returned (see
// 0016_item_return_tracking.sql — returned_at is set explicitly by staff,
// or automatically when the guest's stay ends).
export async function fetchItemAvailability(hotelId: string): Promise<ItemAvailability[]> {
  const query = supabase
    .from('request_types')
    .select('id, name, name_i18n, available_quantity, request_categories!inner(name, name_i18n, hotel_id)')
    .not('available_quantity', 'is', null)
    .eq('active', true)
  const { data: types, error: typesError } = await query.eq(...hotelFilter(hotelId, 'request_categories.hotel_id'))
  if (typesError) throw typesError
  const typeList = (types ?? []) as unknown as {
    id: string
    name: string
    name_i18n: Record<string, string>
    available_quantity: number
    request_categories: { name: string; name_i18n: Record<string, string> } | null
  }[]
  if (typeList.length === 0) return []

  const ids = typeList.map((t) => t.id)
  const { data: active, error: activeError } = await supabase
    .from('guest_requests')
    .select('request_type_id, room_number')
    .eq(...hotelFilter(hotelId))
    .in('request_type_id', ids)
    .or('status.in.(requested,in_progress),and(status.eq.completed,returned_at.is.null)')
  if (activeError) throw activeError

  const byType = new Map<string, string[]>()
  for (const r of active ?? []) {
    const list = byType.get(r.request_type_id) ?? []
    list.push(r.room_number)
    byType.set(r.request_type_id, list)
  }

  return typeList.map((t) => {
    const rooms = byType.get(t.id) ?? []
    return {
      requestTypeId: t.id,
      name: t.name,
      name_i18n: t.name_i18n,
      categoryName: t.request_categories?.name ?? '',
      categoryName_i18n: t.request_categories?.name_i18n ?? {},
      totalQuantity: t.available_quantity,
      activeCount: rooms.length,
      remaining: Math.max(0, t.available_quantity - rooms.length),
      rooms,
    }
  })
}

export type PmsMode = 'manual' | 'opera'

export interface PmsIntegrationStatus {
  hotel_id: string
  mode: PmsMode
  ohip_hotel_code: string | null
  ohip_enterprise_id: string | null
  ohip_gateway_url: string | null
  has_credentials: boolean
  last_sync_at: string | null
  last_sync_status: 'success' | 'error' | null
  last_sync_error: string | null
}

export async function getPmsIntegrationStatus(hotelId?: string): Promise<PmsIntegrationStatus> {
  const { data, error } = await supabase.rpc('get_pms_integration_status', { p_hotel_id: hotelId ?? null })
  if (error) throw error
  const row = data?.[0]
  if (!row) throw new Error('missing_status')
  return row as PmsIntegrationStatus
}

export async function savePmsIntegration(input: {
  hotelId?: string
  mode: PmsMode
  ohipHotelCode: string
  ohipEnterpriseId: string
  ohipGatewayUrl: string
  ohipClientId: string | null
  ohipClientSecret: string | null
  ohipAppKey: string | null
}): Promise<void> {
  const { error } = await supabase.rpc('save_pms_integration', {
    p_hotel_id: input.hotelId ?? null,
    p_mode: input.mode,
    p_ohip_hotel_code: input.ohipHotelCode || null,
    p_ohip_enterprise_id: input.ohipEnterpriseId || null,
    p_ohip_gateway_url: input.ohipGatewayUrl || null,
    p_ohip_client_id: input.ohipClientId || null,
    p_ohip_client_secret: input.ohipClientSecret || null,
    p_ohip_app_key: input.ohipAppKey || null,
  })
  if (error) throw error
}

export interface PmsSyncResult {
  ok: boolean
  created?: number
  updated?: number
  error?: string
}

export async function triggerPmsSync(hotelId?: string): Promise<PmsSyncResult> {
  const { data, error } = await supabase.functions.invoke('sync-pms-stays', { body: { hotelId } })
  if (error) throw error
  return data as PmsSyncResult
}
