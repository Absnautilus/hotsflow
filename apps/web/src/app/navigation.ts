import { Boxes, CalendarDays, Home, Hotel, Settings, Users, Wrench } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

export type ShellNavItem = {
  label: string
  path: string
  icon: LucideIcon
  kind: 'platform' | 'module'
}

export const shellNavigation: ShellNavItem[] = [
  { label: 'Home', path: '/', icon: Home, kind: 'platform' },
  { label: 'Housekeeping', path: '/housekeeping', icon: Hotel, kind: 'module' },
  { label: 'Turni', path: '/turni', icon: CalendarDays, kind: 'module' },
  { label: 'Transfer', path: '/transfer', icon: Wrench, kind: 'module' },
  { label: 'Moduli', path: '/modules', icon: Boxes, kind: 'platform' },
  { label: 'Team', path: '/team', icon: Users, kind: 'platform' },
  { label: 'Impostazioni', path: '/settings', icon: Settings, kind: 'platform' },
]
