import { useEffect, useState, type FormEvent, type ReactNode } from 'react'
import { Bell, Building2, ChevronRight, Globe2, LockKeyhole, Puzzle, UserRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { LanguageToggle } from '../components/LanguageToggle'
import { Modal } from '../components/Modal'
import { GuestLinkRow } from '../components/GuestLinkRow'
import { NotificationsToggle } from '../components/NotificationsToggle'
import { PasswordField } from '../components/PasswordField'
import { Select } from '../components/Select'
import { core, supabase } from '../core/client'
import { useModuleRuntime } from '../core/ModuleRuntimeContext'
import { useHousekeepingAccess } from '../modules/housekeeping/useHousekeepingAccess'

export function SettingsPage() {
  const runtime = useModuleRuntime()
  const housekeepingAccess = useHousekeepingAccess()
  const propertyName = runtime.property?.name ?? 'Struttura'
  const profileName = runtime.profile?.fullName ?? 'Utente Hotsflow'
  const [language, setLanguage] = useState(() => localStorage.getItem('hotsflow.language') === 'en' ? 'en' : 'it')
  const [propertyOpen, setPropertyOpen] = useState(false)
  const [profileOpen, setProfileOpen] = useState(false)
  const [securityOpen, setSecurityOpen] = useState(false)
  const [canManageProperty, setCanManageProperty] = useState(false)

  useEffect(() => { void runtime.hasPermission('core.property.manage').then(setCanManageProperty).catch(() => setCanManageProperty(false)) }, [runtime.hasPermission])

  useEffect(() => {
    function syncLanguage(event: Event) {
      const next = (event as CustomEvent<string>).detail
      if (next === 'it' || next === 'en') setLanguage(next)
    }
    window.addEventListener('hotsflow:language-change', syncLanguage)
    return () => window.removeEventListener('hotsflow:language-change', syncLanguage)
  }, [])

  return (
    <div className="page-stack shell-page settings-page">
      <header className="page-heading">
        <p className="eyebrow">Hotsflow</p>
        <h1>Impostazioni</h1>
        <p>Preferenze della struttura, del tuo account e dei moduli.</p>
      </header>

      <section className="settings-section">
        <div className="settings-section-title"><Building2 size={18} /><div><h2>Struttura</h2><p>Configurazione condivisa di {propertyName}.</p></div></div>
        <div className="settings-list shell-card">
          <SettingRow title="Informazioni struttura" detail={`${propertyName} · ${runtime.property?.timezone ?? 'Fuso orario non impostato'}`} onClick={canManageProperty ? () => setPropertyOpen(true) : undefined} status={canManageProperty ? undefined : 'Permesso richiesto'} />
          <SettingRow title="Preferenze operative" detail="Fuso orario, formati e impostazioni comuni" status="Non ancora disponibile" muted />
          {canManageProperty && <GuestLinkRow />}
        </div>
      </section>

      <section className="settings-section" id="account">
        <div className="settings-section-title"><UserRound size={18} /><div><h2>Account</h2><p>Preferenze personali valide in tutta la suite.</p></div></div>
        <div className="settings-list shell-card">
          <SettingRow icon={<UserRound size={17} />} title="Profilo" detail={profileName} onClick={() => setProfileOpen(true)} />
          <div className="settings-row settings-row-control">
            <span className="settings-row-main"><span className="settings-row-icon"><Globe2 size={17} /></span><span><strong>Lingua</strong><small>{language === 'en' ? 'English' : 'Italiano'}</small></span></span>
            <LanguageToggle />
          </div>
          <div className="settings-row settings-row-control">
            <span className="settings-row-main"><span className="settings-row-icon"><Bell size={17} /></span><span><strong>Notifiche</strong><small>Preferenze globali</small></span></span>
            <NotificationsToggle />
          </div>
          <SettingRow icon={<LockKeyhole size={17} />} title="Sicurezza" detail="Cambia la password del tuo account" onClick={() => setSecurityOpen(true)} />
        </div>
      </section>

      <section className="settings-section">
        <div className="settings-section-title"><Puzzle size={18} /><div><h2>Impostazioni moduli</h2><p>Configurazioni specifiche, senza duplicare le preferenze globali.</p></div></div>
        <div className="settings-list shell-card">
          {housekeepingAccess.status === 'compatible' ? (
            <SettingRow title="Housekeeping" detail="Categorie, richieste e configurazione operativa" to="/housekeeping/admin/menu" />
          ) : (
            <SettingRow
              title="Housekeeping"
              detail="Categorie, richieste e configurazione operativa"
              status={housekeepingStatus(housekeepingAccess.status)}
              muted
            />
          )}
          <SettingRow title="Turni" detail="Disponibile dopo l'integrazione del modulo" status="Non ancora disponibile" muted />
          <SettingRow title="Transfer" detail="Disponibile dopo l'integrazione del modulo" status="Non ancora disponibile" muted />
        </div>
      </section>

      <PropertyModal open={propertyOpen} onClose={() => setPropertyOpen(false)} onSaved={async () => { setPropertyOpen(false); await runtime.refresh() }} />
      <ProfileModal open={profileOpen} onClose={() => setProfileOpen(false)} onSaved={async () => { setProfileOpen(false); await runtime.refresh() }} />
      <SecurityModal open={securityOpen} onClose={() => setSecurityOpen(false)} />
    </div>
  )
}

function housekeepingStatus(status: ReturnType<typeof useHousekeepingAccess>['status']): string {
  if (status === 'loading') return 'Verifica disponibilità…'
  if (status === 'not-entitled') return 'Non abilitato'
  if (status === 'no-mapping') return 'Non collegato'
  if (status === 'no-profile') return 'Profilo operativo richiesto'
  if (status === 'error') return 'Disponibilità non verificabile'
  return ''
}

type SettingRowProps = {
  title: string
  detail: string
  icon?: ReactNode
  muted?: boolean
  status?: string
  to?: string
  onClick?: () => void
}

function SettingRow({ title, detail, icon, muted = false, status, to, onClick }: SettingRowProps) {
  const content = (
    <>
      <span className="settings-row-main">{icon ? <span className="settings-row-icon">{icon}</span> : null}<span><strong>{title}</strong><small>{detail}</small></span></span>
      {to || onClick ? <ChevronRight size={17} /> : <span className="settings-row-status">{status}</span>}
    </>
  )

  if (to) return <Link className="settings-row" to={to}>{content}</Link>
  if (onClick) return <button className="settings-row" type="button" onClick={onClick}>{content}</button>
  return <div className={`settings-row settings-row-static${muted ? ' muted' : ''}`}>{content}</div>
}

function PropertyModal({ open, onClose, onSaved }: { open: boolean; onClose: () => void; onSaved: () => Promise<void> }) {
  const runtime = useModuleRuntime()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [timezone, setTimezone] = useState('Europe/Rome')
  useEffect(() => { if (open) { setSaving(false); setError(null); setTimezone(runtime.property?.timezone ?? 'Europe/Rome') } }, [open, runtime.property?.timezone])
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!runtime.property) return
    const form = new FormData(event.currentTarget)
    setSaving(true); setError(null)
    try {
      const checkInTime = String(form.get('checkInTime') ?? '').trim() || null
      const checkOutTime = String(form.get('checkOutTime') ?? '').trim() || null
      await core.updateProperty(runtime.property.id, {
        name: String(form.get('name')),
        timezone,
        settings: { ...runtime.property.settings, checkInTime, checkOutTime },
      })
      await onSaved()
    } catch { setError('Non è stato possibile aggiornare la struttura.'); setSaving(false) }
  }
  const checkInDefault = typeof runtime.property?.settings.checkInTime === 'string' ? runtime.property.settings.checkInTime : ''
  const checkOutDefault = typeof runtime.property?.settings.checkOutTime === 'string' ? runtime.property.settings.checkOutTime : ''
  return <Modal open={open} title="Informazioni struttura" description="Dati condivisi da tutti i moduli Hotsflow." onClose={onClose} footer={<><button className="btn btn-secondary" type="button" onClick={onClose}>Annulla</button><button className="btn btn-primary" type="submit" form="property-form" disabled={saving}>{saving ? 'Salvataggio…' : 'Salva'}</button></>}>
    <form className="modal-form" id="property-form" onSubmit={submit}>
      <label className="form-field"><span>Nome struttura</span><input name="name" required minLength={2} maxLength={120} defaultValue={runtime.property?.name} /></label>
      <label className="form-field" htmlFor="property-timezone"><span>Fuso orario</span><Select id="property-timezone" name="timezone" value={timezone} onChange={setTimezone}><option value="Europe/Rome">Europa — Roma</option><option value="Europe/London">Europa — Londra</option><option value="Europe/Amsterdam">Europa — Amsterdam</option><option value="America/Mexico_City">America — Città del Messico</option><option value="America/New_York">America — New York</option></Select></label>
      <label className="form-field"><span>Orario check-in predefinito</span><input name="checkInTime" type="time" defaultValue={checkInDefault} /></label>
      <label className="form-field"><span>Orario check-out predefinito</span><input name="checkOutTime" type="time" defaultValue={checkOutDefault} /></label>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
    </form>
  </Modal>
}

function ProfileModal({ open, onClose, onSaved }: { open: boolean; onClose: () => void; onSaved: () => Promise<void> }) {
  const runtime = useModuleRuntime()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { if (open) { setSaving(false); setError(null) } }, [open])
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = new FormData(event.currentTarget); setSaving(true); setError(null)
    try {
      await core.updateCurrentProfile({ fullName: String(form.get('name')), avatarUrl: String(form.get('avatar')).trim() || null })
      await onSaved()
    } catch { setError('Non è stato possibile aggiornare il profilo.'); setSaving(false) }
  }
  return <Modal open={open} title="Profilo" description="Questi dati sono visibili agli altri membri del team." onClose={onClose} footer={<><button className="btn btn-secondary" type="button" onClick={onClose}>Annulla</button><button className="btn btn-primary" type="submit" form="profile-form" disabled={saving}>{saving ? 'Salvataggio…' : 'Salva'}</button></>}>
    <form className="modal-form" id="profile-form" onSubmit={submit}>
      <label className="form-field"><span>Nome e cognome</span><input name="name" required minLength={2} maxLength={120} defaultValue={runtime.profile?.fullName} autoComplete="name" /></label>
      <label className="form-field"><span>Email account</span><input value={runtime.session?.user.email ?? ''} readOnly /></label>
      <label className="form-field"><span>URL immagine profilo (facoltativo)</span><input name="avatar" type="url" defaultValue={runtime.profile?.avatarUrl ?? ''} /></label>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
    </form>
  </Modal>
}

function SecurityModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const runtime = useModuleRuntime()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)
  useEffect(() => { if (open) { setSaving(false); setError(null); setDone(false) } }, [open])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const email = runtime.session?.user.email
    if (!email) { setError('Sessione non valida. Ricarica la pagina.'); return }
    const form = new FormData(event.currentTarget)
    const currentPassword = String(form.get('current'))
    const newPassword = String(form.get('next'))
    const confirmPassword = String(form.get('confirm'))
    if (newPassword !== confirmPassword) { setError('Le due password non coincidono.'); return }
    setSaving(true); setError(null)
    try {
      // Re-check the current password before changing it -- updateUser only
      // needs an active session, it wouldn't otherwise ask for it.
      const { error: reauthError } = await supabase.auth.signInWithPassword({ email, password: currentPassword })
      if (reauthError) { setError('Password attuale non corretta.'); setSaving(false); return }
      const { error: updateError } = await supabase.auth.updateUser({ password: newPassword })
      if (updateError) throw updateError
      setDone(true)
    } catch { setError('Non è stato possibile aggiornare la password.'); setSaving(false) }
  }

  if (done) {
    return <Modal open={open} title="Password aggiornata" description="Usa la nuova password dal prossimo accesso." onClose={onClose} footer={<button className="btn btn-primary" type="button" onClick={onClose}>Chiudi</button>}>
      <p>La password del tuo account è stata cambiata.</p>
    </Modal>
  }
  return <Modal open={open} title="Cambia password" description="Serve la password attuale per confermare l'identità." onClose={onClose} footer={<><button className="btn btn-secondary" type="button" onClick={onClose}>Annulla</button><button className="btn btn-primary" type="submit" form="security-form" disabled={saving}>{saving ? 'Salvataggio…' : 'Aggiorna'}</button></>}>
    <form className="modal-form" id="security-form" onSubmit={submit}>
      <label className="form-field"><span>Password attuale</span><PasswordField name="current" required autoComplete="current-password" /></label>
      <label className="form-field"><span>Nuova password</span><PasswordField name="next" required minLength={8} maxLength={72} autoComplete="new-password" /></label>
      <label className="form-field"><span>Conferma nuova password</span><PasswordField name="confirm" required minLength={8} maxLength={72} autoComplete="new-password" /></label>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
    </form>
  </Modal>
}
