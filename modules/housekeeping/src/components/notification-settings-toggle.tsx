import { useEffect, useRef, useState } from 'react'
import { getAlertVolume, playAlertSound, setAlertVolume, unlockAudio } from '@/lib/beep'
import { useLocale } from '@/lib/i18n/locale-context'
import { cn } from '@/lib/cn'

export function NotificationSettingsToggle({ dark = false, align = 'center' }: { dark?: boolean; align?: 'center' | 'right' } = {}) {
  const { t } = useLocale()
  const [open, setOpen] = useState(false)
  const [volume, setVolume] = useState(() => getAlertVolume())
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    function onClickOutside(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onClickOutside)
    return () => document.removeEventListener('mousedown', onClickOutside)
  }, [open])

  function onVolumeChange(next: number) {
    setVolume(next)
    setAlertVolume(next)
  }

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => {
          unlockAudio()
          setOpen((v) => !v)
        }}
        aria-label={t('staff.notifSettings.label')}
        title={t('staff.notifSettings.label')}
        aria-expanded={open}
        className={cn(
          'flex h-11 w-11 cursor-pointer items-center justify-center rounded-full transition-colors',
          dark ? 'hover:bg-white/10' : 'border border-line shadow-sm hover:border-accent-soft-line',
        )}
      >
        {volume > 0 ? <IconBell className="h-4.5 w-4.5" /> : <IconBellMuted className="h-4.5 w-4.5" />}
      </button>
      {open && (
        <div
          className={cn(
            'absolute z-10 mt-2 w-56 rounded-2xl border border-line bg-white p-3 text-foreground shadow-lg',
            align === 'right' ? 'right-0' : 'left-1/2 -translate-x-1/2',
          )}
        >
          <p className="mb-2 text-xs font-bold tracking-wide text-muted uppercase">{t('staff.notifSettings.volume')}</p>
          <div className="flex items-center gap-2">
            <IconBellMuted className="h-4 w-4 shrink-0 text-muted" />
            <input
              type="range"
              min={0}
              max={100}
              value={Math.round(volume * 100)}
              onChange={(e) => onVolumeChange(Number(e.target.value) / 100)}
              className="w-full accent-accent"
              aria-label={t('staff.notifSettings.volume')}
            />
            <IconBell className="h-4 w-4 shrink-0 text-muted" />
          </div>
          <button
            type="button"
            onClick={() => playAlertSound()}
            className="mt-3 min-h-11 w-full cursor-pointer rounded-full bg-surface-2 px-3 py-1.5 text-xs font-bold text-foreground transition-colors hover:bg-line-strong"
          >
            {t('staff.notifSettings.test')}
          </button>
        </div>
      )}
    </div>
  )
}

function IconBell({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M6 8a6 6 0 0 1 12 0c0 4.5 1.5 6 2 7H4c.5-1 2-2.5 2-7Z" />
      <path d="M10 20a2 2 0 0 0 4 0" />
    </svg>
  )
}

function IconBellMuted({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="M6 8a6 6 0 0 1 10.4-4M18 8c0 4.5 1.5 6 2 7H4c.5-1 2-2.5 2-7v-.5" />
      <path d="M10 20a2 2 0 0 0 4 0" />
      <path d="M3 3l18 18" />
    </svg>
  )
}
