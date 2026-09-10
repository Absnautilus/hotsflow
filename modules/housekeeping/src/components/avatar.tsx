// Tenui e desaturati apposta: devono distinguere le persone, non competere
// con i colori di stato (attesa/in corso/confermato) nella stessa schermata.
const PALETTE = ['#8A6A3A', '#6B5B78', '#2E6B78', '#5C7A5E', '#7A5C4A', '#4A6670', '#9A7B4E', '#5E6B4A', '#6B4E5E', '#2A2E3A']

function colorFor(name: string): string {
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) >>> 0
  return PALETTE[hash % PALETTE.length]!
}

function initialsFor(name: string): string {
  const parts = name.trim().split(/\s+/)
  const first = parts[0]?.[0] ?? ''
  const last = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : ''
  return (first + last).toUpperCase()
}

export function Avatar({ name, className }: { name: string; className?: string }) {
  return (
    <span
      title={name}
      style={{ backgroundColor: colorFor(name) }}
      className={`inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[0.625rem] font-semibold text-white ${className ?? ''}`}
    >
      {initialsFor(name)}
    </span>
  )
}
