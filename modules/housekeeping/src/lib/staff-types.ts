import type { GuestRequest, StaffDepartment, StaffRole } from '@/lib/types'

export interface StaffProfile {
  id: string
  hotel_id: string
  auth_user_id: string
  name: string
  role: StaffRole
  department: StaffDepartment | null
  active: boolean
  on_duty: boolean
}

export interface QueuedRequest extends GuestRequest {
  request_types: {
    name: string
    name_i18n: Record<string, string>
    allows_quantity: boolean
    available_quantity: number | null
    request_categories: { name: string; name_i18n: Record<string, string> } | null
  } | null
  accepted_by_staff: { name: string } | null
}
