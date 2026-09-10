import { useState, type PointerEvent as ReactPointerEvent } from 'react'
import { Card, CardBody } from '@/components/ui/card'
import { IconButton } from '@/components/ui/icon-button'
import { Badge, StatusBadge } from '@/components/ui/badge'
import { Select } from '@/components/ui/field'
import { IconCheck, IconClaim, IconGrip, IconReturn, IconTrash, IconUndo, IconX } from '@/components/ui/action-icons'
import { Avatar } from '@/components/avatar'
import { AutoText } from '@/components/auto-text'
import { DEPARTMENTS } from '@/lib/constants'
import type { Department } from '@/lib/types'
import { formatElapsed, formatTime } from '@/lib/format'
import { cancelRequest, claimRequest, completeRequest, deleteRequest, markItemReturned, reassignRequest, revertRequest } from '@/lib/staff-api'
import type { QueuedRequest } from '@/lib/staff-types'
import { useConfirm } from '@/components/confirm-dialog'
import { useLocale } from '@/lib/i18n/locale-context'

export function RequestRow({
  request,
  now,
  staffId,
  mode,
  canReorder = false,
  onMoveUp,
  onMoveDown,
  onDragPointerDown,
  onDragPointerMove,
  onDragPointerUp,
}: {
  request: QueuedRequest
  now: Date
  staffId: string
  mode: 'active' | 'done'
  canReorder?: boolean
  onMoveUp?: () => void
  onMoveDown?: () => void
  onDragPointerDown?: (e: ReactPointerEvent<HTMLButtonElement>) => void
  onDragPointerMove?: (e: ReactPointerEvent<HTMLButtonElement>) => void
  onDragPointerUp?: (e: ReactPointerEvent<HTMLButtonElement>) => void
}) {
  const { t } = useLocale()
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmDialog, confirm] = useConfirm()
  const typeName = request.request_types?.name ?? t('staff.row.defaultTypeName')
  const typeNameI18n = request.request_types?.name_i18n
  const categoryName = request.request_types?.request_categories?.name
  const categoryNameI18n = request.request_types?.request_categories?.name_i18n
  const trackable = request.request_types?.available_quantity != null

  async function run(action: () => Promise<void>) {
    setPending(true)
    setError(null)
    try {
      await action()
    } catch {
      setError(t('staff.row.opFailed'))
    } finally {
      setPending(false)
    }
  }

  async function onCancel() {
    const ok = await confirm({
      title: t('staff.row.cancelTitle'),
      description: t('staff.row.cancelDesc', { room: request.room_number, type: typeName }),
      confirmLabel: t('staff.row.cancelConfirm'),
    })
    if (ok) run(() => cancelRequest(request.id))
  }

  async function onDelete() {
    const ok = await confirm({
      title: t('staff.row.deleteTitle'),
      description: t('staff.row.deleteDesc', { room: request.room_number, type: typeName }),
      confirmLabel: t('staff.row.deleteConfirm'),
    })
    if (ok) run(() => deleteRequest(request.id))
  }

  const elapsedLabel =
    mode !== 'active'
      ? request.status === 'completed'
        ? t('staff.row.resolvedIn', { time: formatElapsed(request.created_at, new Date(request.completed_at ?? request.created_at)) })
        : t('staff.row.cancelledLabel')
      : request.status === 'in_progress' && request.accepted_at
        ? t('staff.row.inChargeSince', { time: formatElapsed(request.accepted_at, now) })
        : t('staff.row.waitingSince', { time: formatElapsed(request.created_at, now) })

  const draggable = canReorder && mode === 'active' && request.status === 'in_progress' && Boolean(onDragPointerDown)

  return (
    <Card>
      {confirmDialog}
      <CardBody>
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="font-semibold text-foreground">
              {t('staff.newRequest.room')} {request.room_number} <span className="font-normal text-muted">·</span>{' '}
              <AutoText text={typeName} translations={typeNameI18n} />
              {request.quantity ? ` × ${request.quantity}` : ''}
            </p>
            <p className="mt-0.5 text-sm text-muted">
              {formatTime(request.created_at)}
              {categoryName && (
                <>
                  {' · '}
                  <AutoText text={categoryName} translations={categoryNameI18n} />
                </>
              )}
            </p>
          </div>
          {draggable && (
            <div className="flex shrink-0 items-center gap-1">
              <div className="flex flex-col">
                <button
                  type="button"
                  disabled={!onMoveUp}
                  onClick={onMoveUp}
                  aria-label={t('staff.row.moveUp')}
                  className="cursor-pointer leading-none text-muted hover:text-accent disabled:cursor-not-allowed disabled:opacity-30"
                >
                  ▲
                </button>
                <button
                  type="button"
                  disabled={!onMoveDown}
                  onClick={onMoveDown}
                  aria-label={t('staff.row.moveDown')}
                  className="cursor-pointer leading-none text-muted hover:text-accent disabled:cursor-not-allowed disabled:opacity-30"
                >
                  ▼
                </button>
              </div>
              <button
                type="button"
                aria-label={t('staff.row.drag')}
                title={t('staff.row.drag')}
                aria-roledescription={t('staff.row.drag')}
                onPointerDown={onDragPointerDown}
                onPointerMove={onDragPointerMove}
                onPointerUp={onDragPointerUp}
                onPointerCancel={onDragPointerUp}
                className="flex h-9 w-9 shrink-0 cursor-grab touch-none items-center justify-center rounded-full text-muted transition-colors select-none hover:bg-surface-2 hover:text-foreground active:cursor-grabbing"
              >
                <IconGrip className="h-4 w-4" />
              </button>
            </div>
          )}
        </div>

        <div className="mt-2 flex flex-wrap items-center gap-2">
          {request.accepted_by_staff && <Avatar name={request.accepted_by_staff.name} />}
          <StatusBadge status={request.status} label={t(`statusLabel.${request.status}` as const)} />
          <Badge>{t(`department.${request.assigned_department}`)}</Badge>
        </div>

        {request.note && <p className="mt-2 rounded-md bg-surface-2 p-2 text-sm text-muted">{request.note}</p>}

        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-line pt-3">
          <div className="flex items-center gap-2">
            <p className="text-xs text-muted">{elapsedLabel}</p>
            {mode === 'done' && trackable && request.status === 'completed' && (
              <Badge className={request.returned_at ? 'bg-ok-bg text-ok-ink' : 'bg-wait-bg text-wait-ink'}>
                {request.returned_at ? t('staff.row.returned') : t('staff.row.notReturned')}
              </Badge>
            )}
          </div>

          {mode === 'active' && (
            <div className="flex flex-wrap items-center gap-2">
              <Select
                value={request.assigned_department}
                disabled={pending}
                onChange={(e) => run(() => reassignRequest(request.id, e.target.value as Department))}
                className="w-auto py-1 text-xs"
              >
                {DEPARTMENTS.map((value) => (
                  <option key={value} value={value}>
                    {t(`department.${value}`)}
                  </option>
                ))}
              </Select>
              {/* Negatives (reject/cancel) on the left, positives (accept/complete) on the right. */}
              {request.status === 'requested' ? (
                <IconButton tone="hintCaution" icon={IconX} label={t('staff.row.reject')} disabled={pending} onClick={onCancel} />
              ) : (
                <IconButton tone="danger" icon={IconX} label={t('staff.row.cancel')} disabled={pending} onClick={onCancel} />
              )}
              {request.status === 'in_progress' && (
                <IconButton tone="neutral" icon={IconUndo} label={t('staff.row.revert')} disabled={pending} onClick={() => run(() => revertRequest(request.id, 'in_progress'))} />
              )}
              {request.status === 'requested' && (
                <IconButton tone="hintPositive" icon={IconClaim} label={t('staff.row.claim')} disabled={pending} onClick={() => run(() => claimRequest(request.id, staffId))} />
              )}
              {request.status === 'in_progress' && (
                <IconButton tone="ok" icon={IconCheck} label={t('staff.row.complete')} disabled={pending} onClick={() => run(() => completeRequest(request.id))} />
              )}
            </div>
          )}

          {mode === 'done' && (
            <div className="flex flex-wrap items-center gap-2">
              {trackable && request.status === 'completed' && !request.returned_at && (
                <IconButton tone="ok" icon={IconReturn} label={t('staff.row.markReturned')} disabled={pending} onClick={() => run(() => markItemReturned(request.id))} />
              )}
              <IconButton
                tone="neutral"
                icon={IconUndo}
                label={t('staff.row.revert')}
                disabled={pending}
                onClick={() => run(() => revertRequest(request.id, request.status === 'completed' ? 'completed' : 'cancelled'))}
              />
              <IconButton tone="danger" icon={IconTrash} label={t('staff.row.delete')} disabled={pending} onClick={onDelete} />
            </div>
          )}
        </div>
        {error && <p className="mt-2 text-xs text-bad-ink">{error}</p>}
      </CardBody>
    </Card>
  )
}
