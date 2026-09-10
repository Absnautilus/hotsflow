import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { ToastStack } from '@/components/toast-stack'
import { EmptyState, IconInboxEmpty } from '@/components/empty-state'
import { cn } from '@/lib/cn'
import { cancelRequest, claimRequest, fetchQueue, subscribeToQueue } from '@/lib/staff-api'
import { useToasts } from '@/hooks/use-toasts'
import { useRequestAlerts } from '@/hooks/use-request-alerts'
import { playAlertSound } from '@/lib/beep'
import { RequestRow } from '@/staff/request-row'
import { InProgressColumn } from '@/staff/in-progress-column'
import { NewRequestForm } from '@/staff/new-request-form'
import { DEPARTMENTS } from '@/lib/constants'
import { useLocale } from '@/lib/i18n/locale-context'
import { getErrorMessage } from '@/lib/errors'
import type { Department } from '@/lib/types'
import type { QueuedRequest, StaffProfile } from '@/lib/staff-types'

type Tab = 'active' | 'done'
type DepartmentFilter = 'all' | Department

const DONE_PAGE_SIZE = 15

export function RequestQueue({ profile }: { profile: StaffProfile }) {
  const { t } = useLocale()
  const [queue, setQueue] = useState<QueuedRequest[] | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>('active')
  const [department, setDepartment] = useState<DepartmentFilter>('all')
  const [donePage, setDonePage] = useState(0)
  const [now, setNow] = useState(() => new Date())
  const { toasts, push, pushCard, dismiss } = useToasts()
  const knownIds = useRef<Set<string> | null>(null)

  const managesFrontDesk = profile.role === 'admin' || profile.role === 'master' || (profile.role === 'operatore' && profile.department === 'reception')
  const canReorder = managesFrontDesk

  const reload = useCallback(async () => {
    try {
      const data = await fetchQueue(profile.hotel_id)
      setLoadError(null)
      setQueue(data)

      if (knownIds.current === null) {
        knownIds.current = new Set(data.map((r) => r.id))
        return
      }
      for (const request of data) {
        if (!knownIds.current.has(request.id)) {
          knownIds.current.add(request.id)
          const itemName = request.request_types?.name ?? t('staff.queue.newRequestFallbackItem')
          const title = `${t('staff.newRequest.room')} ${request.room_number} · ${itemName}${request.quantity ? ` × ${request.quantity}` : ''}`
          pushCard({
            title,
            onAccept: () => void claimRequest(request.id, profile.id),
            onReject: () => void cancelRequest(request.id),
          })
          playAlertSound()
        }
      }
    } catch (err) {
      setLoadError(getErrorMessage(err))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pushCard, profile.id, profile.hotel_id])

  useEffect(() => {
    reload()
    const unsubscribe = subscribeToQueue(profile.hotel_id, () => {
      reload()
    })
    return unsubscribe
  }, [reload, profile.hotel_id])

  useEffect(() => {
    const interval = setInterval(() => setNow(new Date()), 30_000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    setDonePage(0)
  }, [department])

  const filtered = useMemo(
    () => (department === 'all' ? (queue ?? []) : (queue ?? []).filter((r) => r.assigned_department === department)),
    [queue, department],
  )

  const pending = filtered.filter((r) => r.status === 'requested')
  const inProgress = filtered.filter((r) => r.status === 'in_progress')
  const active = [...pending, ...inProgress]
  const done = useMemo(
    () =>
      filtered
        .filter((r) => r.status === 'completed' || r.status === 'cancelled')
        .sort((a, b) => new Date(b.completed_at ?? b.created_at).getTime() - new Date(a.completed_at ?? a.created_at).getTime()),
    [filtered],
  )

  const doneTotalPages = Math.max(1, Math.ceil(done.length / DONE_PAGE_SIZE))
  const clampedDonePage = Math.min(donePage, doneTotalPages - 1)
  const donePageItems = done.slice(clampedDonePage * DONE_PAGE_SIZE, clampedDonePage * DONE_PAGE_SIZE + DONE_PAGE_SIZE)

  const onAlert = useCallback((message: string, tone: 'info' | 'warning') => push(message, tone), [push])
  useRequestAlerts(active, onAlert)

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div className="min-w-0">
          <h1 className="font-head text-2xl font-bold tracking-tight text-foreground">{t('staff.queue.title')}</h1>
          <p className="mt-1 text-sm text-muted">
            {managesFrontDesk || !profile.department
              ? t('staff.queue.subtitle')
              : t('staff.queue.subtitleOwnDept', { department: t(`department.${profile.department}`) })}
          </p>
        </div>
        {managesFrontDesk && <DepartmentFilterBar value={department} onChange={setDepartment} />}
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <NewRequestForm staffId={profile.id} hotelId={profile.hotel_id} onCreated={reload} />
        <div className="flex gap-1 rounded-md bg-surface-2 p-1 sm:w-fit">
          <TabButton active={tab === 'active'} onClick={() => setTab('active')}>
            {t('staff.queue.tabActive')} ({active.length})
          </TabButton>
          <TabButton active={tab === 'done'} onClick={() => setTab('done')}>
            {t('staff.queue.tabDone')}
          </TabButton>
        </div>
      </div>

      {loadError ? (
        <div className="rounded-lg border border-bad-ink/25 bg-bad-bg p-4 text-sm text-bad-ink">
          {t('staff.queue.loadError', { error: loadError })}
        </div>
      ) : queue === null ? (
        <p className="text-sm text-muted">{t('staff.queue.loading')}</p>
      ) : tab === 'active' ? (
        active.length === 0 ? (
          <EmptyState
            icon={<IconInboxEmpty className="h-6 w-6" />}
            title={t('staff.queue.emptyActiveTitle')}
            description={t('staff.queue.emptyActiveDesc')}
          />
        ) : (
          <div className="grid grid-cols-1 items-start gap-5 xl:grid-cols-2">
            <section className="min-w-0">
              <h2 className="mb-3 flex items-center gap-2 px-1 text-sm font-semibold text-wait-ink">
                <span className="h-2 w-2 rounded-full bg-wait-ink" />
                {t('staff.queue.columnNew')} ({pending.length})
              </h2>
              {pending.length === 0 ? (
                <div className="rounded-lg border border-line bg-surface/70 px-4 py-6 text-sm text-muted">
                  {t('staff.queue.emptyNewShort')}
                </div>
              ) : (
                <div className="space-y-3">
                  {pending.map((request) => (
                    <RequestRow key={request.id} request={request} now={now} staffId={profile.id} mode="active" />
                  ))}
                </div>
              )}
            </section>
            <section className="min-w-0">
              <h2 className="mb-3 flex items-center gap-2 px-1 text-sm font-semibold text-prog-ink">
                <span className="h-2 w-2 rounded-full bg-prog-ink" />
                {t('staff.queue.columnInProgress')} ({inProgress.length})
              </h2>
              {inProgress.length === 0 ? (
                <div className="rounded-lg border border-line bg-surface/70 px-4 py-6 text-sm text-muted">
                  {t('staff.queue.emptyInProgressShort')}
                </div>
              ) : (
                <InProgressColumn items={inProgress} now={now} staffId={profile.id} canReorder={canReorder} onReordered={reload} />
              )}
            </section>
          </div>
        )
      ) : done.length === 0 ? (
        <EmptyState icon={<IconInboxEmpty className="h-6 w-6" />} title={t('staff.queue.emptyDoneTitle')} description={t('staff.queue.emptyDoneDesc')} />
      ) : (
        <div className="space-y-3">
          {donePageItems.map((request) => (
            <RequestRow key={request.id} request={request} now={now} staffId={profile.id} mode="done" />
          ))}
          {doneTotalPages > 1 && (
            <div className="flex items-center justify-center gap-3 pt-2">
              <button
                type="button"
                disabled={clampedDonePage === 0}
                onClick={() => setDonePage((p) => Math.max(0, p - 1))}
                className="cursor-pointer rounded-md border border-line bg-white px-3 py-1.5 text-sm text-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40"
              >
                {t('staff.queue.donePagePrev')}
              </button>
              <span className="text-xs text-muted">{t('staff.queue.donePageLabel', { page: clampedDonePage + 1, total: doneTotalPages })}</span>
              <button
                type="button"
                disabled={clampedDonePage >= doneTotalPages - 1}
                onClick={() => setDonePage((p) => Math.min(doneTotalPages - 1, p + 1))}
                className="cursor-pointer rounded-md border border-line bg-white px-3 py-1.5 text-sm text-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40"
              >
                {t('staff.queue.donePageNext')}
              </button>
            </div>
          )}
        </div>
      )}

      <ToastStack toasts={toasts} onDismiss={dismiss} />
    </div>
  )
}

function DepartmentFilterBar({ value, onChange }: { value: DepartmentFilter; onChange: (d: DepartmentFilter) => void }) {
  const { t } = useLocale()
  const options: DepartmentFilter[] = ['all', ...DEPARTMENTS]
  return (
    <div className="flex flex-wrap gap-1.5 lg:justify-end">
      {options.map((opt) => (
        <button
          key={opt}
          type="button"
          onClick={() => onChange(opt)}
          className={cn(
            'cursor-pointer rounded-full border px-3 py-1.5 text-xs font-medium transition-colors',
            value === opt ? 'border-accent bg-accent text-white' : 'border-line bg-surface text-muted hover:border-accent-soft-line hover:text-foreground',
          )}
        >
          {opt === 'all' ? t('staff.queue.filterAll') : t(`department.${opt}`)}
        </button>
      ))}
    </div>
  )
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex-1 cursor-pointer whitespace-nowrap rounded px-3 py-1.5 text-sm font-medium transition-colors sm:flex-none',
        active ? 'bg-white text-foreground shadow-sm' : 'text-muted hover:text-foreground',
      )}
    >
      {children}
    </button>
  )
}
