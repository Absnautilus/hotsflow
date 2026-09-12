import { useEffect, useState } from 'react'
import { core } from '../core/client'
import { GUEST_APP_URL } from '../core/guestAppUrl'
import { useModuleRuntime } from '../core/ModuleRuntimeContext'

export function GuestLinkRow() {
  const runtime = useModuleRuntime()
  const propertyId = runtime.property?.id ?? null
  const [slug, setSlug] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (!propertyId) return
    let cancelled = false
    core
      .getGuestRequestsSlugForProperty(propertyId)
      .then((value) => {
        if (!cancelled) setSlug(value)
      })
      .catch(() => {
        if (!cancelled) setSlug(null)
      })
    return () => {
      cancelled = true
    }
  }, [propertyId])

  if (!GUEST_APP_URL || !slug) return null

  const link = `${GUEST_APP_URL}/${slug}`

  async function onCopy() {
    await navigator.clipboard.writeText(link)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div className="settings-row settings-row-static guest-link-row">
      <span className="settings-row-main">
        <span>
          <strong>Link accesso ospiti</strong>
          <small>Da comunicare o stampare in QR per ogni camera</small>
        </span>
      </span>
      <div className="guest-link-box">
        <input readOnly value={link} onFocus={(e) => e.currentTarget.select()} />
        <button className="btn btn-secondary" type="button" onClick={onCopy}>
          {copied ? 'Copiato!' : 'Copia'}
        </button>
      </div>
    </div>
  )
}
