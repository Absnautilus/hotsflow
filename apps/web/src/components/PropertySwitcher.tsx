import { useEffect, useRef, useState } from 'react'
import { Check, ChevronDown } from 'lucide-react'

export interface SwitchableProperty {
  id: string
  name: string
}

export function PropertySwitcher({
  current,
  properties,
  staffLabel,
  onSelect,
}: {
  current: SwitchableProperty | null
  properties: SwitchableProperty[]
  staffLabel: string
  onSelect: (propertyId: string) => void
}) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const canSwitch = properties.length > 1

  useEffect(() => {
    if (!open) return
    function onPointerDown(event: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false)
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open])

  const initials = (current?.name ?? '??').slice(0, 2).toUpperCase()

  return (
    <div ref={rootRef} className="property-switcher-root">
      <button
        type="button"
        className="property-switcher"
        aria-haspopup={canSwitch ? 'listbox' : undefined}
        aria-expanded={canSwitch ? open : undefined}
        onClick={() => canSwitch && setOpen((o) => !o)}
      >
        <span className="mk">{initials}</span>
        <span>
          <strong>{current?.name ?? '—'}</strong>
          <small>{staffLabel}</small>
        </span>
        {canSwitch && <ChevronDown size={16} className={open ? 'rotate' : undefined} aria-hidden="true" />}
      </button>
      {canSwitch && open && (
        <div className="switch-panel" role="listbox">
          <div className="switch-panel-hd">Strutture</div>
          {properties.map((property) => (
            <button
              type="button"
              key={property.id}
              role="option"
              aria-selected={property.id === current?.id}
              className={`switch-panel-row${property.id === current?.id ? ' current' : ''}`}
              onClick={() => {
                onSelect(property.id)
                setOpen(false)
              }}
            >
              <span className="mk">{property.name.slice(0, 2).toUpperCase()}</span>
              <span className="n">{property.name}</span>
              {property.id === current?.id && <Check size={15} className="check" aria-hidden="true" />}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
