import { useState } from 'react'
import { goOffDuty, goOnDuty } from '@/lib/push'
import { useLocale } from '@/lib/i18n/locale-context'
import { cn } from '@/lib/cn'
import type { StaffProfile } from '@/lib/staff-types'

// Only operatori get push notifications about new requests (admin/master
// don't work a physical shift), so the toggle only appears for them. Keeps
// its own on_duty state seeded from the profile rather than bubbling changes
// up — nothing else in the dashboard needs to know the current value.
export function OnDutyToggle({ profile, dark = true }: { profile: StaffProfile; dark?: boolean }) {
  const { t } = useLocale()
  const [onDuty, setOnDuty] = useState(profile.on_duty)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (profile.role !== 'operatore') return null

  async function onClick() {
    setPending(true)
    setError(null)
    try {
      if (onDuty) {
        await goOffDuty()
        setOnDuty(false)
      } else {
        await goOnDuty(profile.id)
        setOnDuty(true)
      }
    } catch (err) {
      setError(err instanceof Error && err.message === 'permission_denied' ? t('staff.onDuty.permissionDenied') : t('staff.onDuty.error'))
    } finally {
      setPending(false)
    }
  }

  return (
    <div className="relative">
      <button
        type="button"
        onClick={onClick}
        disabled={pending}
        title={onDuty ? t('staff.onDuty.onTitle') : t('staff.onDuty.offTitle')}
        className={cn(
          'flex h-11 shrink-0 cursor-pointer items-center gap-1.5 rounded-full px-3 text-xs font-bold transition-colors disabled:cursor-not-allowed disabled:opacity-60',
          dark
            ? onDuty
              ? 'bg-white text-accent'
              : 'bg-white/10 text-white/70 hover:bg-white/15'
            : onDuty
              ? 'bg-accent-soft text-accent'
              : 'bg-surface-2 text-muted hover:bg-line',
        )}
      >
        <span className={cn('h-2 w-2 shrink-0 rounded-full', onDuty ? 'bg-ok-ink' : dark ? 'bg-white/40' : 'bg-line-strong')} />
        <span className="hidden sm:inline">{onDuty ? t('staff.onDuty.on') : t('staff.onDuty.off')}</span>
      </button>
      {error && (
        <div className="absolute top-full right-0 z-10 mt-2 w-48 rounded-lg border border-bad-ink/25 bg-bad-bg p-2 text-xs text-bad-ink shadow-lg">
          {error}
        </div>
      )}
    </div>
  )
}
