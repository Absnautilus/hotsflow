import { useEffect, useMemo, useState } from 'react'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { FieldError, FieldGroup, Label, Textarea } from '@/components/ui/field'
import { CategoryIcon } from '@/components/category-icon'
import { AutoText } from '@/components/auto-text'
import { createGuestRequest, fetchMenu, isInvalidSessionError } from '@/lib/guest-api'
import { useLocale } from '@/lib/i18n/locale-context'
import type { GuestRequest, RequestCategory, RequestType } from '@/lib/types'

type Step =
  | { name: 'categories' }
  | { name: 'types'; category: RequestCategory }
  | { name: 'compose'; category: RequestCategory; type: RequestType }
  | { name: 'confirm'; type: RequestType; request: GuestRequest }

export function RequestFlow({
  token,
  onSessionExpired,
  onCreated,
}: {
  token: string
  onSessionExpired: () => void
  onCreated: (request: GuestRequest) => void
}) {
  const { t } = useLocale()
  const [menu, setMenu] = useState<{ categories: RequestCategory[]; types: RequestType[] } | null>(null)
  const [menuError, setMenuError] = useState<string | null>(null)
  const [step, setStep] = useState<Step>({ name: 'categories' })

  useEffect(() => {
    fetchMenu()
      .then(setMenu)
      .catch(() => setMenuError(t('flow.menuLoadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (menuError) {
    return <p className="text-center text-sm text-bad-ink">{menuError}</p>
  }

  if (!menu) {
    return <p className="text-center text-sm text-muted">{t('flow.loading')}</p>
  }

  if (step.name === 'categories') {
    return (
      <CategoriesGrid
        categories={menu.categories}
        onSelect={(category) => setStep({ name: 'types', category })}
      />
    )
  }

  if (step.name === 'types') {
    const types = menu.types.filter((rt) => rt.category_id === step.category.id)
    return (
      <TypesList
        category={step.category}
        types={types}
        onBack={() => setStep({ name: 'categories' })}
        onSelect={(type) => setStep({ name: 'compose', category: step.category, type })}
      />
    )
  }

  if (step.name === 'compose') {
    return (
      <ComposeForm
        type={step.type}
        onBack={() => setStep({ name: 'types', category: step.category })}
        onSubmit={async (quantity, note) => {
          try {
            const request = await createGuestRequest(token, step.type.id, quantity, note)
            setStep({ name: 'confirm', type: step.type, request })
            onCreated(request)
          } catch (error) {
            if (isInvalidSessionError(error)) {
              onSessionExpired()
              return
            }
            throw error
          }
        }}
      />
    )
  }

  return (
    <ConfirmPanel
      type={step.type}
      request={step.request}
      onNewRequest={() => setStep({ name: 'categories' })}
    />
  )
}

function CategoriesGrid({
  categories,
  onSelect,
}: {
  categories: RequestCategory[]
  onSelect: (category: RequestCategory) => void
}) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {categories.map((category) => (
        <button
          key={category.id}
          type="button"
          onClick={() => onSelect(category)}
          className="flex cursor-pointer flex-col items-center gap-2 rounded-lg border border-line bg-white p-5 text-center shadow-sm transition-colors hover:border-accent-soft-line hover:bg-accent-soft"
        >
          <CategoryIcon icon={category.icon} className="h-7 w-7 text-accent" />
          <span className="text-sm font-medium text-foreground">
            <AutoText text={category.name} translations={category.name_i18n} />
          </span>
        </button>
      ))}
    </div>
  )
}

function TypesList({
  category,
  types,
  onBack,
  onSelect,
}: {
  category: RequestCategory
  types: RequestType[]
  onBack: () => void
  onSelect: (type: RequestType) => void
}) {
  const { t } = useLocale()
  return (
    <Card>
      <CardHeader className="flex items-center gap-2">
        <button type="button" onClick={onBack} className="cursor-pointer text-muted hover:text-foreground" aria-label={t('flow.back')}>
          ←
        </button>
        <h2 className="text-sm font-semibold text-foreground">
          <AutoText text={category.name} translations={category.name_i18n} />
        </h2>
      </CardHeader>
      <CardBody className="space-y-2">
        {types.length === 0 && <p className="text-sm text-muted">{t('flow.noItems')}</p>}
        {types.map((type) => (
          <button
            key={type.id}
            type="button"
            onClick={() => onSelect(type)}
            className="block w-full cursor-pointer rounded-md border border-line p-3 text-left text-sm hover:border-accent-soft-line hover:bg-accent-soft"
          >
            <span className="font-medium text-foreground">
              <AutoText text={type.name} translations={type.name_i18n} />
            </span>
            {type.description && (
              <p className="mt-0.5 text-xs text-muted">
                <AutoText text={type.description} translations={type.description_i18n} />
              </p>
            )}
          </button>
        ))}
      </CardBody>
    </Card>
  )
}

function ComposeForm({
  type,
  onBack,
  onSubmit,
}: {
  type: RequestType
  onBack: () => void
  onSubmit: (quantity: number | null, note: string | null) => Promise<void>
}) {
  const { t } = useLocale()
  const [quantity, setQuantity] = useState(1)
  const [note, setNote] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function onConfirm() {
    setPending(true)
    setError(null)
    try {
      await onSubmit(type.allows_quantity ? quantity : null, note.trim() || null)
    } catch {
      setError(t('flow.submitError'))
    } finally {
      setPending(false)
    }
  }

  return (
    <Card>
      <CardHeader className="flex items-center gap-2">
        <button type="button" onClick={onBack} className="cursor-pointer text-muted hover:text-foreground" aria-label={t('flow.back')}>
          ←
        </button>
        <h2 className="text-sm font-semibold text-foreground">
          <AutoText text={type.name} translations={type.name_i18n} />
        </h2>
      </CardHeader>
      <CardBody>
        {type.allows_quantity && (
          <FieldGroup>
            <Label>{t('flow.quantity')}</Label>
            <div className="flex items-center gap-3">
              <Button
                type="button"
                variant="outline"
                size="sm"
                disabled={quantity <= 1}
                onClick={() => setQuantity((q) => Math.max(1, q - 1))}
              >
                −
              </Button>
              <span className="w-8 text-center text-sm font-medium tabular-nums">{quantity}</span>
              <Button type="button" variant="outline" size="sm" onClick={() => setQuantity((q) => Math.min(10, q + 1))}>
                +
              </Button>
            </div>
          </FieldGroup>
        )}
        <FieldGroup>
          <Label htmlFor="note">{t('flow.notes')}</Label>
          <Textarea id="note" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder={t('flow.notesPlaceholder')} />
        </FieldGroup>
        <FieldError>{error ?? undefined}</FieldError>
        <Button type="button" disabled={pending} onClick={onConfirm} className="mt-2 w-full">
          {pending ? t('flow.sendPending') : t('flow.send')}
        </Button>
      </CardBody>
    </Card>
  )
}

function ConfirmPanel({
  type,
  request,
  onNewRequest,
}: {
  type: RequestType
  request: GuestRequest
  onNewRequest: () => void
}) {
  const { t } = useLocale()
  const time = useMemo(
    () => new Date(request.created_at).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' }),
    [request.created_at],
  )
  return (
    <div className="rounded-lg border border-ok-ink/25 bg-ok-bg p-6 text-center">
      <p className="text-lg font-semibold text-ok-ink">{t('flow.confirmTitle')}</p>
      <p className="mt-2 text-sm text-ok-ink">
        <AutoText text={type.name} translations={type.name_i18n} />
        {request.quantity ? ` · ${request.quantity}` : ''} — {t('flow.confirmAt', { time })}
      </p>
      <Button variant="outline" className="mt-4 bg-white" onClick={onNewRequest}>
        {t('tabs.new')}
      </Button>
    </div>
  )
}
