import { useEffect, useState } from 'react'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { FieldError, FieldGroup, Label, Select, Textarea } from '@/components/ui/field'
import { AutoText } from '@/components/auto-text'
import { listMenu, listRooms, type Room } from '@/lib/admin-api'
import { createStaffRequest } from '@/lib/staff-api'
import { useLocale } from '@/lib/i18n/locale-context'
import { getErrorMessage, tenantIntegrityErrorRef } from '@/lib/errors'
import type { RequestCategoryAdmin, RequestTypeAdmin } from '@/lib/admin-api'

export function NewRequestForm({ staffId, hotelId, onCreated }: { staffId: string; hotelId: string; onCreated: () => void }) {
  const { t } = useLocale()
  const [open, setOpen] = useState(false)
  const [rooms, setRooms] = useState<Room[]>([])
  const [categories, setCategories] = useState<RequestCategoryAdmin[]>([])
  const [types, setTypes] = useState<RequestTypeAdmin[]>([])
  const [roomId, setRoomId] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [typeId, setTypeId] = useState('')
  const [note, setNote] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    Promise.all([listRooms(hotelId), listMenu(hotelId)]).then(([roomList, menu]) => {
      const activeRooms = roomList.filter((r) => r.active)
      setRooms(activeRooms)
      setRoomId((c) => c || (activeRooms[0]?.id ?? ''))
      const activeCategories = menu.categories.filter((c) => c.active)
      setCategories(activeCategories)
      setCategoryId((c) => c || (activeCategories[0]?.id ?? ''))
      setTypes(menu.types.filter((t) => t.active))
    })
  }, [open, hotelId])

  const typesForCategory = types.filter((t) => t.category_id === categoryId)

  useEffect(() => {
    setTypeId(typesForCategory[0]?.id ?? '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [categoryId])

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault()
    const room = rooms.find((r) => r.id === roomId)
    if (!room || !typeId) return
    setPending(true)
    setError(null)
    try {
      await createStaffRequest({ hotelId, roomNumber: room.room_number, requestTypeId: typeId, note: note.trim() || null, staffId })
      setNote('')
      setOpen(false)
      onCreated()
    } catch (err) {
      const ref = tenantIntegrityErrorRef(err)
      setError(ref ? t('staff.newRequest.tenantMismatchError', { ref }) : getErrorMessage(err) || t('staff.newRequest.error'))
    } finally {
      setPending(false)
    }
  }

  if (!open) {
    return (
      <Button variant="outline" onClick={() => setOpen(true)}>
        {t('staff.newRequest.toggle')}
      </Button>
    )
  }

  return (
    <Card className="mb-5">
      <CardHeader>
        <h2 className="text-sm font-semibold text-foreground">{t('staff.newRequest.title')}</h2>
      </CardHeader>
      <CardBody>
        <form onSubmit={onSubmit}>
          <div className="grid grid-cols-1 gap-x-4 sm:grid-cols-3">
            <FieldGroup>
              <Label htmlFor="sr-room" required>
                {t('staff.newRequest.room')}
              </Label>
              <Select id="sr-room" required value={roomId} onChange={(e) => setRoomId(e.target.value)}>
                {rooms.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.room_number}
                  </option>
                ))}
              </Select>
            </FieldGroup>
            <FieldGroup>
              <Label htmlFor="sr-category" required>
                {t('staff.newRequest.category')}
              </Label>
              <Select id="sr-category" required value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    <AutoText text={c.name} translations={c.name_i18n} />
                  </option>
                ))}
              </Select>
            </FieldGroup>
            <FieldGroup>
              <Label htmlFor="sr-type" required>
                {t('staff.newRequest.what')}
              </Label>
              <Select id="sr-type" required value={typeId} onChange={(e) => setTypeId(e.target.value)}>
                {typesForCategory.map((rt) => (
                  <option key={rt.id} value={rt.id}>
                    <AutoText text={rt.name} translations={rt.name_i18n} />
                  </option>
                ))}
              </Select>
            </FieldGroup>
          </div>
          <FieldGroup>
            <Label htmlFor="sr-note">{t('staff.newRequest.notes')}</Label>
            <Textarea id="sr-note" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder={t('staff.newRequest.notesPlaceholder')} />
          </FieldGroup>
          <FieldError>{error ?? undefined}</FieldError>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={() => setOpen(false)}>
              {t('staff.newRequest.cancel')}
            </Button>
            <Button type="submit" disabled={pending || !roomId || !typeId}>
              {pending ? t('staff.newRequest.submitPending') : t('staff.newRequest.submit')}
            </Button>
          </div>
        </form>
      </CardBody>
    </Card>
  )
}
