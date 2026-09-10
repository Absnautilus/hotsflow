import { useEffect, useRef, useState } from 'react'
import { UI_SCALES, useUiScale, type UiScale } from '@/lib/ui-scale-context'
import { useLocale } from '@/lib/i18n/locale-context'
import { cn } from '@/lib/cn'

const SCALE_KEY: Record<UiScale, 'uiScale.small' | 'uiScale.normal' | 'uiScale.large'> = {
  small: 'uiScale.small',
  normal: 'uiScale.normal',
  large: 'uiScale.large',
}

const SAMPLE_SIZE: Record<UiScale, string> = {
  small: 'text-xs',
  normal: 'text-base',
  large: 'text-xl',
}

export function TextSizeToggle({ dark = false, align = 'center' }: { dark?: boolean; align?: 'center' | 'right' } = {}) {
  const { t } = useLocale()
  const { scale, setScale } = useUiScale()
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
        aria-label={t('uiScale.label')}
        title={t('uiScale.label')}
        aria-expanded={open}
        className={cn(
          'flex h-11 w-11 cursor-pointer items-center justify-center rounded-full transition-colors',
          dark ? 'hover:bg-white/10' : 'border border-line shadow-sm hover:border-accent-soft-line',
        )}
      >
        <TextSizeIcon className="h-4.5 w-4.5" />
      </button>
      {open && (
        <div
          className={cn(
            'absolute z-10 mt-2 flex items-end gap-1 rounded-2xl border border-line bg-white p-1.5 shadow-lg',
            align === 'right' ? 'right-0' : 'left-1/2 -translate-x-1/2',
          )}
        >
          {UI_SCALES.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => {
                setScale(s)
                setOpen(false)
              }}
              aria-label={t(SCALE_KEY[s])}
              title={t(SCALE_KEY[s])}
              className={cn(
                'flex h-11 w-11 cursor-pointer items-center justify-center rounded-full font-bold text-foreground transition-colors hover:bg-surface-2',
                SAMPLE_SIZE[s],
                s === scale && 'bg-accent-soft text-accent ring-2 ring-accent',
              )}
            >
              A
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

// A big "A" next to a small "a" — the conventional "text size" glyph (same
// idea as the font-size control in Word/Docs), so it doesn't get mistaken
// for a general settings/gear icon.
function TextSizeIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden="true">
      <text x="1" y="18" fontSize="16" fontWeight="800" fill="currentColor">
        A
      </text>
      <text x="13" y="18" fontSize="9" fontWeight="800" fill="currentColor">
        A
      </text>
    </svg>
  )
}
