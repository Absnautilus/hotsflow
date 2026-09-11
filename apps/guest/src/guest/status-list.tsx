import { useEffect, useState } from 'react'
import { Card, CardBody } from '@/components/ui/card'
import { StatusBadge } from '@/components/ui/badge'
import { AutoText } from '@/components/auto-text'
import { cancelMyRequest, fetchMenu, isInvalidSessionError, listMyRequests } from '@/lib/guest-api'
import { useLocale } from '@/lib/i18n/locale-context'
import type { GuestRequest, RequestStatus } from '@/lib/types'

const POLL_INTERVAL_MS = 12_000

export function StatusList({
  token,
  refreshKey,
  onSessionExpired,
}: {
  token: string
  refreshKey: number
  onSessionExpired: () => void
}) {
  const { t } = useLocale()
  const [requests, setRequests] = useState<GuestRequest[] | null>(null)
  const [typeInfo, setTypeInfo] = useState<Record<string, { name: string; name_i18n: Record<string, string> }>>({})
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchMenu()
      .then(({ types }) => setTypeInfo(Object.fromEntries(types.map((rt) => [rt.id, { name: rt.name, name_i18n: rt.name_i18n }]))))
      .catch(() => {
        // the request cards still work without the item name, just less useful
      })
  }, [])

  useEffect(() => {
    let cancelled = false

    async function load() {
      try {
        const data = await listMyRequests(token)
        if (!cancelled) setRequests(data)
      } catch (err) {
        if (isInvalidSessionError(err)) {
          onSessionExpired()
          return
        }
        if (!cancelled) setError(t('status.refreshError'))
      }
    }

    load()
    const interval = setInterval(load, POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, refreshKey, onSessionExpired])

  if (error) return <p className="text-center text-sm text-bad-ink">{error}</p>
  if (!requests) return <p className="text-center text-sm text-muted">{t('flow.loading')}</p>
  if (requests.length === 0) return <p className="text-center text-sm text-muted">{t('status.empty')}</p>

  return (
    <div className="space-y-3">
      {requests.map((request) => (
        <RequestCard
          key={request.id}
          request={request}
          typeInfo={typeInfo[request.request_type_id]}
          onCancel={async () => {
            try {
              const updated = await cancelMyRequest(token, request.id)
              setRequests((prev) => prev?.map((r) => (r.id === updated.id ? updated : r)) ?? null)
            } catch (err) {
              if (isInvalidSessionError(err)) onSessionExpired()
            }
          }}
        />
      ))}
    </div>
  )
}

const STATUS_LABEL_KEY: Record<RequestStatus, `statusLabel.${RequestStatus}`> = {
  requested: 'statusLabel.requested',
  in_progress: 'statusLabel.in_progress',
  completed: 'statusLabel.completed',
  cancelled: 'statusLabel.cancelled',
}

function RequestCard({
  request,
  typeInfo,
  onCancel,
}: {
  request: GuestRequest
  typeInfo: { name: string; name_i18n: Record<string, string> } | undefined
  onCancel: () => void
}) {
  const { t } = useLocale()
  const time = new Date(request.created_at).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' })
  return (
    <Card>
      <CardBody className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-foreground">
            {request.quantity ? `${request.quantity} × ` : ''}
            {typeInfo ? <AutoText text={typeInfo.name} translations={typeInfo.name_i18n} /> : t('status.requestAt', { time })}
          </p>
          <p className="mt-0.5 text-xs text-muted">{t('status.requestAt', { time })}</p>
          {request.note && <p className="mt-0.5 text-xs text-muted">{request.note}</p>}
        </div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          <StatusBadge status={request.status} label={t(STATUS_LABEL_KEY[request.status])} />
          {request.status === 'requested' && (
            <button type="button" onClick={onCancel} className="cursor-pointer text-xs text-muted hover:text-bad-ink">
              {t('status.cancel')}
            </button>
          )}
        </div>
      </CardBody>
    </Card>
  )
}
