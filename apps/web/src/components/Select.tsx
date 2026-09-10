import { Children, isValidElement, useEffect, useMemo, useRef, useState, type KeyboardEvent, type OptionHTMLAttributes, type ReactNode } from 'react'
import { Check, ChevronDown } from 'lucide-react'

interface SelectOptionProps extends OptionHTMLAttributes<HTMLOptionElement> {
  value: string
  children?: ReactNode
}

// Custom listbox so the open list matches the app's own styling instead of
// the browser/OS-rendered native <select> popup (see Team's "Mansione" bug).
// Accepts <option> children like a native select so call sites barely
// change, and renders a hidden input under `name` so it still participates
// in FormData-based form submission the same way a native select would.
export function Select({
  id,
  name,
  value,
  onChange,
  disabled,
  required,
  children,
}: {
  id?: string
  name: string
  value: string
  onChange: (value: string) => void
  disabled?: boolean
  required?: boolean
  children: ReactNode
}) {
  const options = useMemo(
    () =>
      Children.toArray(children).flatMap((child) => {
        if (!isValidElement<SelectOptionProps>(child)) return []
        return [{ value: child.props.value, label: child.props.children, disabled: Boolean(child.props.disabled) }]
      }),
    [children],
  )
  const [open, setOpen] = useState(false)
  const [highlighted, setHighlighted] = useState(0)
  const rootRef = useRef<HTMLDivElement>(null)
  const selectedIndex = options.findIndex((option) => option.value === value)
  const selected = selectedIndex >= 0 ? options[selectedIndex] : undefined

  useEffect(() => {
    if (!open) return
    function onPointerDown(event: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onPointerDown)
    return () => document.removeEventListener('mousedown', onPointerDown)
  }, [open])

  function commit(index: number) {
    const option = options[index]
    if (!option || option.disabled) return
    onChange(option.value)
    setOpen(false)
  }

  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (disabled) return
    if (!open) {
      if (['Enter', ' ', 'ArrowDown', 'ArrowUp'].includes(event.key)) {
        event.preventDefault()
        setHighlighted(selectedIndex >= 0 ? selectedIndex : 0)
        setOpen(true)
      }
      return
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setHighlighted((index) => Math.min(options.length - 1, index + 1))
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      setHighlighted((index) => Math.max(0, index - 1))
    } else if (event.key === 'Home') {
      event.preventDefault()
      setHighlighted(0)
    } else if (event.key === 'End') {
      event.preventDefault()
      setHighlighted(options.length - 1)
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault()
      commit(highlighted)
    } else if (event.key === 'Escape' || event.key === 'Tab') {
      setOpen(false)
    }
  }

  return (
    <div ref={rootRef} className="select-root">
      <input type="hidden" name={name} value={value} required={required} disabled={disabled} />
      <button
        type="button"
        id={id}
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => {
          if (disabled) return
          setHighlighted(selectedIndex >= 0 ? selectedIndex : 0)
          setOpen((value) => !value)
        }}
        onKeyDown={onKeyDown}
        className="select-trigger"
      >
        <span>{selected?.label ?? ''}</span>
        <ChevronDown size={16} className={open ? 'rotate' : undefined} aria-hidden="true" />
      </button>
      {open && (
        <ul role="listbox" className="select-panel">
          {options.map((option, index) => (
            <li
              key={option.value}
              role="option"
              aria-selected={option.value === value}
              aria-disabled={option.disabled}
              onMouseEnter={() => setHighlighted(index)}
              onMouseDown={(event) => { event.preventDefault(); commit(index) }}
              className={`select-option${option.disabled ? ' disabled' : ''}${index === highlighted ? ' highlighted' : ''}`}
            >
              <span>{option.label}</span>
              {option.value === value && <Check size={14} aria-hidden="true" />}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
