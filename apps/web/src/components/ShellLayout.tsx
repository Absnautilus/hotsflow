import { useEffect, useRef, useState } from 'react'
import { ArrowLeft, Menu, X } from 'lucide-react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { shellNavigation } from '../app/navigation'
import { useModuleRuntime } from '../core/ModuleRuntimeContext'
import { useHousekeepingAccess } from '../modules/housekeeping/useHousekeepingAccess'
import { LoginScreen } from './LoginScreen'
import { PropertySwitcher } from './PropertySwitcher'
import { AccountMenu } from './AccountMenu'

const moduleSlugByPath: Record<string, string> = {
  '/housekeeping': 'guest_requests',
  '/turni': 'shifts',
  '/transfer': 'transfers',
}

export function ShellLayout() {
  const runtime = useModuleRuntime()
  // Called unconditionally, ahead of the runtime.status early returns below,
  // to satisfy the rules of hooks -- its own loading/error states resolve to
  // "not compatible yet" and simply keep Housekeeping out of nav until known.
  const housekeepingAccess = useHousekeepingAccess()
  const location = useLocation()
  const [drawerOpen, setDrawerOpen] = useState(false)
  const drawerRef = useRef<HTMLDivElement>(null)
  const enabledSlugs = new Set(runtime.entitlements.filter((item) => item.enabled).map((item) => item.slug))
  // Housekeeping needs an extra check beyond "entitled": a property can be
  // entitled without being bridged to a legacy hotel, or the current user
  // can lack an operational profile at the bridged hotel -- both are dead
  // ends once inside the module, so the nav entry stays hidden until
  // useHousekeepingAccess confirms an actually-usable profile exists.
  const modules = shellNavigation.filter((item) => {
    if (item.kind !== 'module') return false
    if (!enabledSlugs.has(moduleSlugByPath[item.path])) return false
    if (item.path === '/housekeeping') return housekeepingAccess.status === 'compatible'
    return true
  })
  const home = shellNavigation.find((item) => item.path === '/')
  const platform = shellNavigation.filter((item) => item.kind === 'platform' && item.path !== '/')
  const activeModule = modules.find((item) => location.pathname === item.path || location.pathname.startsWith(`${item.path}/`))

  useEffect(() => {
    if (!drawerOpen) return
    const previous = document.activeElement as HTMLElement | null
    const firstButton = drawerRef.current?.querySelector<HTMLElement>('button, a[href]')
    firstButton?.focus()

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') setDrawerOpen(false)
    }
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('keydown', onKeyDown)
      previous?.focus()
    }
  }, [drawerOpen])

  if (runtime.status === 'loading') return <main className="runtime-state">Caricamento Hotsflow…</main>
  if (runtime.status === 'signed-out') return <LoginScreen />
  if (runtime.status === 'no-property') return <main className="runtime-state">Nessuna struttura accessibile.</main>
  if (runtime.status === 'error') return <main className="runtime-state"><strong>Impossibile caricare Hotsflow.</strong><button type="button" onClick={() => void runtime.refresh()}>Riprova</button></main>

  const displayName = runtime.profile?.fullName ?? 'Staff'

  const navSections = (
    <>
      {home && (
        <NavLink className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`} to={home.path} end onClick={() => setDrawerOpen(false)}>
          <home.icon size={18} /><span>{home.label}</span>
        </NavLink>
      )}
      <div className="nav-section-label">Moduli</div>
      {modules.map((item) => (
        <NavLink className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`} key={item.path} to={item.path} onClick={() => setDrawerOpen(false)}>
          <item.icon size={18} /><span>{item.label}</span>
        </NavLink>
      ))}
      <div className="nav-section-label platform">Piattaforma</div>
      {platform.map((item) => (
        <NavLink className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`} key={item.path} to={item.path} onClick={() => setDrawerOpen(false)}>
          <item.icon size={18} /><span>{item.label}</span>
        </NavLink>
      ))}
    </>
  )

  const brandMark = <div className="brand"><span className="mark">H</span><span>Hotsflow</span></div>

  const propertySwitcher = (
    <PropertySwitcher
      current={runtime.property ? { id: runtime.property.id, name: runtime.property.name } : null}
      properties={runtime.properties.map((property) => ({ id: property.id, name: property.name }))}
      staffLabel={displayName}
      onSelect={(propertyId) => runtime.selectProperty(propertyId)}
    />
  )

  return (
    <div className="app-shell">
      <aside className="sidebar">
        {brandMark}
        {propertySwitcher}
        <nav className="sidebar-nav" aria-label="Navigazione principale">{navSections}</nav>
        <div className="sidebar-account"><AccountMenu name={displayName} /></div>
      </aside>

      <div className="shell-content">
        {activeModule ? (
          <header className="mobile-header mobile-header-module">
            <Link to="/" aria-label="Torna alla Home" className="mobile-back"><ArrowLeft size={19} /><span>{activeModule.label}</span></Link>
            <button type="button" aria-label="Apri menu" onClick={() => setDrawerOpen(true)}><Menu size={20} /></button>
          </header>
        ) : (
          <header className="mobile-header">
            <div>{brandMark}<small>{runtime.property?.name}</small></div>
            <button type="button" aria-label="Apri menu" onClick={() => setDrawerOpen(true)}><Menu size={20} /></button>
          </header>
        )}
        <main className="page-content"><Outlet /></main>
      </div>

      {!activeModule && (
        <nav className="mobile-nav" aria-label="Navigazione mobile">
          {[shellNavigation[0], ...modules.slice(0, 3)].map((item) => (
            <NavLink className={({ isActive }) => `mobile-nav-item${isActive ? ' active' : ''}`} key={item.path} to={item.path}>
              <item.icon size={19} /><span>{item.label}</span>
            </NavLink>
          ))}
        </nav>
      )}

      {drawerOpen && (
        <div className="drawer-scrim" onClick={() => setDrawerOpen(false)}>
          <div ref={drawerRef} className="drawer-panel" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="Menu">
            <div className="drawer-header">
              {brandMark}
              <button type="button" aria-label="Chiudi menu" onClick={() => setDrawerOpen(false)}><X size={20} /></button>
            </div>
            {propertySwitcher}
            <nav className="sidebar-nav" aria-label="Navigazione principale">{navSections}</nav>
            <div className="drawer-account"><AccountMenu name={displayName} /></div>
          </div>
        </div>
      )}
    </div>
  )
}
