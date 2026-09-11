import type { Department } from '@/lib/types'

export const REQUEST_STATUS = {
  REQUESTED: 'requested',
  IN_PROGRESS: 'in_progress',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
} as const

export type RequestStatus = (typeof REQUEST_STATUS)[keyof typeof REQUEST_STATUS]

export const REQUEST_STATUS_LABEL: Record<RequestStatus, string> = {
  requested: 'Richiesta',
  in_progress: 'In corso',
  completed: 'Completata',
  cancelled: 'Annullata',
}

export const DEPARTMENT_LABEL: Record<Department, string> = {
  reception: 'Reception',
  housekeeping: 'Housekeeping',
  maintenance: 'Maintenance',
  porter: 'Portineria',
}

export const DEPARTMENTS: Department[] = ['reception', 'housekeeping', 'maintenance', 'porter']
