import type { SVGProps } from 'react'

// Matches the hand-drawn line style used everywhere else (dashboard-header,
// text-size toggle, empty states): 24x24 viewBox, no fill, 1.8 stroke, round
// caps/joins. One file so every row action button pulls from the same set.
const shared = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' } as const

export function IconClaim(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M12 4v10" />
      <path d="M7 10l5 5 5-5" />
      <path d="M5 19h14" />
    </svg>
  )
}

// The suite's "Annulla" glyph — a plain left arrow, not a curved undo — used
// here for "Indietro" too since both are the same "no consequence, step
// back" action.
export function IconUndo(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M19 12H5" />
      <path d="M11 6l-6 6 6 6" />
    </svg>
  )
}

export function IconCheck(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M4 12.5 9 17.5 20 6.5" />
    </svg>
  )
}

// Deliberately not part of `shared` (fill: none / stroke line-icons) —
// a dot-grid drag handle reads better filled, and this exact 2x3 pattern
// is the conventional grip affordance, distinct enough from the action
// icons around it that it doesn't need to match their stroke style.
export function IconGrip(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" {...props}>
      <circle cx="9" cy="6" r="1.5" />
      <circle cx="15" cy="6" r="1.5" />
      <circle cx="9" cy="12" r="1.5" />
      <circle cx="15" cy="12" r="1.5" />
      <circle cx="9" cy="18" r="1.5" />
      <circle cx="15" cy="18" r="1.5" />
    </svg>
  )
}

export function IconX(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M6 6l12 12" />
      <path d="M18 6 6 18" />
    </svg>
  )
}

export function IconTrash(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M4 7h16" />
      <path d="M9 7V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V7" />
      <path d="M6.5 7 7.3 19a2 2 0 0 0 2 1.9h5.4a2 2 0 0 0 2-1.9L17.5 7" />
      <path d="M10 11v6" />
      <path d="M14 11v6" />
    </svg>
  )
}

export function IconReturn(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M4 9 12 4l8 5" />
      <path d="M4 9v9.5A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5V9" />
      <path d="M9.5 13.5 12 16l4-4.5" />
    </svg>
  )
}

export function IconPower(props: SVGProps<SVGSVGElement>) {
  return (
    <svg {...shared} {...props}>
      <path d="M12 3v8" />
      <path d="M7 6.3a8 8 0 1 0 10 0" />
    </svg>
  )
}

// Exact glyph as specified (lucide's "languages" icon) -- not redrawn to
// the suite's shared 1.8 stroke width, since the reference given used 2.
export function IconLanguages(props: SVGProps<SVGSVGElement>) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="m5 8 6 6" />
      <path d="m4 14 6-6 2-3" />
      <path d="M2 5h12" />
      <path d="M7 2h1" />
      <path d="m22 22-5-10-5 10" />
      <path d="M14 18h6" />
    </svg>
  )
}
