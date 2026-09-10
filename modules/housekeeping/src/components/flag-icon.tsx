import type { Locale } from '@/lib/i18n/locales'

// Hand-drawn flags instead of emoji: flag emoji render as plain two-letter
// codes on some platforms (notably Windows), which isn't what "colored
// flags" means to a hotel guest. This way it's always the actual flag,
// everywhere, with no font or external asset dependency.
function ItalyFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="1" height="2" x="0" fill="#009246" />
      <rect width="1" height="2" x="1" fill="#fff" />
      <rect width="1" height="2" x="2" fill="#ce2b37" />
    </svg>
  )
}

function FranceFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="1" height="2" x="0" fill="#0055a4" />
      <rect width="1" height="2" x="1" fill="#fff" />
      <rect width="1" height="2" x="2" fill="#ef4135" />
    </svg>
  )
}

function GermanyFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="0.667" y="0" fill="#000" />
      <rect width="3" height="0.667" y="0.667" fill="#dd0000" />
      <rect width="3" height="0.667" y="1.333" fill="#ffce00" />
    </svg>
  )
}

function SpainFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="0.5" y="0" fill="#aa151b" />
      <rect width="3" height="1" y="0.5" fill="#f1bf00" />
      <rect width="3" height="0.5" y="1.5" fill="#aa151b" />
    </svg>
  )
}

function PortugalFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="1.2" height="2" x="0" fill="#046a38" />
      <rect width="1.8" height="2" x="1.2" fill="#da020e" />
      <circle cx="1.2" cy="1" r="0.32" fill="#ffce00" />
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

function JapanFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="2" fill="#fff" />
      <circle cx="1.5" cy="1" r="0.55" fill="#bc002d" />
    </svg>
  )
}

function ChinaFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="2" fill="#de2910" />
      <g fill="#ffde00">
        <polygon points="0.5,0.3 0.6,0.6 0.9,0.6 0.65,0.78 0.75,1.08 0.5,0.9 0.25,1.08 0.35,0.78 0.1,0.6 0.4,0.6" />
        <polygon points="1.05,0.25 1.1,0.38 1.24,0.38 1.13,0.46 1.17,0.6 1.05,0.51 0.93,0.6 0.97,0.46 0.86,0.38 1,0.38" />
        <polygon points="1.3,0.55 1.35,0.68 1.49,0.68 1.38,0.76 1.42,0.9 1.3,0.81 1.18,0.9 1.22,0.76 1.11,0.68 1.25,0.68" />
        <polygon points="1.3,0.95 1.35,1.08 1.49,1.08 1.38,1.16 1.42,1.3 1.3,1.21 1.18,1.3 1.22,1.16 1.11,1.08 1.25,1.08" />
        <polygon points="1.05,1.25 1.1,1.38 1.24,1.38 1.13,1.46 1.17,1.6 1.05,1.51 0.93,1.6 0.97,1.46 0.86,1.38 1,1.38" />
      </g>
    </svg>
  )
}

function RussiaFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="0.667" y="0" fill="#fff" />
      <rect width="3" height="0.667" y="0.667" fill="#0039a6" />
      <rect width="3" height="0.667" y="1.333" fill="#d52b1e" />
    </svg>
  )
}

function IndiaFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="0.667" y="0" fill="#ff9933" />
      <rect width="3" height="0.667" y="0.667" fill="#fff" />
      <rect width="3" height="0.667" y="1.333" fill="#138808" />
      <circle cx="1.5" cy="1" r="0.22" fill="none" stroke="#000080" strokeWidth="0.03" />
    </svg>
  )
}

function BangladeshFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="2" fill="#006a4e" />
      <circle cx="1.4" cy="1" r="0.5" fill="#f42a41" />
    </svg>
  )
}

function SaudiArabiaFlag() {
  return (
    <svg viewBox="0 0 3 2" preserveAspectRatio="xMidYMid slice" className="h-full w-full">
      <rect width="3" height="2" fill="#006c35" />
      <rect x="0.4" y="1.3" width="1.3" height="0.14" rx="0.07" fill="#fff" />
      <path d="M1.75 1.28 c0.12 0 0.2 0.08 0.2 0.08 s-0.12 0.02 -0.2 -0.01 c0.02 0.05 0.09 0.09 0.09 0.09 s-0.14 0.01 -0.2 -0.08 c-0.03 0.04 -0.05 0.09 -0.05 0.09" fill="#fff" />
    </svg>
  )
}

const FLAGS: Record<Locale, () => React.JSX.Element> = {
  it: ItalyFlag,
  en: UkFlag,
  fr: FranceFlag,
  de: GermanyFlag,
  es: SpainFlag,
  pt: PortugalFlag,
  ja: JapanFlag,
  bn: BangladeshFlag,
  hi: IndiaFlag,
  ar: SaudiArabiaFlag,
  zh: ChinaFlag,
  ru: RussiaFlag,
}

export function FlagIcon({ code, className }: { code: Locale; className?: string }) {
  const Flag = FLAGS[code]
  return (
    <span className={className ? `inline-block overflow-hidden rounded-full ${className}` : 'inline-block overflow-hidden rounded-full'}>
      <Flag />
    </span>
  )
}
