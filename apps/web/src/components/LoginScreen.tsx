import { FormEvent, useState } from 'react'
import { Eye, EyeOff } from 'lucide-react'
import { supabase } from '../core/client'

type HelpView = 'closed' | 'menu' | 'email-form' | 'email-sent' | 'contact-admin'

export function LoginScreen() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [helpView, setHelpView] = useState<HelpView>('closed')
  const [resetEmail, setResetEmail] = useState('')
  const [resetPending, setResetPending] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (pending) return
    setPending(true)
    setError(null)

    const typed = email.trim()

    // A credentials-based team member only ever sees/types their plain
    // username (create-team-member-credentials's own design intent), never
    // the synthetic auth.users email it's derived from -- resolve it here
    // rather than asking them to type an address they were never shown in
    // full. A normal invited email (has an "@") skips resolution entirely.
    let loginEmail = typed
    if (!typed.includes('@')) {
      const { data: identifiers, error: resolveError } = await supabase.rpc('resolve_staff_login_identifier', {
        p_username: typed.toLowerCase(),
      })
      if (resolveError || !identifiers || identifiers.length === 0) {
        // Same message as a real wrong-password attempt below -- a bare
        // username that matches nothing must not be distinguishable from
        // one that does but has the wrong password.
        setError('Email o password non corretti.')
        setPending(false)
        return
      }
      if (identifiers.length > 1) {
        setError('Il tuo nome utente esiste in più strutture. Usa l’indirizzo completo fornito alla creazione dell’account, oppure contatta l’amministratore.')
        setPending(false)
        return
      }
      loginEmail = identifiers[0]
    }

    const { error: signInError } = await supabase.auth.signInWithPassword({ email: loginEmail, password })

    if (signInError) {
      setError(signInError.message === 'Invalid login credentials' ? 'Email o password non corretti.' : 'Accesso non riuscito. Riprova.')
      setPending(false)
    }
  }

  // Always lands on the same confirmation regardless of whether the address
  // is actually tied to an account -- resetPasswordForEmail itself never
  // reports "not found" either, on purpose, to avoid letting this form be
  // used to check which emails have an account.
  async function handleResetRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setResetPending(true)
    try {
      await supabase.auth.resetPasswordForEmail(resetEmail.trim(), {
        redirectTo: `${window.location.origin}/reimposta-password`,
      })
    } finally {
      setResetPending(false)
      setHelpView('email-sent')
    }
  }

  return (
    <main className="login-screen">
      <section className="login-card" aria-labelledby="login-title">
        <div className="login-brand"><img className="mark" src="/icon-192.png" alt="" width={28} height={28} /><span>Homisuite</span></div>
        <div className="login-copy">
          <p className="eyebrow">Workspace hotel</p>
          <h1 id="login-title">Bentornato</h1>
          <p>Accedi al tuo spazio di lavoro Homisuite.</p>
        </div>
        <form className="login-form" onSubmit={handleSubmit}>
          <label>
            <span>Email o identificativo</span>
            <input type="text" autoComplete="username" value={email} onChange={(event) => setEmail(event.target.value)} required autoFocus />
          </label>
          <label>
            <span>Password</span>
            <span className="password-field">
              <input type={showPassword ? 'text' : 'password'} autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required />
              <button type="button" aria-label={showPassword ? 'Nascondi password' : 'Mostra password'} onClick={() => setShowPassword((value) => !value)}>{showPassword ? <EyeOff size={17} /> : <Eye size={17} />}</button>
            </span>
          </label>
          {error ? <p className="login-error" role="alert">{error}</p> : null}
          <button className="login-submit" type="submit" disabled={pending}>{pending ? 'Accesso…' : 'Accedi'}</button>
        </form>

        <div className="login-help">
          {helpView === 'closed' && (
            <button type="button" className="login-help-toggle" onClick={() => setHelpView('menu')}>Problemi ad accedere?</button>
          )}
          {helpView === 'menu' && (
            <div className="login-help-panel">
              <button type="button" onClick={() => setHelpView('email-form')}>Ho dimenticato la password</button>
              <button type="button" onClick={() => setHelpView('contact-admin')}>Accedo con nome utente</button>
            </div>
          )}
          {helpView === 'email-form' && (
            <form className="login-help-panel" onSubmit={handleResetRequest}>
              <label>
                <span>Email dell'account</span>
                <input type="email" required value={resetEmail} onChange={(event) => setResetEmail(event.target.value)} autoFocus />
              </label>
              <button type="submit" disabled={resetPending}>{resetPending ? 'Invio…' : 'Invia link di reset'}</button>
              <button type="button" className="login-help-back" onClick={() => setHelpView('menu')}>Indietro</button>
            </form>
          )}
          {helpView === 'email-sent' && (
            <p className="login-help-panel">Se l'indirizzo è collegato a un account, riceverai a breve un'email con le istruzioni per reimpostare la password.</p>
          )}
          {helpView === 'contact-admin' && (
            <div className="login-help-panel">
              <p>Contatta l'amministratore della struttura.</p>
              <button type="button" className="login-help-back" onClick={() => setHelpView('menu')}>Indietro</button>
            </div>
          )}
        </div>
      </section>
    </main>
  )
}
