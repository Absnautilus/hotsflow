import type { ButtonHTMLAttributes, ComponentType } from 'react'
import { cn } from '@/lib/cn'

type Tone = 'neutral' | 'hintPositive' | 'hintCaution' | 'ok' | 'warning' | 'danger'

/* Row actions should not read like a traffic light. The chrome stays neutral
   and the glyph carries the semantic hint; destructive emphasis is reserved
   for confirmation surfaces, not every row action. */
const toneClass: Record<Tone, string> = {
  neutral: 'border border-line bg-surface text-foreground/70 hover:bg-surface-2',
  hintPositive: 'border border-line bg-surface text-ok-ink hover:border-ok-line hover:bg-ok-bg/40',
  hintCaution: 'border border-line bg-surface text-terracotta-ink hover:border-terracotta-line hover:bg-terracotta-bg/45',
  ok: 'border border-line bg-surface text-ok-ink hover:border-ok-line hover:bg-ok-bg/40',
  warning: 'border border-line bg-surface text-wait-ink hover:border-wait-line hover:bg-wait-bg/45',
  danger: 'border border-line bg-surface text-bad-ink hover:border-bad-line hover:bg-bad-bg/45',
}

export function IconButton({
  tone,
  label,
  icon: Icon,
  className,
  ...props
}: {
  tone: Tone
  label: string
  icon: ComponentType<{ className?: string }>
} & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'>) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={cn(
        'flex h-10 w-10 shrink-0 cursor-pointer items-center justify-center rounded-full shadow-sm transition-all active:scale-[0.94] disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100 sm:h-9 sm:w-9',
        toneClass[tone],
        className,
      )}
      {...props}
    >
      <Icon className="h-4 w-4" />
    </button>
  )
}
