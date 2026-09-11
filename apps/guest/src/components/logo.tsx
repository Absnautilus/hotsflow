export function LogoMark({ className, mouthColor = '#1e1b2e' }: { className?: string; mouthColor?: string }) {
  return (
    <svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg" className={className} aria-hidden="true">
      <path d="M24 10c-7.2 0-13 5.8-13 13v6l-3 4h32l-3-4v-6c0-7.2-5.8-13-13-13Z" fill="currentColor" />
      <circle cx="24" cy="8" r="2.4" fill="currentColor" />
      <path d="M19 36a5 5 0 0 0 10 0" stroke={mouthColor} strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

export function Logo({ className, textClassName }: { className?: string; textClassName?: string }) {
  return (
    <span className={`inline-flex items-center gap-2 text-accent ${className ?? ''}`}>
      <LogoMark className="h-6 w-6" />
      <span className={textClassName ?? 'font-head font-extrabold text-foreground'}>RoomCall</span>
    </span>
  )
}
