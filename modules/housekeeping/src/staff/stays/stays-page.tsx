import { useEffect, useState } from 'react'
import { ChevronsRight, History, LogOut, Pencil, Power } from 'lucide-react'
import type { PlatformHotelSettings } from '@/public/HousekeepingModule'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { EmptyState, IconBedEmpty } from '@/components/empty-state'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import { FieldError, FieldGroup, Input, Label, Select } from '@/components/ui/field'
import { DateTimePicker } from '@/components/ui/date-time-picker'
import { listRooms, type Room } from '@/lib/admin-api'
import { cancelStay, createStay, fetchRequestsForStay, listStays, updateCheckout, updateStay, type Stay, type StayRequest } from '@/lib/stays-api'
import { OperaImportPanel } from '@/staff/stays/opera-import-panel'
import { AutoText } from '@/components/auto-text'
import { formatElapsed, formatTime } from '@/lib/format'
import { useConfirm } from '@/components/confirm-dialog'
import { useLocale } from '@/lib/i18n/locale-context'
import { tenantIntegrityErrorRef } from '@/lib/errors'

function toLocalInputValue(iso: string): string {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

// Combines "days from now" with an "HH:mm" hotel-configured default into a
// datetime-local value -- e.g. today at the configured check-in time, or
// tomorrow at the configured check-out time, for a typical one-night stay.
function defaultDateTimeInput(daysFromNow: number, time: string): string {
  const [hours, minutes] = time.split(':').map(Number)
  const d = new Date()
  d.setDate(d.getDate() + daysFromNow)
  d.setHours(hours || 0, minutes || 0, 0, 0)
  return toLocalInputValue(d.toISOString())
}

export function StaysPage({ hotelId, hotelSettings }: { hotelId: string; hotelSettings?: PlatformHotelSettings }) {
  const { t } = useLocale()
  const [stays, setStays] = useState<Stay[] | null>(null)
  const [allRooms, setAllRooms] = useState<Room[]>([])
  const [error, setError] = useState<string | null>(null)
  const rooms = allRooms.filter((room) => room.active)

  async function reload() {
    const [s, r] = await Promise.all([listStays(hotelId), listRooms(hotelId)])
    setStays(s)
    setAllRooms(r)
  }

  useEffect(() => {
    reload().catch(() => setError(t('staff.stays.loadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hotelId])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.stays.title')}</h1>
        <p className="text-sm text-muted">{t('staff.stays.subtitle')}</p>
      </div>

      <NewStayForm hotelId={hotelId} rooms={rooms} hotelSettings={hotelSettings} onCreated={reload} />
      <OperaImportPanel hotelId={hotelId} rooms={rooms} onImported={reload} />

      {error && <p className="text-sm text-bad-ink">{error}</p>}

      <div className="space-y-3">
        {stays === null ? (
          <p className="text-sm text-muted">{t('staff.stays.loading')}</p>
        ) : stays.length === 0 ? (
          <EmptyState icon={<IconBedEmpty className="h-6 w-6" />} title={t('staff.stays.emptyTitle')} description={t('staff.stays.emptyDesc')} />
        ) : (
          stays.map((stay) => <StayRow key={stay.id} hotelId={hotelId} stay={stay} rooms={allRooms} onChanged={reload} />)
        )}
      </div>
    </div>
  )
}

function NewStayForm({ hotelId, rooms, hotelSettings, onCreated }: { hotelId: string; rooms: Room[]; hotelSettings?: PlatformHotelSettings; onCreated: () => Promise<void> }) {
  const { t } = useLocale()
  const [roomId, setRoomId] = useState('')
  const [lastName, setLastName] = useState('')
  const [checkIn, setCheckIn] = useState(() => hotelSettings?.checkInTime ? defaultDateTimeInput(0, hotelSettings.checkInTime) : '')
  const [checkOut, setCheckOut] = useState(() => hotelSettings?.checkOutTime ? defaultDateTimeInput(1, hotelSettings.checkOutTime) : '')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [createdPin, setCreatedPin] = useState<{ roomNumber: string; pin: string } | null>(null)

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setPending(true)
    setError(null)
    setCreatedPin(null)
    try {
      const stay = await createStay({
        hotelId,
        roomId,
        guestLastName: lastName.trim(),
        checkInAt: new Date(checkIn).toISOString(),
        checkOutAt: new Date(checkOut).toISOString(),
      })
      setCreatedPin({ roomNumber: stay.rooms?.room_number ?? '', pin: stay.guest_pin })
      setLastName('')
      setCheckIn(hotelSettings?.checkInTime ? defaultDateTimeInput(0, hotelSettings.checkInTime) : '')
      setCheckOut(hotelSettings?.checkOutTime ? defaultDateTimeInput(1, hotelSettings.checkOutTime) : '')
      await onCreated()
    } catch (err) {
      const ref = tenantIntegrityErrorRef(err)
      setError(ref ? t('staff.stays.tenantMismatchError', { ref }) : t('staff.stays.addError'))
    } finally {
      setPending(false)
    }
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="text-sm font-semibold text-foreground">{t('staff.stays.addTitle')}</h2>
      </CardHeader>
      <CardBody>
        {createdPin && (
          <div className="mb-4 rounded-lg border border-ok-ink/25 bg-ok-bg p-3 text-sm text-ok-ink">
            {t('staff.stays.activatedBanner', { room: createdPin.roomNumber })}{' '}
            <span className="font-mono text-base font-semibold tracking-widest">{createdPin.pin}</span>
            <br />
            {t('staff.stays.communicatePin')}
          </div>
        )}
        <form onSubmit={onSubmit}>
          <div className="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
            <FieldGroup>
              <Label htmlFor="room" required>
                {t('staff.stays.room')}
              </Label>
              <Select id="room" required value={roomId} onChange={(e) => setRoomId(e.target.value)}>
                <option value="" disabled>
                  {t('staff.stays.selectPlaceholder')}
                </option>
                {rooms.map((room) => (
                  <option key={room.id} value={room.id}>
                    {room.room_number}
                  </option>
                ))}
              </Select>
            </FieldGroup>
            <FieldGroup>
              <Label htmlFor="lastName" required>
                {t('staff.stays.guestLastName')}
              </Label>
              <Input id="lastName" required value={lastName} onChange={(e) => setLastName(e.target.value)} />
            </FieldGroup>
            <FieldGroup>
              <Label htmlFor="checkIn" required>
                {t('staff.stays.checkIn')}
              </Label>
              <DateTimePicker id="checkIn" required value={checkIn} onChange={setCheckIn} />
            </FieldGroup>
            <FieldGroup>
              <Label htmlFor="checkOut" required>
                {t('staff.stays.checkOut')}
              </Label>
              <DateTimePicker id="checkOut" required value={checkOut} onChange={setCheckOut} />
            </FieldGroup>
          </div>
          <FieldError>{error ?? undefined}</FieldError>
          <div className="flex justify-end">
            <Button type="submit" disabled={pending}>
              {pending ? t('staff.stays.submitPending') : t('staff.stays.submit')}
            </Button>
          </div>
        </form>
      </CardBody>
    </Card>
  )
}

function StayRow({ hotelId, stay, rooms, onChanged }: { hotelId: string; stay: Stay; rooms: Room[]; onChanged: () => Promise<void> }) {
  const { t } = useLocale()
  const [editingCheckout, setEditingCheckout] = useState(false)
  const [checkOut, setCheckOut] = useState(toLocalInputValue(stay.check_out_at))
  const [editingDetails, setEditingDetails] = useState(false)
  const [detailsRoomId, setDetailsRoomId] = useState(stay.room_id)
  const [detailsGuestLastName, setDetailsGuestLastName] = useState(stay.guest_last_name)
  const [detailsCheckIn, setDetailsCheckIn] = useState(toLocalInputValue(stay.check_in_at))
  const [detailsCheckOut, setDetailsCheckOut] = useState(toLocalInputValue(stay.check_out_at))
  const [pending, setPending] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [confirmDialog, confirm] = useConfirm()
  const [historyOpen, setHistoryOpen] = useState(false)
  const [history, setHistory] = useState<StayRequest[] | null>(null)

  function startEditingDetails() {
    setDetailsRoomId(stay.room_id)
    setDetailsGuestLastName(stay.guest_last_name)
    setDetailsCheckIn(toLocalInputValue(stay.check_in_at))
    setDetailsCheckOut(toLocalInputValue(stay.check_out_at))
    setEditingDetails(true)
  }

  async function toggleHistory() {
    if (historyOpen) {
      setHistoryOpen(false)
      return
    }
    setHistoryOpen(true)
    if (history === null) {
      const items = await fetchRequestsForStay(stay.id, hotelId).catch(() => [])
      setHistory(items)
    }
  }

  // Returns whether the action actually succeeded so a caller chaining a
  // "close the inline editor" step can skip it on failure -- the person
  // should see the error and be able to retry, not lose what they typed.
  async function run(action: () => Promise<void>): Promise<boolean> {
    setPending(true)
    setActionError(null)
    try {
      await action()
      await onChanged()
      return true
    } catch {
      setActionError(t('staff.stays.actionError'))
      return false
    } finally {
      setPending(false)
    }
  }

  async function onDeactivate() {
    const ok = await confirm({
      title: t('staff.stays.deactivateTitle'),
      description: t('staff.stays.deactivateDesc', { room: stay.rooms?.room_number ?? '', name: stay.guest_last_name, pin: stay.guest_pin }),
      confirmLabel: t('staff.stays.deactivateConfirm'),
    })
    if (ok) await run(() => cancelStay(stay.id))
  }

  return (
    <Card>
      {confirmDialog}
      <CardBody>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="font-medium text-foreground">
              {t('staff.stays.room')} {stay.rooms?.room_number} · {stay.guest_last_name}
            </p>
            <p className="text-sm text-muted">
              {t('staff.stays.checkoutLabel')} {new Date(stay.check_out_at).toLocaleString('it-IT', { dateStyle: 'short', timeStyle: 'short' })} ·{' '}
              {t('staff.stays.pinLabel')} <span className="font-mono font-semibold tracking-widest text-foreground">{stay.guest_pin}</span>
            </p>
          </div>
          {editingDetails ? (
            <div className="grid w-full grid-cols-1 gap-3 sm:grid-cols-2">
              <FieldGroup className="mb-0">
                <Label htmlFor={`edit-room-${stay.id}`} required>
                  {t('staff.stays.room')}
                </Label>
                <Select id={`edit-room-${stay.id}`} required value={detailsRoomId} onChange={(e) => setDetailsRoomId(e.target.value)}>
                  {rooms.map((room) => (
                    <option key={room.id} value={room.id}>
                      {room.room_number}
                    </option>
                  ))}
                </Select>
              </FieldGroup>
              <FieldGroup className="mb-0">
                <Label htmlFor={`edit-guest-${stay.id}`} required>
                  {t('staff.stays.guestLastName')}
                </Label>
                <Input id={`edit-guest-${stay.id}`} required value={detailsGuestLastName} onChange={(e) => setDetailsGuestLastName(e.target.value)} />
              </FieldGroup>
              <FieldGroup className="mb-0">
                <Label htmlFor={`edit-checkin-${stay.id}`} required>
                  {t('staff.stays.checkIn')}
                </Label>
                <DateTimePicker id={`edit-checkin-${stay.id}`} required value={detailsCheckIn} onChange={setDetailsCheckIn} />
              </FieldGroup>
              <FieldGroup className="mb-0">
                <Label htmlFor={`edit-checkout-${stay.id}`} required>
                  {t('staff.stays.checkOut')}
                </Label>
                <DateTimePicker id={`edit-checkout-${stay.id}`} required value={detailsCheckOut} onChange={setDetailsCheckOut} />
              </FieldGroup>
              <div className="flex items-center gap-2 sm:col-span-2">
                <Button
                  size="sm"
                  disabled={pending || !detailsRoomId || !detailsGuestLastName.trim()}
                  onClick={() =>
                    run(() =>
                      updateStay(stay.id, {
                        roomId: detailsRoomId,
                        guestLastName: detailsGuestLastName.trim(),
                        checkInAt: new Date(detailsCheckIn).toISOString(),
                        checkOutAt: new Date(detailsCheckOut).toISOString(),
                      }),
                    ).then((ok) => { if (ok) setEditingDetails(false) })
                  }
                >
                  {t('staff.stays.save')}
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setEditingDetails(false)}>
                  {t('staff.stays.cancel')}
                </Button>
              </div>
            </div>
          ) : editingCheckout ? (
            <div className="flex items-center gap-2">
              <DateTimePicker value={checkOut} onChange={setCheckOut} />
              <Button
                size="sm"
                disabled={pending}
                onClick={() => run(() => updateCheckout(stay.id, new Date(checkOut).toISOString())).then((ok) => { if (ok) setEditingCheckout(false) })}
              >
                {t('staff.stays.save')}
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setEditingCheckout(false)}>
                {t('staff.stays.cancel')}
              </Button>
            </div>
          ) : (
            <div className="flex flex-wrap gap-2">
              <IconButton tone="neutral" icon={Pencil} label={t('staff.stays.edit')} disabled={pending} onClick={startEditingDetails} />
              <IconButton
                tone="neutral"
                icon={History}
                label={historyOpen ? t('staff.stays.hideHistory') : t('staff.stays.showHistory')}
                disabled={pending}
                onClick={toggleHistory}
              />
              <IconButton tone="neutral" icon={ChevronsRight} label={t('staff.stays.extend')} disabled={pending} onClick={() => setEditingCheckout(true)} />
              <IconButton
                tone="neutral"
                icon={LogOut}
                label={t('staff.stays.checkoutNow')}
                disabled={pending}
                onClick={() => run(() => updateCheckout(stay.id, new Date().toISOString()))}
              />
              <IconButton tone="danger" icon={Power} label={t('staff.stays.deactivate')} disabled={pending} onClick={onDeactivate} />
            </div>
          )}
        </div>
        {actionError && <p className="mt-2 text-xs font-semibold text-bad-ink" role="alert">{actionError}</p>}

        {historyOpen && (
          <div className="mt-3 border-t border-line pt-3">
            {history === null ? (
              <p className="text-sm text-muted">{t('staff.stays.historyLoading')}</p>
            ) : history.length === 0 ? (
              <p className="text-sm text-muted">{t('staff.stays.historyEmpty')}</p>
            ) : (
              <ul className="space-y-1.5">
                {history.map((r) => (
                  <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 text-sm">
                    <span className="text-foreground">
                      <AutoText text={r.request_types?.name ?? t('staff.row.defaultTypeName')} translations={r.request_types?.name_i18n} /> ·{' '}
                      <span className="text-muted">{t(`department.${r.assigned_department}` as const)}</span>
                    </span>
                    <span className="text-xs text-muted">
                      {formatTime(r.created_at)} · {t(`statusLabel.${r.status}` as const)}
                      {r.status === 'completed' && r.completed_at ? ` · ${formatElapsed(r.created_at, new Date(r.completed_at))}` : ''}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </CardBody>
    </Card>
  )
}
