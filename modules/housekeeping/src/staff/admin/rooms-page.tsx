import { useEffect, useState } from 'react'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import { IconTrash } from '@/components/ui/action-icons'
import { FieldError, FieldGroup, Input, Label } from '@/components/ui/field'
import { SwitchControl } from '@/components/ui/switch'
import {
  Table,
  TableBody,
  TableCell,
  TableFrame,
  TableHead,
  TableHeaderCell,
  TableRow,
} from '@/components/ui/table'
import { createRoom, deleteRoom, listRooms, setRoomActive, type Room } from '@/lib/admin-api'
import { useConfirm } from '@/components/confirm-dialog'
import { useLocale } from '@/lib/i18n/locale-context'

export function RoomsPage({ hotelId }: { hotelId: string }) {
  const { t } = useLocale()
  const [rooms, setRooms] = useState<Room[] | null>(null)
  const [hiddenRoomIds, setHiddenRoomIds] = useState<Set<string>>(new Set())
  const [roomNumber, setRoomNumber] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)
  const [confirmDialog, confirm] = useConfirm()
  const visibleRooms = rooms?.filter((room) => !hiddenRoomIds.has(room.id)) ?? null

  async function reload() {
    setRooms(await listRooms(hotelId))
  }

  useEffect(() => {
    reload().catch(() => setError(t('staff.rooms.loadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hotelId])

  async function onToggle(room: Room) {
    if (room.active) {
      const ok = await confirm({
        title: t('staff.rooms.deactivateTitle'),
        description: t('staff.rooms.deactivateDesc', { room: room.room_number }),
        confirmLabel: t('staff.rooms.deactivateConfirm'),
      })
      if (!ok) return
    }
    setError(null)
    try {
      await setRoomActive(room.id, !room.active)
      await reload()
    } catch {
      setError(t('staff.rooms.toggleError'))
    }
  }

  // A room with recorded stays is kept by the FK guard (see deleteRoom's
  // comment) -- that's an expected outcome, so it's still hidden here
  // without an error; the person asking to remove it doesn't need a
  // Postgres constraint explained, and deactivating is the right next step.
  // Any other failure (e.g. blocked by RLS) is a real error and must be
  // surfaced instead of leaving the room silently un-deleted.
  async function onDelete(room: Room) {
    const ok = await confirm({
      title: t('staff.rooms.deleteTitle'),
      description: t('staff.rooms.deleteDesc', { room: room.room_number }),
      confirmLabel: t('staff.rooms.deleteConfirm'),
    })
    if (!ok) return
    setError(null)
    try {
      await deleteRoom(room.id)
      setHiddenRoomIds((current) => new Set(current).add(room.id))
    } catch (err) {
      if (err && typeof err === 'object' && 'code' in err && err.code === '23503') {
        setHiddenRoomIds((current) => new Set(current).add(room.id))
        return
      }
      setError(t('staff.rooms.deleteError'))
    }
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    setPending(true)
    setError(null)
    try {
      await createRoom(roomNumber.trim())
      setRoomNumber('')
      await reload()
    } catch {
      setError(t('staff.rooms.addError'))
    } finally {
      setPending(false)
    }
  }

  return (
    <div className="space-y-6">
      {confirmDialog}
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.rooms.title')}</h1>
        <p className="text-sm text-muted">{t('staff.rooms.subtitle')}</p>
      </div>

      <Card>
        <CardHeader>
          <h2 className="text-sm font-semibold text-foreground">{t('staff.rooms.addTitle')}</h2>
        </CardHeader>
        <CardBody>
          <form onSubmit={onSubmit} className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <FieldGroup className="mb-0 min-w-0 flex-1">
              <Label htmlFor="roomNumber" required>
                {t('staff.rooms.roomNumber')}
              </Label>
              <Input id="roomNumber" required value={roomNumber} onChange={(e) => setRoomNumber(e.target.value)} />
            </FieldGroup>
            <Button type="submit" disabled={pending} className="w-full sm:w-auto">
              {t('staff.rooms.add')}
            </Button>
          </form>
          <FieldError>{error ?? undefined}</FieldError>
        </CardBody>
      </Card>

      <TableFrame>
        <Table>
          <TableHead>
            <tr>
              <TableHeaderCell>{t('staff.rooms.colRoom')}</TableHeaderCell>
              <TableHeaderCell>{t('staff.rooms.colStatus')}</TableHeaderCell>
              <TableHeaderCell className="w-px" />
            </tr>
          </TableHead>
          <TableBody>
            {visibleRooms?.map((room) => (
              <TableRow key={room.id}>
                <TableCell className="font-medium text-foreground">{room.room_number}</TableCell>
                <TableCell>
                  <SwitchControl
                    checked={room.active}
                    onCheckedChange={() => onToggle(room)}
                    aria-label={room.active ? t('staff.rooms.deactivate') : t('staff.rooms.reactivate')}
                  />
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end gap-2">
                    <IconButton
                      tone="danger"
                      icon={IconTrash}
                      label={t('staff.rooms.delete')}
                      onClick={() => onDelete(room)}
                    />
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableFrame>
    </div>
  )
}
