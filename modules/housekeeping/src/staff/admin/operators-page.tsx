import { useEffect, useState } from 'react'
import { Card, CardBody } from '@/components/ui/card'
import { LinkButton } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { listStaff, setStaffActive, type OperatorSummary } from '@/lib/admin-api'
import { useLocale } from '@/lib/i18n/locale-context'
import type { TranslationKey } from '@/lib/i18n/dictionaries'
import type { StaffRole } from '@/lib/types'
import type { StaffProfile } from '@/lib/staff-types'
import { useConfirm } from '@/components/confirm-dialog'
import type { PlatformStaffManagementLink } from '@/public/HousekeepingModule'

const ROLE_KEY: Record<StaffRole, TranslationKey> = {
  master: 'role.master',
  admin: 'role.admin',
  operatore: 'role.operatore',
}

export function OperatorsPage({
  profile,
  platformStaffManagement,
  hotelId,
}: {
  profile: StaffProfile
  // Account creation and lifecycle live only in Hotsflow Team -- this screen
  // is always embedded today, so this is always supplied by the shell (see
  // HousekeepingModuleGate.tsx). It stays optional in the type only for the
  // legacy, currently-unreachable standalone rendering path in staff-app.tsx;
  // there is no supported way to create a native Housekeeping account from
  // this page regardless.
  platformStaffManagement?: PlatformStaffManagementLink
  /** Embedded mode only: scopes the roster to this hotel. Omit in standalone. */
  hotelId?: string
}) {
  const { t } = useLocale()
  const isMaster = profile.role === 'master'
  const [staff, setStaff] = useState<OperatorSummary[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [confirmDialog, confirm] = useConfirm()

  async function reload() {
    setStaff(await listStaff(hotelId))
  }

  useEffect(() => {
    reload().catch(() => setError(t('staff.operators.loadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hotelId])

  async function onToggle(person: OperatorSummary) {
    if (person.active) {
      const ok = await confirm({
        title: t('staff.operators.deactivateTitle'),
        description: t('staff.operators.deactivateDesc', { name: person.name }),
        confirmLabel: t('staff.operators.deactivateConfirm'),
      })
      if (!ok) return
    }
    setError(null)
    const next = !person.active
    setStaff((current) => current?.map((p) => (p.id === person.id ? { ...p, active: next } : p)) ?? current)
    try {
      await setStaffActive(person.id, next)
    } catch {
      setStaff((current) => current?.map((p) => (p.id === person.id ? { ...p, active: person.active } : p)) ?? current)
      setError(t('staff.operators.toggleError'))
    }
  }

  return (
    <div className="space-y-6">
      {confirmDialog}
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.operators.title')}</h1>
      </div>

      <Card>
        <CardBody>
          <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
            <p className="text-sm text-muted">
              {platformStaffManagement?.description ?? t('staff.operators.accountsManagedElsewhere')}
            </p>
            {platformStaffManagement && (
              <LinkButton className="shrink-0" to={platformStaffManagement.href}>
                {platformStaffManagement.label}
              </LinkButton>
            )}
          </div>
        </CardBody>
      </Card>

      {error && <p role="alert" className="text-sm text-bad-ink">{error}</p>}

      <div className="overflow-x-auto rounded-lg border border-line bg-white">
        <table aria-label={t('staff.operators.title')} className="w-full min-w-max text-sm">
          <thead className="bg-surface-2 text-left text-xs uppercase text-muted">
            <tr>
              <th className="px-4 py-2">{t('staff.operators.colName')}</th>
              <th className="px-4 py-2">{t('staff.operators.colRole')}</th>
              <th className="px-4 py-2">{t('staff.operators.colAccess')}</th>
              <th className="px-4 py-2">{t('staff.operators.colStatus')}</th>
              <th className="px-4 py-2" />
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {staff?.map((person) => {
              // grant-housekeeping-access always inserts role: 'admin' for a
              // Team-bridged member regardless of their real Hotsflow role
              // (see that function's own comment -- Housekeeping's
              // 'operatore' role requires a native login_username, which a
              // Team-bridged account never has). role: 'admin' with no
              // login_username is exactly that case today and going
              // forward (native account creation no longer exists), so
              // showing it as "Admin" here would misrepresent a real
              // Hotsflow operatore. A genuine 'master' row is never
              // produced by the bridge, so that label stays trustworthy.
              const roleLabel =
                person.role === 'operatore'
                  ? t(`department.${person.department ?? 'reception'}`)
                  : person.role === 'admin' && !person.login_username
                    ? '—'
                    : t(ROLE_KEY[person.role])
              // an admin can only ever touch operatori; only master can deactivate an admin,
              // and nobody deactivates a master from this screen
              const canToggle = !platformStaffManagement && (person.role === 'operatore' || (person.role === 'admin' && isMaster))
              return (
                <tr key={person.id}>
                  <td className="px-4 py-2 font-medium text-foreground">{person.name}</td>
                  <td className="px-4 py-2 text-muted">{roleLabel}</td>
                  <td className="px-4 py-2 text-muted">{person.login_username ?? <span className="text-muted">{t('staff.operators.accessEmail')}</span>}</td>
                  <td className="px-4 py-2">
                    <Badge className={person.active ? 'bg-ok-bg text-ok-ink' : undefined}>
                      {person.active ? t('staff.operators.statusActive') : t('staff.operators.statusInactive')}
                    </Badge>
                  </td>
                  <td className="px-4 py-2 text-right">
                    {canToggle && (
                      <button
                        type="button"
                        className="min-h-11 cursor-pointer px-2 text-xs text-muted hover:text-foreground"
                        onClick={() => onToggle(person)}
                      >
                        {person.active ? t('staff.operators.deactivate') : t('staff.operators.reactivate')}
                      </button>
                    )}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
