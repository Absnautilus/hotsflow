import { useEffect, useRef, useState } from 'react'
import { cn } from '@/lib/cn'
import { useLocale } from '@/lib/i18n/locale-context'
import type { Locale } from '@/lib/i18n/locales'

// Matches the Suite Design Standard's calendar spec exactly (.date-trigger /
// .cal-popover / .cal-grid) — built to replace the native
// <input type="datetime-local"> that renders as a different, OS-styled
// widget on every platform. Keeps the same "local wall-clock string" value
// shape (YYYY-MM-DDTHH:mm) as the native input it replaces, so callers don't
// need to change how they store or convert the value.

const INTL_LOCALE: Record<Locale, string> = {
  it: 'it-IT',
  en: 'en-US',
  fr: 'fr-FR',
  de: 'de-DE',
  es: 'es-ES',
  pt: 'pt-PT',
  ja: 'ja-JP',
  bn: 'bn-BD',
  hi: 'hi-IN',
  ar: 'ar-SA',
  zh: 'zh-CN',
  ru: 'ru-RU',
}

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

function parseLocalValue(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value)
  if (!match) return null
  const [, y, mo, d, h, mi] = match
  return new Date(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi))
}

function toLocalValue(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

// Monday-first 6x7 grid covering the full visible month.
function buildGrid(viewYear: number, viewMonth: number): Date[] {
  const first = new Date(viewYear, viewMonth, 1)
  const firstWeekday = (first.getDay() + 6) % 7 // 0 = Monday
  const start = new Date(viewYear, viewMonth, 1 - firstWeekday)
  return Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i))
}

function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

export function DateTimePicker({
  id,
  value,
  onChange,
  required,
}: {
  id?: string
  value: string
  onChange: (value: string) => void
  required?: boolean
}) {
  const { locale, t } = useLocale()
  const intlLocale = INTL_LOCALE[locale]
  const selected = parseLocalValue(value)
  const [open, setOpen] = useState(false)
  const [viewDate, setViewDate] = useState(() => selected ?? new Date())
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (selected) setViewDate(selected)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])

  useEffect(() => {
    if (!open) return
    function onClickOutside(e: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onClickOutside)
    return () => document.removeEventListener('mousedown', onClickOutside)
  }, [open])

  const today = new Date()
  const grid = buildGrid(viewDate.getFullYear(), viewDate.getMonth())
  const monthLabel = new Intl.DateTimeFormat(intlLocale, { month: 'long', year: 'numeric' }).format(viewDate)
  const weekdayLabels = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(2024, 0, i + 1) // a known Monday
    return new Intl.DateTimeFormat(intlLocale, { weekday: 'short' }).format(d)
  })

  function pickDay(day: Date) {
    const base = selected ?? new Date()
    onChange(toLocalValue(new Date(day.getFullYear(), day.getMonth(), day.getDate(), base.getHours(), base.getMinutes())))
  }

  function setHours(h: number) {
    const base = selected ?? new Date()
    onChange(toLocalValue(new Date(base.getFullYear(), base.getMonth(), base.getDate(), Math.max(0, Math.min(23, h)), base.getMinutes())))
  }

  function setMinutes(m: number) {
    const base = selected ?? new Date()
    onChange(toLocalValue(new Date(base.getFullYear(), base.getMonth(), base.getDate(), base.getHours(), Math.max(0, Math.min(59, m)))))
  }

  return (
    <div ref={rootRef} className="relative w-full">
      <button
        id={id}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex w-full cursor-pointer items-center justify-between gap-2 rounded-sm border border-line-strong bg-surface px-3 py-2 text-left text-sm text-foreground hover:border-muted"
      >
        <span className={selected ? undefined : 'text-muted'}>
          {selected ? new Intl.DateTimeFormat(intlLocale, { day: 'numeric', month: 'long', year: 'numeric' }).format(selected) : t('datePicker.placeholder')}
        </span>
        <IconCalendar className="h-4 w-4 shrink-0 text-muted" />
      </button>
      {required && <input tabIndex={-1} aria-hidden className="sr-only" required value={value} onChange={() => {}} />}

      {open && (
        <div className="absolute z-20 mt-2 w-[266px] rounded-md border border-line bg-surface p-3.5 pb-4 shadow-lg">
          <div className="mb-2.5 flex items-center justify-between">
            <button
              type="button"
              aria-label={t('datePicker.prevMonth')}
              onClick={() => setViewDate((d) => new Date(d.getFullYear(), d.getMonth() - 1, 1))}
              className="flex h-6 w-6 cursor-pointer items-center justify-center rounded-full text-muted hover:bg-surface-2 hover:text-foreground"
            >
              <IconChevronLeft className="h-3.5 w-3.5" />
            </button>
            <span className="font-head text-[0.8125rem] font-extrabold text-foreground capitalize">{monthLabel}</span>
            <button
              type="button"
              aria-label={t('datePicker.nextMonth')}
              onClick={() => setViewDate((d) => new Date(d.getFullYear(), d.getMonth() + 1, 1))}
              className="flex h-6 w-6 cursor-pointer items-center justify-center rounded-full text-muted hover:bg-surface-2 hover:text-foreground"
            >
              <IconChevronRight className="h-3.5 w-3.5" />
            </button>
          </div>

          <div className="grid grid-cols-7 gap-0.5">
            {weekdayLabels.map((label, i) => (
              <div key={i} className="pt-0 pb-1.5 text-center text-[0.5625rem] font-extrabold tracking-wide text-muted uppercase">
                {label}
              </div>
            ))}
            {grid.map((day, i) => {
              const inMonth = day.getMonth() === viewDate.getMonth()
              const isToday = sameDay(day, today)
              const isSelected = selected ? sameDay(day, selected) : false
              return (
                <button
                  key={i}
                  type="button"
                  onClick={() => pickDay(day)}
                  className={cn(
                    'flex aspect-square cursor-pointer items-center justify-center rounded-sm font-mono text-[0.71875rem] text-foreground/80 hover:bg-surface-2',
                    !inMonth && 'text-line-strong',
                    isToday && !isSelected && 'font-extrabold text-accent ring-[1.5px] ring-inset ring-accent',
                    isSelected && 'bg-accent font-bold text-accent-ink hover:bg-accent',
                  )}
                >
                  {day.getDate()}
                </button>
              )
            })}
          </div>

          <div className="mt-3 flex items-center justify-center gap-1.5 border-t border-line pt-3">
            <input
              value={selected ? pad(selected.getHours()) : '--'}
              onChange={(e) => {
                const n = Number(e.target.value.replace(/\D/g, '').slice(-2))
                if (!Number.isNaN(n)) setHours(n)
              }}
              inputMode="numeric"
              aria-label={t('datePicker.hour')}
              className="w-11 rounded-sm border-[1.5px] border-line-strong bg-surface py-1.5 text-center font-mono text-sm text-foreground"
            />
            <span className="font-bold text-muted">:</span>
            <input
              value={selected ? pad(selected.getMinutes()) : '--'}
              onChange={(e) => {
                const n = Number(e.target.value.replace(/\D/g, '').slice(-2))
                if (!Number.isNaN(n)) setMinutes(n)
              }}
              inputMode="numeric"
              aria-label={t('datePicker.minute')}
              className="w-11 rounded-sm border-[1.5px] border-line-strong bg-surface py-1.5 text-center font-mono text-sm text-foreground"
            />
          </div>
        </div>
      )}
    </div>
  )
}

function IconCalendar(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <rect x="3" y="4" width="18" height="17" rx="2" />
      <path d="M3 9h18M8 3v3M16 3v3" />
    </svg>
  )
}

function IconChevronLeft(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M15 18l-6-6 6-6" />
    </svg>
  )
}

function IconChevronRight(props: React.SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M9 18l6-6-6-6" />
    </svg>
  )
}
