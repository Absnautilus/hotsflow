import { useRef, useState, type ChangeEvent } from 'react'
import { Button } from '@/components/ui/button'
import { useLocale } from '@/lib/i18n/locale-context'
import { cn } from '@/lib/cn'

// The suite had no file-input treatment yet -- every other control here
// (Input, Select, DateTimePicker, Button) is custom-styled, but a bare
// <input type="file"> still rendered the OS-native "Choose file" button,
// the same class of inconsistency Select existed to fix for dropdowns.
// The native input can't be restyled directly (the button chrome is
// OS-drawn), so it's visually hidden and driven by our own Button, which
// is the standard accessible pattern: the input stays in the tab order
// and still receives the real file, just triggered by a styled proxy.
export function FileInput({
  id,
  accept,
  required,
  onFileSelected,
  className,
}: {
  id?: string
  accept?: string
  required?: boolean
  onFileSelected: (file: File | null) => void
  className?: string
}) {
  const { t } = useLocale()
  const inputRef = useRef<HTMLInputElement>(null)
  const [fileName, setFileName] = useState<string | null>(null)

  function handleChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0] ?? null
    setFileName(file?.name ?? null)
    onFileSelected(file)
  }

  return (
    <div className={cn('flex items-center gap-3', className)}>
      <input ref={inputRef} id={id} type="file" accept={accept} required={required} onChange={handleChange} className="sr-only" />
      <Button type="button" variant="outline" size="sm" onClick={() => inputRef.current?.click()}>
        {t('ui.fileInput.choose')}
      </Button>
      <span className="truncate text-sm text-muted">{fileName ?? t('ui.fileInput.none')}</span>
    </div>
  )
}
