import { useEffect, useState } from 'react'
import { FlagIcon } from './FlagIcon'

type Lang = 'it' | 'en'

const LABELS: Record<Lang, string> = { it: 'Italiano', en: 'English' }
const LANGS: Lang[] = ['it', 'en']

function readStoredLanguage(): Lang {
  return localStorage.getItem('homisuite.language') === 'en' ? 'en' : 'it'
}

// Inline flag toggle rather than a flag-trigger + flyout: every place this
// renders (Settings' .settings-list, the account menu's .account-popover)
// clips overflow to keep its own rounded corners, which silently cropped a
// nested popover's second option out of view. Two languages fit inline
// without needing a flyout at all.
export function LanguageToggle() {
  const [language, setLanguageState] = useState<Lang>(readStoredLanguage)

  useEffect(() => {
    function syncLanguage(event: Event) {
      const next = (event as CustomEvent<string>).detail
      if (next === 'it' || next === 'en') setLanguageState(next)
    }
    window.addEventListener('homisuite:language-change', syncLanguage)
    return () => window.removeEventListener('homisuite:language-change', syncLanguage)
  }, [])

  function select(next: Lang) {
    localStorage.setItem('homisuite.language', next)
    setLanguageState(next)
    window.dispatchEvent(new CustomEvent('homisuite:language-change', { detail: next }))
  }

  return (
    <div className="lang-toggle" role="radiogroup" aria-label="Lingua">
      {LANGS.map((code) => (
        <button
          key={code}
          type="button"
          role="radio"
          aria-checked={code === language}
          aria-label={LABELS[code]}
          title={LABELS[code]}
          className={`lang-toggle-option${code === language ? ' current' : ''}`}
          onClick={() => select(code)}
        >
          <FlagIcon code={code} />
        </button>
      ))}
    </div>
  )
}
