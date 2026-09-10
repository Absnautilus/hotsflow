import { Link, useLocation } from 'react-router-dom'
import type { SVGProps } from 'react'
import type { HousekeepingCapabilities } from '@/public/HousekeepingModule'
import { LogoMark } from '@/components/logo'
import { LanguageToggle } from '@/components/language-toggle'
import { TextSizeToggle } from '@/components/text-size-toggle'
import { NotificationSettingsToggle } from '@/components/notification-settings-toggle'
import { OnDutyToggle } from '@/staff/on-duty-toggle'
import { cn } from '@/lib/cn'
import { signOut } from '@/lib/staff-api'
import { useLocale } from '@/lib/i18n/locale-context'
import type { StaffProfile } from '@/lib/staff-types'

interface DashboardHeaderProps {
  profile: StaffProfile
  embedded?: boolean
  basePath?: string
  capabilities?: HousekeepingCapabilities
}

export function DashboardHeader({ profile, embedded = false, basePath = '/staff', capabilities }: DashboardHeaderProps) {
  const { t } = useLocale()
  const location = useLocation()
  const roleLabel = profile.role === 'master' ? t('role.master') : profile.role === 'admin' ? t('role.admin') : profile.department ? t(`department.${profile.department}`) : t('role.operatore')
  const legacyAdminLike = profile.role === 'admin' || profile.role === 'master'
  const staysAllowed = embedded && capabilities ? capabilities.staysView : legacyAdminLike || profile.department === 'reception'
  const manageAllowed = embedded && capabilities ? capabilities.manage : legacyAdminLike
  const initials = profile.name.trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase()

  const requestPath = basePath
  const staysPath = `${basePath}/soggiorni`
  const adminPath = `${basePath}/admin`

  if (embedded) {
    return (
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <nav className="flex w-fit gap-0.5 rounded-full bg-surface-2 p-[3px]" aria-label={t('staff.nav.requests')}>
          <TabLink to={requestPath} label={t('staff.nav.requests')} active={location.pathname === requestPath || location.pathname === `${requestPath}/`} />
          {staysAllowed && <TabLink to={staysPath} label={t('staff.nav.stays')} active={location.pathname.startsWith(staysPath)} />}
          {manageAllowed && <TabLink to={adminPath} label={t('staff.nav.admin')} active={location.pathname.startsWith(adminPath)} />}
        </nav>
        <div className="flex items-center gap-1">
          <OnDutyToggle profile={profile} dark={false} />
          <NotificationSettingsToggle align="right" />
          <TextSizeToggle align="right" />
          <LanguageToggle align="right" />
        </div>
      </div>
    )
  }

  return (
    <div className="bg-background px-3 pt-3 sm:px-6 sm:pt-4">
      <div className="mx-auto flex max-w-5xl items-center gap-1 rounded-full bg-accent py-1.5 pr-2 pl-3 text-white shadow-md">
        <Link to="/staff" className="flex shrink-0 items-center gap-2 rounded-full py-1.5 pr-2 hover:opacity-80">
          <LogoMark className="h-5 w-5 text-white" mouthColor="var(--accent)" />
          <span className="hidden font-head text-sm font-extrabold sm:inline">RoomCall</span>
        </Link>
        <div className="mx-1 hidden h-5 w-px shrink-0 bg-white/15 sm:block" />
        <nav className="flex shrink-0 items-center gap-0.5">
          <NavLink to={requestPath} label={t('staff.nav.requests')} icon={IconInbox} active={location.pathname === requestPath || location.pathname === `${requestPath}/`} />
          {staysAllowed && <NavLink to={staysPath} label={t('staff.nav.stays')} icon={IconBed} active={location.pathname.startsWith(staysPath)} />}
          {manageAllowed && <NavLink to={adminPath} label={t('staff.nav.admin')} icon={IconSettings} active={location.pathname.startsWith(adminPath)} />}
        </nav>
        <div className="flex-1" />
        <OnDutyToggle profile={profile} dark />
        <NotificationSettingsToggle dark align="right" />
        <TextSizeToggle dark align="right" />
        <LanguageToggle dark align="right" />
        <div className="mx-1 hidden h-5 w-px shrink-0 bg-white/15 sm:block" />
        <div className="hidden items-center gap-2 rounded-full bg-white/10 py-1 pr-3 pl-1 sm:flex">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white text-[0.625rem] font-bold text-accent">{initials}</span>
          <div className="leading-tight"><p className="text-[0.5625rem] font-bold tracking-wide text-white/50 uppercase">{roleLabel}</p><p className="truncate text-xs font-semibold">{profile.name}</p></div>
        </div>
        <button type="button" onClick={() => void signOut()} title={t('staff.nav.logout')} aria-label={t('staff.nav.logout')} className="flex h-11 w-11 shrink-0 cursor-pointer items-center justify-center rounded-full text-white/70 hover:bg-white/10 hover:text-white"><IconExit className="h-4 w-4" /></button>
      </div>
    </div>
  )
}

function TabLink({ to, label, active }: { to: string; label: string; active: boolean }) {
  return <Link to={to} className={cn('inline-flex min-h-11 items-center rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors', active ? 'bg-white text-foreground shadow-sm' : 'text-muted hover:text-foreground')}>{label}</Link>
}

function NavLink({ to, label, icon: Icon, active }: { to: string; label: string; icon: (props: SVGProps<SVGSVGElement>) => React.JSX.Element; active: boolean }) {
  return <Link to={to} title={label} className={cn('flex min-h-11 items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-bold transition-colors sm:px-3.5 sm:text-sm', active ? 'bg-white/15 text-white' : 'text-white/60 hover:bg-white/10 hover:text-white')}><Icon className="h-4 w-4 shrink-0" /><span className="hidden sm:inline">{label}</span></Link>
}

function IconInbox(props: SVGProps<SVGSVGElement>) { return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}><path d="M3 12h4l2 3h6l2-3h4" /><path d="M5.5 5h13L21 12v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6L5.5 5Z" /></svg> }
function IconBed(props: SVGProps<SVGSVGElement>) { return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}><path d="M3 18v-7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v7M3 18v2M21 18v2M3 14h18M7 11V9a2 2 0 0 1 2-2h1a2 2 0 0 1 2 2v2" /></svg> }
function IconSettings(props: SVGProps<SVGSVGElement>) { return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1.08-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1.08 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z" /></svg> }
function IconExit(props: SVGProps<SVGSVGElement>) { return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><path d="M16 17l5-5-5-5" /><path d="M21 12H9" /></svg> }
