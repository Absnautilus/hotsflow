import { useEffect, useState } from 'react'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { Button, LinkButton } from '@/components/ui/button'
import { FieldError, FieldGroup, Input, Label, Select } from '@/components/ui/field'
import { Badge } from '@/components/ui/badge'
import {
  createStaffAccount,
  listHotels,
  listStaff,
  setStaffActive,
  type Hotel,
  type OperatorSummary,
} from '@/lib/admin-api'
import { isValidPin } from '@/lib/operator-login'
import { useLocale } from '@/lib/i18n/locale-context'
import { getErrorMessage } from '@/lib/errors'
import type { TranslationKey } from '@/lib/i18n/dictionaries'
import type { StaffDepartment, StaffRole } from '@/lib/types'
import type { StaffProfile } from '@/lib/staff-types'
import { useConfirm } from '@/components/confirm-dialog'
import type { PlatformStaffManagementLink } from '@/public/HousekeepingModule'

function describeCreateAccountError(err: unknown, t: (key: TranslationKey, vars?: Record<string, string | number>) => string): string {
  const message = getErrorMessage(err)
  if (/non-2xx|failed to send a request|not found/i.test(message)) {
    return t('staff.operators.createErrorFunctionMissing')
  }
  return t('staff.operators.createError', { message })
}

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
    try {
      await setStaffActive(person.id, !person.active)
      await reload()
    } catch {
      setError(t('staff.operators.toggleError'))
    }
  }

  return (
    <div className="space-y-6">
      {confirmDialog}
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.operators.title')}</h1>
        {!platformStaffManagement && (
          <p className="text-sm text-muted">{isMaster ? t('staff.operators.subtitleMaster') : t('staff.operators.subtitleAdmin')}</p>
        )}
      </div>

      {platformStaffManagement ? (
        <Card>
          <CardBody>
            <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
              <p className="text-sm text-muted">{platformStaffManagement.description}</p>
              <LinkButton className="shrink-0" to={platformStaffManagement.href}>
                {platformStaffManagement.label}
              </LinkButton>
            </div>
          </CardBody>
        </Card>
      ) : (
        <NewStaffForm isMaster={isMaster} onCreated={reload} />
      )}

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
              const roleLabel = person.role === 'operatore' ? t(`department.${person.department ?? 'reception'}`) : t(ROLE_KEY[person.role])
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

function NewStaffForm({ isMaster, onCreated }: { isMaster: boolean; onCreated: () => Promise<void> }) {
  const [name, setName] = useState('')
  const [role, setRole] = useState<'admin' | 'operatore'>('operatore')
  const [department, setDepartment] = useState<StaffDepartment>('housekeeping')
  const { t } = useLocale()
  const [username, setUsername] = useState('')
  const [pin, setPin] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [hotels, setHotels] = useState<Hotel[]>([])
  const [hotelId, setHotelId] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!isMaster) return
    listHotels()
      .then((list) => {
        setHotels(list)
        setHotelId((current) => current || (list[0]?.id ?? ''))
      })
      .catch(() => setError(t('staff.operators.hotelsLoadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isMaster])

  const effectiveRole = isMaster ? role : 'operatore'

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (effectiveRole === 'operatore' && !isValidPin(pin)) {
      setError(t('staff.operators.pinError'))
      return
    }

    setPending(true)
    try {
      if (effectiveRole === 'admin') {
        await createStaffAccount({ name: name.trim(), role: 'admin', email: email.trim(), password, hotelId })
      } else {
        await createStaffAccount({
          name: name.trim(),
          role: 'operatore',
          username: username.trim(),
          pin,
          department,
          hotelId: isMaster ? hotelId : undefined,
        })
      }
      setName('')
      setUsername('')
      setPin('')
      setEmail('')
      setPassword('')
      await onCreated()
    } catch (err) {
      setError(describeCreateAccountError(err, t))
    } finally {
      setPending(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="text-sm font-semibold text-foreground">{isMaster ? t('staff.operators.newAccount') : t('staff.operators.newOperator')}</h2>
      </CardHeader>
      <CardBody>
        <form onSubmit={onSubmit}>
          <div className="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
            <FieldGroup>
              <Label htmlFor="name" required>
                {t('staff.operators.name')}
              </Label>
              <Input id="name" required value={name} onChange={(e) => setName(e.target.value)} />
            </FieldGroup>

            {isMaster && (
              <FieldGroup>
                <Label htmlFor="hotel" required>
                  {t('staff.operators.hotel')}
                </Label>
                <Select id="hotel" required value={hotelId} onChange={(e) => setHotelId(e.target.value)}>
                  {hotels.map((h) => (
                    <option key={h.id} value={h.id}>
                      {h.name}
                    </option>
                  ))}
                </Select>
              </FieldGroup>
            )}

            {isMaster && (
              <FieldGroup>
                <Label htmlFor="role" required>
                  {t('staff.operators.role')}
                </Label>
                <Select id="role" value={role} onChange={(e) => setRole(e.target.value as 'admin' | 'operatore')}>
                  <option value="operatore">{t('staff.operators.roleOperatore')}</option>
                  <option value="admin">{t('staff.operators.roleAdminHotel')}</option>
                </Select>
              </FieldGroup>
            )}

            {effectiveRole === 'operatore' && (
              <FieldGroup>
                <Label htmlFor="department" required>
                  {t('staff.operators.department')}
                </Label>
                <Select id="department" value={department} onChange={(e) => setDepartment(e.target.value as StaffDepartment)}>
                  <option value="housekeeping">{t('department.housekeeping')}</option>
                  <option value="reception">{t('department.reception')}</option>
                  <option value="maintenance">{t('department.maintenance')}</option>
                </Select>
              </FieldGroup>
            )}

            {effectiveRole === 'operatore' ? (
              <>
                <FieldGroup>
                  <Label htmlFor="username" required>
                    {t('staff.operators.username')}
                  </Label>
                  <Input id="username" required value={username} onChange={(e) => setUsername(e.target.value)} placeholder={t('staff.operators.usernamePlaceholder')} />
                </FieldGroup>
                <FieldGroup>
                  <Label htmlFor="pin" required>
                    {t('staff.operators.pin6')}
                  </Label>
                  <Input
                    id="pin"
                    inputMode="numeric"
                    maxLength={6}
                    required
                    value={pin}
                    onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  />
                </FieldGroup>
              </>
            ) : (
              <>
                <FieldGroup>
                  <Label htmlFor="email" required>
                    {t('staff.operators.email')}
                  </Label>
                  <Input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
                </FieldGroup>
                <FieldGroup>
                  <Label htmlFor="password" required>
                    {t('staff.operators.passwordInitial')}
                  </Label>
                  <Input id="password" type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} />
                </FieldGroup>
              </>
            )}
          </div>
          <FieldError>{error ?? undefined}</FieldError>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending || (isMaster && !hotelId)}>
              {pending ? t('staff.operators.submitPending') : t('staff.operators.submit')}
            </Button>
          </div>
        </form>
      </CardBody>
    </Card>
  )
}
