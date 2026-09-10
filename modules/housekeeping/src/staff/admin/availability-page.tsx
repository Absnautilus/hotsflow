import { useEffect, useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { AutoText } from '@/components/auto-text'
import { fetchItemAvailability, type ItemAvailability } from '@/lib/admin-api'
import { getErrorMessage } from '@/lib/errors'
import { useLocale } from '@/lib/i18n/locale-context'

export function AvailabilityPage({ hotelId }: { hotelId: string }) {
  const { t } = useLocale()
  const [items, setItems] = useState<ItemAvailability[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchItemAvailability(hotelId)
      .then(setItems)
      .catch((err) => setError(getErrorMessage(err)))
  }, [hotelId])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.availability.title')}</h1>
        <p className="text-sm text-muted">{t('staff.availability.subtitle')}</p>
      </div>

      {error ? (
        <div role="alert" className="rounded-lg border border-bad-ink/25 bg-bad-bg p-4 text-sm text-bad-ink">{t('staff.availability.loadError', { error })}</div>
      ) : items === null ? (
        <p role="status" className="text-sm text-muted">{t('staff.availability.loading')}</p>
      ) : items.length === 0 ? (
        <p className="text-sm text-muted">{t('staff.availability.empty')}</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-line bg-white">
          <table aria-label={t('staff.availability.title')} className="w-full min-w-max text-sm">
            <thead className="bg-surface-2 text-left text-xs uppercase text-muted">
              <tr>
                <th className="px-4 py-2">{t('staff.availability.colItem')}</th>
                <th className="px-4 py-2">{t('staff.availability.colTotal')}</th>
                <th className="px-4 py-2">{t('staff.availability.colRemaining')}</th>
                <th className="px-4 py-2">{t('staff.availability.colRooms')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {items.map((it) => (
                <tr key={it.requestTypeId}>
                  <td className="px-4 py-2 font-medium text-foreground">
                    <AutoText text={it.name} translations={it.name_i18n} />
                    {it.categoryName && (
                      <span className="ml-1.5 text-xs text-muted">
                        · <AutoText text={it.categoryName} translations={it.categoryName_i18n} />
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-2 tabular-nums text-muted">{it.totalQuantity}</td>
                  <td className="px-4 py-2">
                    <Badge className={it.remaining === 0 ? 'bg-bad-bg text-bad-ink' : 'bg-ok-bg text-ok-ink'}>{it.remaining}</Badge>
                  </td>
                  <td className="px-4 py-2 text-muted">
                    {it.rooms.length === 0 ? '—' : it.rooms.map((r) => t('staff.newRequest.room') + ' ' + r).join(', ')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
