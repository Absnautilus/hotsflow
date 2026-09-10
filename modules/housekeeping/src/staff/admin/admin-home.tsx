import { Link, Route, Routes, useLocation } from 'react-router-dom'
import { cn } from '@/lib/cn'
import { RoomsPage } from '@/staff/admin/rooms-page'
import { OperatorsPage } from '@/staff/admin/operators-page'
import { ItemsPage } from '@/staff/admin/items-page'
import { PmsIntegrationPage } from '@/staff/admin/pms-integration-page'
import { ArchivePage } from '@/staff/admin/archive-page'
import { StatsPage } from '@/staff/admin/stats-page'
import { AvailabilityPage } from '@/staff/admin/availability-page'
import { useLocale } from '@/lib/i18n/locale-context'
import type { StaffProfile } from '@/lib/staff-types'
import type { PlatformStaffManagementLink } from '@/public/HousekeepingModule'

interface AdminHomeProps {
  profile: StaffProfile
  basePath?: string
  embedded?: boolean
  platformStaffManagement?: PlatformStaffManagementLink
  /** Embedded mode only: scopes the operators roster to this hotel. */
  hotelId?: string
}

const moreLabels = {
  it: 'Altro',
  en: 'More',
  fr: 'Autres',
  de: 'Mehr',
  es: 'Más',
  pt: 'Mais',
  ja: 'その他',
  bn: 'আরও',
  hi: 'और',
  ar: 'المزيد',
  zh: '更多',
  ru: 'Ещё',
} as const

export function AdminHome({ profile, basePath = '/staff/admin', embedded = false, platformStaffManagement, hotelId }: AdminHomeProps) {
  const { t, locale } = useLocale()
  const location = useLocation()
  const primaryTabs = [
    { to: basePath, label: t('staff.admin.tabStaff'), match: (p: string) => p === basePath || p === `${basePath}/` },
    { to: `${basePath}/camere`, label: t('staff.admin.tabRooms'), match: (p: string) => p.startsWith(`${basePath}/camere`) },
    { to: `${basePath}/menu`, label: t('staff.admin.tabMenu'), match: (p: string) => p.startsWith(`${basePath}/menu`) },
    { to: `${basePath}/disponibilita`, label: t('staff.admin.tabAvailability'), match: (p: string) => p.startsWith(`${basePath}/disponibilita`) },
  ]
  const secondaryTabs = [
    { to: `${basePath}/statistiche`, label: t('staff.admin.tabStats'), match: (p: string) => p.startsWith(`${basePath}/statistiche`) },
    { to: `${basePath}/archivio`, label: t('staff.admin.tabArchive'), match: (p: string) => p.startsWith(`${basePath}/archivio`) },
    { to: `${basePath}/pms`, label: t('staff.admin.tabPms'), match: (p: string) => p.startsWith(`${basePath}/pms`) },
  ]
  const secondaryActive = secondaryTabs.some((tab) => tab.match(location.pathname))
  const operationalHotelId = hotelId ?? profile.hotel_id

  const routes = embedded ? (
    <Routes>
      <Route index element={<OperatorsPage profile={profile} platformStaffManagement={platformStaffManagement} hotelId={hotelId} />} />
      <Route path="camere" element={<RoomsPage hotelId={operationalHotelId} />} />
      <Route path="menu" element={<ItemsPage hotelId={operationalHotelId} />} />
      <Route path="disponibilita" element={<AvailabilityPage hotelId={operationalHotelId} />} />
      <Route path="statistiche" element={<StatsPage hotelId={operationalHotelId} />} />
      <Route path="archivio" element={<ArchivePage hotelId={operationalHotelId} />} />
      <Route path="pms" element={<PmsIntegrationPage profile={profile} />} />
    </Routes>
  ) : (
    <Routes>
      <Route path="/" element={<OperatorsPage profile={profile} />} />
      <Route path="/camere" element={<RoomsPage hotelId={operationalHotelId} />} />
      <Route path="/menu" element={<ItemsPage hotelId={operationalHotelId} />} />
      <Route path="/disponibilita" element={<AvailabilityPage hotelId={operationalHotelId} />} />
      <Route path="/statistiche" element={<StatsPage hotelId={operationalHotelId} />} />
      <Route path="/archivio" element={<ArchivePage hotelId={operationalHotelId} />} />
      <Route path="/pms" element={<PmsIntegrationPage profile={profile} />} />
    </Routes>
  )

  return (
    <div className="min-w-0">
      <nav
        className="mb-5 flex w-fit max-w-full items-start gap-1 rounded-md bg-surface-2 p-1"
        aria-label={t('staff.nav.admin')}
      >
        <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {primaryTabs.map((tab) => {
            const active = tab.match(location.pathname)
            return (
              <Link
                key={tab.to}
                to={tab.to}
                aria-current={active ? 'page' : undefined}
                className={cn('admin-tab', active && 'active')}
              >
                {tab.label}
              </Link>
            )
          })}
        </div>
        <details className="group relative shrink-0">
          <summary
            className={cn(
              'admin-tab flex cursor-pointer list-none items-center gap-1.5 [&::-webkit-details-marker]:hidden',
              secondaryActive && 'active',
            )}
          >
            {moreLabels[locale]}
            <svg
              viewBox="0 0 20 20"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.8"
              className="h-3.5 w-3.5 transition-transform group-open:rotate-180"
              aria-hidden="true"
            >
              <path d="m6 8 4 4 4-4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </summary>
          <div className="absolute right-0 z-30 mt-2 min-w-52 rounded-md border border-line bg-surface p-1.5 shadow-lg">
            {secondaryTabs.map((tab) => {
              const active = tab.match(location.pathname)
              return (
                <Link
                  key={tab.to}
                  to={tab.to}
                  aria-current={active ? 'page' : undefined}
                  className={cn(
                    'block rounded-sm px-3 py-2 text-sm font-semibold text-muted transition-colors hover:bg-surface-2 hover:text-foreground',
                    active && 'bg-accent-soft text-accent',
                  )}
                  onClick={(event) => event.currentTarget.closest('details')?.removeAttribute('open')}
                >
                  {tab.label}
                </Link>
              )
            })}
          </div>
        </details>
      </nav>
      {routes}
    </div>
  )
}
