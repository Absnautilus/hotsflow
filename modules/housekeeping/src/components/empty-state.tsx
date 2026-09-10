import type { ReactNode } from 'react'

export function EmptyState({ icon, title, description, action }: { icon: ReactNode; title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-lg border border-line bg-surface px-6 py-13 text-center">
      <div className="mb-4 flex h-13 w-13 items-center justify-center rounded-2xl bg-surface-2 text-muted">{icon}</div>
      <p className="font-head text-sm font-bold text-foreground">{title}</p>
      {description && <p className="mt-1.5 max-w-64 text-xs leading-relaxed text-muted">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}

export function IconInboxEmpty(props: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" className={props.className}>
      <path d="M3 12h4l2 3h6l2-3h4" />
      <path d="M5.5 5h13L21 12v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6L5.5 5Z" />
    </svg>
  )
}

export function IconBedEmpty(props: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" className={props.className}>
      <path d="M3 18v-7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v7M3 18v2M21 18v2M3 14h18M7 11V9a2 2 0 0 1 2-2h1a2 2 0 0 1 2 2v2" />
    </svg>
  )
}
