// Hand-drawn flags instead of emoji: flag emoji render as plain two-letter
// codes on some platforms (notably Windows). Same approach as the
// Housekeeping module's own FlagIcon, kept in sync for visual consistency.
function ItalyFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="1" height="2" x="0" fill="#009246" />
      <rect width="1" height="2" x="1" fill="#fff" />
      <rect width="1" height="2" x="2" fill="#ce2b37" />
    </svg>
  )
}

function UkFlag() {
  return (
    <svg viewBox="0 0 60 40" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="60" height="40" fill="#012169" />
      <line x1="0" y1="0" x2="60" y2="40" stroke="#fff" strokeWidth="10" />
      <line x1="60" y1="0" x2="0" y2="40" stroke="#fff" strokeWidth="10" />
      <line x1="0" y1="0" x2="60" y2="40" stroke="#c8102e" strokeWidth="4" />
      <line x1="60" y1="0" x2="0" y2="40" stroke="#c8102e" strokeWidth="4" />
      <rect x="0" y="13" width="60" height="14" fill="#fff" />
      <rect x="23" y="0" width="14" height="40" fill="#fff" />
      <rect x="0" y="17" width="60" height="6" fill="#c8102e" />
      <rect x="27" y="0" width="6" height="40" fill="#c8102e" />
    </svg>
  )
}

const FLAGS = { it: ItalyFlag, en: UkFlag } as const

export function FlagIcon({ code, className }: { code: 'it' | 'en'; className?: string }) {
  const Flag = FLAGS[code]
  return (
    <span className={`flag-icon${className ? ` ${className}` : ''}`}>
      <Flag />
    </span>
  )
}
