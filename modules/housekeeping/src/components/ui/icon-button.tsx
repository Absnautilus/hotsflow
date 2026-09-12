import type { ButtonHTMLAttributes, ComponentType } from 'react'
import { cn } from '@/lib/cn'

type Tone = 'neutral' | 'hintPositive' | 'hintCaution' | 'ok' | 'warning' | 'danger'

// Matches the Hotsflow shell's own row-action buttons (apps/web's
// .row-action): transparent, borderless, 44px, 8px radius, muted at rest --
// only the hover color carries the tone's semantic hint, so a row never
// reads like a traffic light.
const toneHoverClass: Record<Tone, string> = {
  neutral: 'hover:text-accent',
  hintPositive: 'hover:text-ok-ink',
  hintCaution: 'hover:text-terracotta-ink',
  ok: 'hover:text-ok-ink',
  warning: 'hover:text-wait-ink',
  danger: 'hover:text-bad-ink',
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
      className={cn(
        'flex h-11 w-11 shrink-0 cursor-pointer items-center justify-center rounded-lg border-0 bg-transparent text-muted transition-colors disabled:cursor-not-allowed disabled:opacity-35',
        toneHoverClass[tone],
        className,
      )}
      {...props}
    >
      <Icon className="h-[15px] w-[15px]" />
    </button>
  )
}
