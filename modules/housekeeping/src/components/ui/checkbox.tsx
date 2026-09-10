import { useId, type ReactNode } from 'react'
import { cn } from '@/lib/cn'
import { IconCheck } from '@/components/ui/action-icons'

interface CheckboxProps {
  checked: boolean
  onCheckedChange: (checked: boolean) => void
  label?: ReactNode
  disabled?: boolean
  id?: string
  className?: string
  'aria-label'?: string
}

// Switch's own doc comment already named this: "use Checkbox for selection
// tasks" -- it just didn't exist yet. Selection checkboxes (a table row, a
// bulk "select all") are a different affordance than Switch's persistent
// on/off setting, so this is a separate component rather than a Switch
// reskin, matching the distinction the suite had already drawn.
export function Checkbox({ checked, onCheckedChange, label, disabled = false, id, className, ...aria }: CheckboxProps) {
  const generatedId = useId()
  const controlId = id ?? generatedId

  const box = (
    <button
      id={controlId}
      type="button"
      role="checkbox"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange(!checked)}
      className={cn(
        'flex h-5 w-5 shrink-0 items-center justify-center rounded-[5px] border transition-colors disabled:cursor-not-allowed disabled:opacity-45',
        checked ? 'border-accent bg-accent text-white' : 'border-line-strong bg-surface',
        !label && className,
      )}
      {...aria}
    >
      {checked && <IconCheck className="h-3.5 w-3.5" />}
    </button>
  )

  if (!label) return box

  return (
    <label htmlFor={controlId} className={cn('flex cursor-pointer items-center gap-2 text-sm text-foreground', disabled && 'cursor-not-allowed opacity-45', className)}>
      {box}
      {label}
    </label>
  )
}
