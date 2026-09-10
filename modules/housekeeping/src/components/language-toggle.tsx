import { useEffect, useRef, useState } from 'react'
import { LOCALES } from '@/lib/i18n/locales'
import { useLocale } from '@/lib/i18n/locale-context'
import { FlagIcon } from '@/components/flag-icon'
import { cn } from '@/lib/cn'

export function LanguageToggle({ dark = false, align = 'center' }: { dark?: boolean; align?: 'center' | 'right' } = {}) {
  const { locale, setLocale } = useLocale()
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    function onClickOutside(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onClickOutside)
    return () => document.removeEventListener('mousedown', onClickOutside)
  }, [open])

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label="Lingua"
        aria-expanded={open}
        className={cn(
          'flex h-11 w-11 cursor-pointer items-center justify-center rounded-full transition-colors',
          dark ? 'hover:bg-white/10' : 'border border-line shadow-sm hover:border-accent-soft-line',
        )}
      >
        <FlagIcon code={locale} className="h-6 w-6" />
      </button>
      {open && (
        <div
          className={cn(
            'absolute z-10 mt-2 flex w-56 flex-wrap gap-1.5 rounded-2xl border border-line bg-white p-2 shadow-lg',
            align === 'right' ? 'right-0' : 'left-1/2 -translate-x-1/2',
          )}
        >
          {LOCALES.map((l) => (
            <button
              key={l.code}
              type="button"
              onClick={() => {
                setLocale(l.code)
                setOpen(false)
              }}
              aria-label={l.label}
              title={l.label}
              className={cn(
                'flex h-11 w-11 cursor-pointer items-center justify-center rounded-full transition-transform hover:scale-110',
                l.code === locale && 'ring-2 ring-accent',
              )}
            >
              <FlagIcon code={l.code} className="h-7 w-7" />
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
