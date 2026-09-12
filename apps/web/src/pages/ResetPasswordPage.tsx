import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../core/client'
import { PasswordField } from '../components/PasswordField'

// Reached only via the link in a Supabase password-reset email
// (resetPasswordForEmail's redirectTo). The Supabase client auto-exchanges
// the URL's recovery token for a session and fires PASSWORD_RECOVERY --
// deliberately outside ShellLayout/ModuleRuntimeContext, which assume a
// full signed-in profile+property and would otherwise misroute this
// transient recovery session before this page ever renders.
export function ResetPasswordPage() {
  const [ready, setReady] = useState<'checking' | 'ready' | 'invalid'>('checking')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') setReady('ready')
    })
    supabase.auth.getSession().then(({ data }) => {
      setReady((current) => (current === 'checking' ? (data.session ? 'ready' : 'invalid') : current))
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (password !== confirmPassword) { setError('Le due password non coincidono.'); return }
    setPending(true)
    setError(null)
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password })
      if (updateError) throw updateError
      setDone(true)
    } catch {
      setError('Non è stato possibile aggiornare la password. Il link potrebbe essere scaduto.')
      setPending(false)
    }
  }

  return (
    <main className="login-screen">
      <section className="login-card" aria-labelledby="reset-title">
        <div className="login-brand"><span className="mark">H</span><span>Homisuite</span></div>

        {ready === 'checking' && (
          <div className="login-copy"><p>Verifica del link in corso…</p></div>
        )}

        {ready === 'invalid' && (
          <>
            <div className="login-copy">
              <h1 id="reset-title">Link non valido</h1>
              <p>Il link è scaduto o non è più valido. Richiedi un nuovo link dalla pagina di accesso.</p>
            </div>
            <Link className="login-submit" to="/" style={{ display: 'grid', placeItems: 'center' }}>Torna al login</Link>
          </>
        )}

        {ready === 'ready' && !done && (
          <>
            <div className="login-copy">
              <h1 id="reset-title">Imposta una nuova password</h1>
              <p>Scegli una nuova password per il tuo account.</p>
            </div>
            <form className="login-form" onSubmit={submit}>
              <label>
                <span>Nuova password</span>
                <PasswordField required minLength={8} maxLength={72} autoComplete="new-password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus />
              </label>
              <label>
                <span>Conferma nuova password</span>
                <PasswordField required minLength={8} maxLength={72} autoComplete="new-password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} />
              </label>
              {error ? <p className="login-error" role="alert">{error}</p> : null}
              <button className="login-submit" type="submit" disabled={pending}>{pending ? 'Salvataggio…' : 'Aggiorna password'}</button>
            </form>
          </>
        )}

        {done && (
          <>
            <div className="login-copy">
              <h1 id="reset-title">Password aggiornata</h1>
              <p>La tua password è stata cambiata.</p>
            </div>
            <Link className="login-submit" to="/" style={{ display: 'grid', placeItems: 'center' }}>Continua</Link>
          </>
        )}
      </section>
    </main>
  )
}
