import { useEffect, useState } from 'react'
import { EmptyState, IconInboxEmpty } from '@/components/empty-state'
import { StatusBadge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableFrame,
  TableHead,
  TableHeaderCell,
  TableRow,
} from '@/components/ui/table'
import { AutoText } from '@/components/auto-text'
import { fetchArchivedRequests } from '@/lib/staff-api'
import { formatElapsed, formatTime } from '@/lib/format'
import { getErrorMessage } from '@/lib/errors'
import { useLocale } from '@/lib/i18n/locale-context'
import type { QueuedRequest } from '@/lib/staff-types'

const PAGE_SIZE = 15

export function ArchivePage({ hotelId }: { hotelId: string }) {
  const { t } = useLocale()
  const [page, setPage] = useState(0)
  const [items, setItems] = useState<QueuedRequest[] | null>(null)
  const [total, setTotal] = useState(0)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setItems(null)
    fetchArchivedRequests(page, hotelId)
      .then(({ items, total }) => {
        setItems(items)
        setTotal(total)
      })
      .catch((err) => setError(getErrorMessage(err)))
  }, [page, hotelId])

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.archive.title')}</h1>
        <p className="text-sm text-muted">{t('staff.archive.subtitle')}</p>
      </div>

      {error ? (
        <div className="rounded-lg border border-bad-ink/25 bg-bad-bg p-4 text-sm text-bad-ink">
          {t('staff.archive.loadError', { error })}
        </div>
      ) : items === null ? (
        <p className="text-sm text-muted">{t('staff.archive.loading')}</p>
      ) : items.length === 0 ? (
        <EmptyState icon={<IconInboxEmpty className="h-6 w-6" />} title={t('staff.archive.emptyTitle')} description={t('staff.archive.emptyDesc')} />
      ) : (
        <>
          <TableFrame>
            <Table>
              <TableHead>
                <tr>
                  <TableHeaderCell>{t('staff.archive.colRoom')}</TableHeaderCell>
                  <TableHeaderCell>{t('staff.archive.colItem')}</TableHeaderCell>
                  <TableHeaderCell>{t('staff.archive.colDepartment')}</TableHeaderCell>
                  <TableHeaderCell>{t('staff.archive.colStatus')}</TableHeaderCell>
                  <TableHeaderCell>{t('staff.archive.colCreated')}</TableHeaderCell>
                  <TableHeaderCell>{t('staff.archive.colDuration')}</TableHeaderCell>
                </tr>
              </TableHead>
              <TableBody>
                {items.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="font-medium text-foreground">{r.room_number}</TableCell>
                    <TableCell className="text-muted">
                      <AutoText text={r.request_types?.name ?? t('staff.row.defaultTypeName')} translations={r.request_types?.name_i18n} />
                    </TableCell>
                    <TableCell className="text-muted">{t(`department.${r.assigned_department}` as const)}</TableCell>
                    <TableCell>
                      <StatusBadge status={r.status} label={t(`statusLabel.${r.status}` as const)} />
                    </TableCell>
                    <TableCell className="text-muted">{formatTime(r.created_at)}</TableCell>
                    <TableCell className="text-muted">
                      {r.status === 'completed' && r.completed_at ? formatElapsed(r.created_at, new Date(r.completed_at)) : '—'}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableFrame>
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-3">
              <Button
                type="button"
                variant="secondary"
                size="sm"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
              >
                {t('staff.queue.donePagePrev')}
              </Button>
              <span className="text-xs text-muted">{t('staff.queue.donePageLabel', { page: page + 1, total: totalPages })}</span>
              <Button
                type="button"
                variant="secondary"
                size="sm"
                disabled={page >= totalPages - 1}
                onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
              >
                {t('staff.queue.donePageNext')}
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  )
}
