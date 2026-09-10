import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { REQUEST_STATUS, REQUEST_STATUS_LABEL, type RequestStatus } from '@/lib/constants'

// bg/ink/border for each status -- the suite's badge spec is always a
// tinted border, not just a flat bg+text pair (see design standard
// #badges: "--b-bg / --b-ink / --b-line").
const colors: Record<RequestStatus, string> = {
  requested: 'bg-wait-bg text-wait-ink border-wait-line',
  in_progress: 'bg-prog-bg text-prog-ink border-prog-line',
  completed: 'bg-done-bg text-done-ink border-done-line',
  cancelled: 'bg-off-bg text-off-ink border-off-line',
}

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const key = (status in colors ? status : REQUEST_STATUS.REQUESTED) as RequestStatus
  return (
    <span className={cn('inline-flex items-center gap-1.5 rounded-sm border px-2.5 py-1 text-[0.65625rem] font-bold uppercase tracking-wide', colors[key])}>
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {label ?? REQUEST_STATUS_LABEL[key]}
    </span>
  )
}

export function Badge({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <span className={cn('inline-flex items-center rounded-full bg-surface-2 px-2.5 py-0.5 text-xs font-medium text-foreground/70', className)}>
      {children}
    </span>
  )
}
