import { useEffect, useState } from 'react'
import { useLocale } from '@/lib/i18n/locale-context'
import { autoTranslate } from '@/lib/i18n/auto-translate'

type Translations = Record<string, string> | null | undefined

// Renders admin-entered text (category/item names, descriptions…).
//
// When `translations` is passed (categories/items now carry a manual
// name_i18n/description_i18n map — see 0017_manual_translations.sql), this
// looks up the viewer's locale there and falls back to the original text if
// that locale hasn't been filled in. No machine translation involved: it
// was unreliable on mixed-language admin input (e.g. "Comfort camera"
// mistranslating to "Fotocamera confortevole").
//
// When `translations` is omitted, falls back to the old Google-Translate
// behavior for any other admin text that hasn't been migrated to manual
// translations.
export function AutoText({ text, translations, className }: { text: string; translations?: Translations; className?: string }) {
  const { locale } = useLocale()
  const [display, setDisplay] = useState(text)
  const manual = translations !== undefined

  useEffect(() => {
    if (manual) {
      setDisplay((translations && translations[locale]) || text)
      return
    }
    setDisplay(text)
    let cancelled = false
    autoTranslate(text, locale).then((translated) => {
      if (!cancelled) setDisplay(translated)
    })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text, locale, manual, translations])

  return <span className={className}>{display}</span>
}
