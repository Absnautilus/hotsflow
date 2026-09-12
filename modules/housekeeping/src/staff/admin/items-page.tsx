import { useEffect, useState } from 'react'
import { Card, CardBody, CardHeader } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import { Languages, Trash2 } from 'lucide-react'
import { FieldError, FieldGroup, Input, Label, Select, Textarea } from '@/components/ui/field'
import { Switch, SwitchControl } from '@/components/ui/switch'
import { AutoText } from '@/components/auto-text'
import {
  createRequestCategory,
  createRequestType,
  listMenu,
  setRequestCategoryActive,
  setRequestTypeActive,
  updateRequestCategoryTranslations,
  updateRequestTypeTranslations,
  type RequestCategoryAdmin,
  type RequestTypeAdmin,
} from '@/lib/admin-api'
import { DEPARTMENTS } from '@/lib/constants'
import { LOCALES } from '@/lib/i18n/locales'
import { useConfirm } from '@/components/confirm-dialog'
import { useLocale } from '@/lib/i18n/locale-context'
import type { Department } from '@/lib/types'

const TRANSLATABLE_LOCALES = LOCALES.filter((l) => l.code !== 'it')

export function ItemsPage({ hotelId }: { hotelId: string }) {
  const { t } = useLocale()
  const [categories, setCategories] = useState<RequestCategoryAdmin[]>([])
  const [types, setTypes] = useState<RequestTypeAdmin[]>([])
  const [error, setError] = useState<string | null>(null)
  const [confirmDialog, confirm] = useConfirm()
  const [removedCategoryIds, setRemovedCategoryIds] = useState<Set<string>>(new Set())
  const [removedTypeIds, setRemovedTypeIds] = useState<Set<string>>(new Set())

  async function reload() {
    const menu = await listMenu(hotelId)
    setCategories(menu.categories)
    setTypes(menu.types)
  }

  useEffect(() => {
    reload().catch(() => setError(t('staff.items.loadError')))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hotelId])

  async function onToggleCategory(category: RequestCategoryAdmin) {
    if (category.active) {
      const ok = await confirm({ title: t('staff.items.categoryDeactivateTitle'), description: t('staff.items.categoryDeactivateDesc', { name: category.name }), confirmLabel: t('staff.items.categoryDeactivateConfirm') })
      if (!ok) return
    }
    setError(null)
    const next = !category.active
    setCategories((current) => current.map((c) => (c.id === category.id ? { ...c, active: next } : c)))
    try {
      await setRequestCategoryActive(category.id, next)
    } catch {
      setCategories((current) => current.map((c) => (c.id === category.id ? { ...c, active: category.active } : c)))
      setError(t('staff.items.toggleError'))
    }
  }

  async function onToggleItem(item: RequestTypeAdmin) {
    if (item.active) {
      const ok = await confirm({ title: t('staff.items.deactivateTitle'), description: t('staff.items.deactivateDesc', { name: item.name }), confirmLabel: t('staff.items.deactivateConfirm') })
      if (!ok) return
    }
    setError(null)
    const next = !item.active
    setTypes((current) => current.map((rt) => (rt.id === item.id ? { ...rt, active: next } : rt)))
    try {
      await setRequestTypeActive(item.id, next)
    } catch {
      setTypes((current) => current.map((rt) => (rt.id === item.id ? { ...rt, active: item.active } : rt)))
      setError(t('staff.items.toggleError'))
    }
  }

  // Purely client-side, like Team's member removal -- no backend delete for
  // request categories/types exists or is required here, this just hides
  // the row from this list.
  async function onRemoveCategory(category: RequestCategoryAdmin) {
    const ok = await confirm({ title: t('staff.items.categoryRemoveTitle'), description: t('staff.items.categoryRemoveDesc', { name: category.name }), confirmLabel: t('staff.items.categoryRemoveConfirm') })
    if (!ok) return
    setRemovedCategoryIds((current) => new Set(current).add(category.id))
  }

  async function onRemoveItem(item: RequestTypeAdmin) {
    const ok = await confirm({ title: t('staff.items.removeTitle'), description: t('staff.items.removeDesc', { name: item.name }), confirmLabel: t('staff.items.removeConfirm') })
    if (!ok) return
    setRemovedTypeIds((current) => new Set(current).add(item.id))
  }

  const activeCategories = categories.filter((c) => c.active)
  const visibleCategories = categories.filter((c) => !removedCategoryIds.has(c.id))
  const visibleTypes = types.filter((rt) => !removedTypeIds.has(rt.id))

  return (
    <div className="space-y-6">
      {confirmDialog}
      <div>
        <h1 className="text-xl font-semibold text-foreground">{t('staff.items.title')}</h1>
        <p className="text-sm text-muted">{t('staff.items.subtitle')}</p>
      </div>
      {error && <p role="alert" className="text-sm text-bad-ink">{error}</p>}
      <NewCategoryForm onCreated={reload} />
      <div className="overflow-x-auto rounded-lg border border-line bg-white">
        <table aria-label={t('staff.items.title')} className="w-full min-w-max text-sm"><thead className="bg-surface-2 text-left text-xs uppercase text-muted"><tr><th className="px-4 py-2">{t('staff.items.colName')}</th><th className="px-4 py-2">{t('staff.items.colDepartment')}</th><th className="px-4 py-2">{t('staff.items.colStatus')}</th><th className="px-4 py-2" /></tr></thead><tbody className="divide-y divide-line">{visibleCategories.map((category) => <CategoryRow key={category.id} category={category} onToggle={() => onToggleCategory(category)} onRemove={() => onRemoveCategory(category)} onSaved={reload} />)}</tbody></table>
      </div>
      <NewItemForm categories={activeCategories} onCreated={reload} />
      <div className="space-y-6">{visibleCategories.map((category) => { const items = visibleTypes.filter((rt) => rt.category_id === category.id); if (items.length === 0) return null; const headingId = `category-${category.id}`; return <div key={category.id}><h2 id={headingId} className="mb-2 text-sm font-semibold text-muted"><AutoText text={category.name} translations={category.name_i18n} /></h2><div className="overflow-x-auto rounded-lg border border-line bg-white"><table aria-labelledby={headingId} className="w-full min-w-max text-sm"><thead className="bg-surface-2 text-left text-xs uppercase text-muted"><tr><th className="px-4 py-2">{t('staff.items.colName')}</th><th className="px-4 py-2">{t('staff.items.colDescription')}</th><th className="px-4 py-2">{t('staff.items.colQuantity')}</th><th className="px-4 py-2">{t('staff.items.colStatus')}</th><th className="px-4 py-2" /></tr></thead><tbody className="divide-y divide-line">{items.map((item) => <ItemRow key={item.id} item={item} onToggle={() => onToggleItem(item)} onRemove={() => onRemoveItem(item)} onSaved={reload} />)}</tbody></table></div></div> })}</div>
    </div>
  )
}

function CategoryRow({ category, onToggle, onRemove, onSaved }: { category: RequestCategoryAdmin; onToggle: () => void; onRemove: () => void; onSaved: () => Promise<void> }) {
  const { t } = useLocale(); const [open, setOpen] = useState(false)
  return <><tr><td className="px-4 py-2 font-medium text-foreground"><AutoText text={category.name} translations={category.name_i18n} /></td><td className="px-4 py-2 text-muted">{t(`department.${category.department}`)}</td><td className="px-4 py-2"><SwitchControl checked={category.active} onCheckedChange={onToggle} aria-label={category.active ? t('staff.items.deactivate') : t('staff.items.reactivate')} /></td><td className="px-4 py-2 text-right whitespace-nowrap"><div className="flex justify-end gap-2"><IconButton tone="neutral" icon={Languages} label={t('staff.items.translations')} onClick={() => setOpen((v) => !v)} /><IconButton tone="danger" icon={Trash2} label={t('staff.items.remove')} onClick={onRemove} /></div></td></tr>{open && <tr><td colSpan={4} className="bg-surface-2 px-4 py-3"><NameTranslationsForm baseName={category.name} initial={category.name_i18n} onSave={async (name_i18n) => { await updateRequestCategoryTranslations(category.id, name_i18n); await onSaved() }} /></td></tr>}</>
}

function ItemRow({ item, onToggle, onRemove, onSaved }: { item: RequestTypeAdmin; onToggle: () => void; onRemove: () => void; onSaved: () => Promise<void> }) {
  const { t } = useLocale(); const [open, setOpen] = useState(false)
  return <><tr><td className="px-4 py-2 font-medium text-foreground"><AutoText text={item.name} translations={item.name_i18n} /></td><td className="px-4 py-2 text-muted">{item.description ? <AutoText text={item.description} translations={item.description_i18n} /> : '—'}</td><td className="px-4 py-2 tabular-nums text-muted">{item.available_quantity ?? '—'}</td><td className="px-4 py-2"><SwitchControl checked={item.active} onCheckedChange={onToggle} aria-label={item.active ? t('staff.items.deactivate') : t('staff.items.reactivate')} /></td><td className="px-4 py-2 text-right whitespace-nowrap"><div className="flex justify-end gap-2"><IconButton tone="neutral" icon={Languages} label={t('staff.items.translations')} onClick={() => setOpen((v) => !v)} /><IconButton tone="danger" icon={Trash2} label={t('staff.items.remove')} onClick={onRemove} /></div></td></tr>{open && <tr><td colSpan={5} className="bg-surface-2 px-4 py-3"><div className="space-y-4"><NameTranslationsForm label={t('staff.items.name')} baseName={item.name} initial={item.name_i18n} onSave={async (name_i18n) => { await updateRequestTypeTranslations(item.id, { name_i18n, description_i18n: item.description_i18n }); await onSaved() }} />{item.description && <NameTranslationsForm label={t('staff.items.description')} baseName={item.description} initial={item.description_i18n} onSave={async (description_i18n) => { await updateRequestTypeTranslations(item.id, { name_i18n: item.name_i18n, description_i18n }); await onSaved() }} />}</div></td></tr>}</>
}

function NameTranslationsForm({ label, baseName, initial, onSave }: { label?: string; baseName: string; initial: Record<string, string>; onSave: (values: Record<string, string>) => Promise<void> }) {
  const { t } = useLocale(); const [values, setValues] = useState<Record<string, string>>(() => Object.fromEntries(TRANSLATABLE_LOCALES.map((l) => [l.code, initial[l.code] ?? '']))); const [pending, setPending] = useState(false); const [saved, setSaved] = useState(false)
  async function onSubmit(e: React.FormEvent) { e.preventDefault(); setPending(true); setSaved(false); try { const cleaned = Object.fromEntries(Object.entries(values).filter(([, v]) => v.trim() !== '')); await onSave(cleaned); setSaved(true) } finally { setPending(false) } }
  return <form onSubmit={onSubmit}><p className="mb-2 text-xs font-semibold text-muted">{label ? `${t('staff.items.translations')} — ${label}` : t('staff.items.translations')}<span className="ml-1.5 font-normal text-line-strong">({baseName})</span></p><div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{TRANSLATABLE_LOCALES.map((l) => <div key={l.code}><Label htmlFor={`tr-${l.code}-${baseName}`}>{l.label}</Label><Input id={`tr-${l.code}-${baseName}`} value={values[l.code] ?? ''} onChange={(e) => setValues((v) => ({ ...v, [l.code]: e.target.value }))} placeholder={baseName} /></div>)}</div><div className="mt-2 flex items-center gap-2"><Button type="submit" size="sm" disabled={pending}>{pending ? t('staff.items.translationsSaving') : t('staff.items.translationsSave')}</Button>{saved && !pending && <span className="text-xs text-ok-ink">{t('staff.items.translationsSaved')}</span>}</div></form>
}

function NewCategoryForm({ onCreated }: { onCreated: () => Promise<void> }) {
  const { t } = useLocale(); const [name, setName] = useState(''); const [department, setDepartment] = useState<Department>('housekeeping'); const [pending, setPending] = useState(false); const [error, setError] = useState<string | null>(null)
  async function onSubmit(e: React.FormEvent) { e.preventDefault(); setPending(true); setError(null); try { await createRequestCategory({ name: name.trim(), department }); setName(''); await onCreated() } catch { setError(t('staff.items.addCategoryError')) } finally { setPending(false) } }
  return <Card><CardHeader><h2 className="text-sm font-semibold text-foreground">{t('staff.items.addCategoryTitle')}</h2></CardHeader><CardBody><form onSubmit={onSubmit} className="grid grid-cols-1 items-end gap-4 sm:grid-cols-[1fr_1fr_auto]"><FieldGroup className="mb-0"><Label htmlFor="categoryName" required>{t('staff.items.categoryName')}</Label><Input id="categoryName" required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('staff.items.categoryNamePlaceholder')} /></FieldGroup><FieldGroup className="mb-0"><Label htmlFor="categoryDepartment" required>{t('staff.items.categoryDepartment')}</Label><Select id="categoryDepartment" value={department} onChange={(e) => setDepartment(e.target.value as Department)}>{DEPARTMENTS.map((d) => <option key={d} value={d}>{t(`department.${d}`)}</option>)}</Select></FieldGroup><Button type="submit" disabled={pending}>{pending ? t('staff.items.addCategorySubmitPending') : t('staff.items.addCategorySubmit')}</Button></form><FieldError>{error ?? undefined}</FieldError></CardBody></Card>
}

function NewItemForm({ categories, onCreated }: { categories: RequestCategoryAdmin[]; onCreated: () => Promise<void> }) {
  const { t } = useLocale(); const [categoryId, setCategoryId] = useState(''); const [name, setName] = useState(''); const [description, setDescription] = useState(''); const [allowsQuantity, setAllowsQuantity] = useState(false); const [availableQuantity, setAvailableQuantity] = useState(''); const [pending, setPending] = useState(false); const [error, setError] = useState<string | null>(null)
  useEffect(() => { setCategoryId((current) => (current && categories.some((c) => c.id === current) ? current : (categories[0]?.id ?? ''))) }, [categories])
  async function onSubmit(e: React.FormEvent) { e.preventDefault(); setPending(true); setError(null); try { await createRequestType({ categoryId, name: name.trim(), description: description.trim() || null, allowsQuantity, availableQuantity: availableQuantity.trim() ? Number(availableQuantity) : null }); setName(''); setDescription(''); setAllowsQuantity(false); setAvailableQuantity(''); await onCreated() } catch { setError(t('staff.items.addError')) } finally { setPending(false) } }
  return <Card><CardHeader><h2 className="text-sm font-semibold text-foreground">{t('staff.items.addTitle')}</h2></CardHeader><CardBody><form onSubmit={onSubmit} className="space-y-4"><div className="grid grid-cols-1 gap-4 sm:grid-cols-2"><FieldGroup className="mb-0"><Label htmlFor="category" required>{t('staff.items.category')}</Label><Select id="category" required value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>{categories.map((c) => <option key={c.id} value={c.id}><AutoText text={c.name} translations={c.name_i18n} /></option>)}</Select></FieldGroup><FieldGroup className="mb-0"><Label htmlFor="itemName" required>{t('staff.items.name')}</Label><Input id="itemName" required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('staff.items.namePlaceholder')} /></FieldGroup></div><FieldGroup className="mb-0"><Label htmlFor="description">{t('staff.items.description')}</Label><Textarea id="description" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></FieldGroup><div className="grid grid-cols-1 gap-4 sm:grid-cols-2"><FieldGroup className="mb-0"><Label htmlFor="availableQuantity">{t('staff.items.availableQuantity')}</Label><Input id="availableQuantity" type="number" min={0} value={availableQuantity} onChange={(e) => setAvailableQuantity(e.target.value)} placeholder={t('staff.items.availableQuantityPlaceholder')} /></FieldGroup><Switch id="allowsQuantity" checked={allowsQuantity} onCheckedChange={setAllowsQuantity} label={t('staff.items.allowsQuantity')} className="self-end" /></div><FieldError>{error ?? undefined}</FieldError><div className="flex justify-end border-t border-line pt-4"><Button type="submit" disabled={pending || !categoryId}>{pending ? t('staff.items.submitPending') : t('staff.items.submit')}</Button></div></form></CardBody></Card>
}
