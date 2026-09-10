import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { FieldError, FieldGroup, Input, Label } from '@/components/ui/field'
import { LanguageToggle } from '@/components/language-toggle'
import { TextSizeToggle } from '@/components/text-size-toggle'
import { LogoMark } from '@/components/logo'
import { signIn, signInOperator } from '@/lib/staff-api'
import { useLocale } from '@/lib/i18n/locale-context'
import { cn } from '@/lib/cn'

type Mode = 'operator' | 'email'

export function StaffLogin() {
  const { t } = useLocale()
  const [mode, setMode] = useState<Mode>('operator')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [username, setUsername] = useState('')
  const [pin, setPin] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setPending(true)
    try {
      if (mode === 'operator') {
        await signInOperator(username.trim(), pin)
      } else {
        await signIn(email.trim(), password)
      }
    } catch {
      setError(mode === 'operator' ? t('staff.login.errorOperator') : t('staff.login.errorEmail'))
    } finally {
      setPending(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm">
        <div className="rounded-lg border border-line bg-surface p-9 shadow-md">
          <div className="mx-auto mb-4 flex h-[50px] w-[50px] items-center justify-center rounded-md bg-accent text-accent-ink shadow-[0_8px_20px_-6px_var(--accent)]">
            <LogoMark className="h-6 w-6" mouthColor="#fff" />
          </div>
          <div className="text-center text-[0.625rem] font-extrabold uppercase tracking-wider text-accent">{t('staff.login.badge')}</div>
          <h1 className="text-center font-head text-[1.1875rem] font-extrabold text-foreground">{t('staff.login.title')}</h1>
          <p className="mx-auto mt-1.5 max-w-[230px] text-center text-xs leading-relaxed text-muted">{t('staff.login.subtitle')}</p>

          <div className="mt-6 flex gap-0.5 rounded-full bg-surface-2 p-[3px]">
            <ModeButton active={mode === 'operator'} onClick={() => setMode('operator')}>
              {t('staff.login.modeOperator')}
            </ModeButton>
            <ModeButton active={mode === 'email'} onClick={() => setMode('email')}>
              {t('staff.login.modeEmail')}
            </ModeButton>
          </div>

          <div className="mt-5">
            <form onSubmit={onSubmit} className="flex flex-col gap-3.5">
              {mode === 'operator' ? (
                <>
                  <FieldGroup>
                    <Label htmlFor="username" required>
                      {t('staff.login.username')}
                    </Label>
                    <Input id="username" autoComplete="username" required value={username} onChange={(e) => setUsername(e.target.value)} />
                  </FieldGroup>
                  <FieldGroup>
                    <Label htmlFor="pin" required>
                      {t('staff.login.pin')}
                    </Label>
                    <Input
                      id="pin"
                      type="password"
                      inputMode="numeric"
                      pattern="[0-9]{6}"
                      maxLength={6}
                      autoComplete="current-password"
                      required
                      value={pin}
                      onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    />
                  </FieldGroup>
                </>
              ) : (
                <>
                  <FieldGroup>
                    <Label htmlFor="email" required>
                      {t('staff.login.email')}
                    </Label>
                    <Input id="email" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} />
                  </FieldGroup>
                  <FieldGroup>
                    <Label htmlFor="password" required>
                      {t('staff.login.password')}
                    </Label>
                    <Input
                      id="password"
                      type="password"
                      autoComplete="current-password"
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                    />
                  </FieldGroup>
                </>
              )}
              <FieldError>{error ?? undefined}</FieldError>
              <Button type="submit" disabled={pending} className="mt-1 w-full">
                {pending ? t('staff.login.submitPending') : t('staff.login.submit')}
              </Button>
            </form>
          </div>
        </div>
        <p className="mt-6 text-center text-[0.71875rem] text-muted">
          {t('staff.login.guestPrompt')} <Link to="/g" className="font-semibold text-accent hover:underline">{t('staff.login.guestLink')}</Link>
        </p>
        <div className="mt-4 flex justify-center gap-2">
          <TextSizeToggle />
          <LanguageToggle />
        </div>
      </div>
    </div>
  )
}

function ModeButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex-1 cursor-pointer rounded-full px-3 py-1.5 text-[0.71875rem] font-bold transition-colors',
        active ? 'bg-accent text-accent-ink' : 'text-muted hover:text-foreground',
      )}
    >
      {children}
    </button>
  )
}
