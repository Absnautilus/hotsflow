import { useEffect, useState } from 'react'
import { Card, CardBody } from '@/components/ui/card'
import { fetchCompletionStats, type StatsSummary } from '@/lib/admin-api'
import { formatDuration } from '@/lib/format'
import { getErrorMessage } from '@/lib/errors'
import { useLocale } from '@/lib/i18n/locale-context'
import type { TranslationKey } from '@/lib/i18n/dictionaries'

export function StatsPage({ hotelId }: { hotelId: string }) {
  const { t } = useLocale()
  const [stats, setStats] = useState<StatsSummary | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchCompletionStats(hotelId)
      .then(setStats)
      .catch((err) => setError(getErrorMessage(err)))
  }, [hotelId])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.stats.title')}</h1>
        <p className="text-sm text-muted">{t('staff.stats.subtitle')}</p>
      </div>

      {error ? (
        <div className="rounded-lg border border-bad-ink/25 bg-bad-bg p-4 text-sm text-bad-ink">{t('staff.stats.loadError', { error })}</div>
      ) : stats === null ? (
        <p className="text-sm text-muted">{t('staff.stats.loading')}</p>
      ) : stats.overallCount === 0 ? (
        <p className="text-sm text-muted">{t('staff.stats.empty')}</p>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Card>
              <CardBody>
                <p className="text-xs font-bold tracking-wide text-muted uppercase">{t('staff.stats.completedCount')}</p>
                <p className="mt-1 font-head text-3xl font-extrabold text-foreground">{stats.overallCount}</p>
              </CardBody>
            </Card>
            <Card>
              <CardBody>
                <p className="text-xs font-bold tracking-wide text-muted uppercase">{t('staff.stats.avgWait')}</p>
                <p className="mt-1 font-head text-3xl font-extrabold text-foreground">
                  {stats.overallAvgWaitMinutes !== null ? formatDuration(stats.overallAvgWaitMinutes) : '—'}
                </p>
                <p className="mt-1 text-xs text-muted">{t('staff.stats.avgWaitHint')}</p>
              </CardBody>
            </Card>
            <Card>
              <CardBody>
                <p className="text-xs font-bold tracking-wide text-muted uppercase">{t('staff.stats.avgExec')}</p>
                <p className="mt-1 font-head text-3xl font-extrabold text-foreground">
                  {stats.overallAvgExecMinutes !== null ? formatDuration(stats.overallAvgExecMinutes) : '—'}
                </p>
                <p className="mt-1 text-xs text-muted">{t('staff.stats.avgExecHint')}</p>
              </CardBody>
            </Card>
          </div>

          <Card>
            <CardBody>
              <h2 className="mb-4 text-sm font-semibold text-foreground">{t('staff.stats.byDepartment')}</h2>
              <BarList
                rows={stats.byDepartment.map((d) => ({
                  key: d.department,
                  label: t(`department.${d.department}` as const),
                  minutes: d.avgMinutes,
                  count: d.count,
                }))}
                t={t}
              />
            </CardBody>
          </Card>

          {stats.byOperator.length > 0 && (
            <Card>
              <CardBody>
                <h2 className="mb-1 text-sm font-semibold text-foreground">{t('staff.stats.byOperator')}</h2>
                <p className="mb-4 text-xs text-muted">{t('staff.stats.byOperatorHint')}</p>
                <BarList
                  rows={stats.byOperator.map((o) => ({ key: o.staffId, label: o.name, minutes: o.avgExecMinutes, count: o.count }))}
                  t={t}
                />
              </CardBody>
            </Card>
          )}
        </>
      )}
    </div>
  )
}

function BarList({
  rows,
  t,
}: {
  rows: { key: string; label: string; minutes: number; count: number }[]
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string
}) {
  const max = Math.max(...rows.map((r) => r.minutes), 1)
  return (
    <div className="space-y-3">
      {rows.map((r) => {
        const pct = Math.max(4, Math.round((r.minutes / max) * 100))
        return (
          <div key={r.key}>
            <div className="mb-1 flex items-baseline justify-between text-sm">
              <span className="font-medium text-foreground">{r.label}</span>
              <span className="text-muted">
                {formatDuration(r.minutes)} · {t('staff.stats.requestCount', { count: r.count })}
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-surface-2">
              <div className="h-full rounded-full bg-accent" style={{ width: `${pct}%` }} />
            </div>
          </div>
        )
      })}
    </div>
  )
}
