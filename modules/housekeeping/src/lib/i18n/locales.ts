export type Locale = 'it' | 'en' | 'fr' | 'de' | 'es' | 'pt' | 'ja' | 'bn' | 'hi' | 'ar' | 'zh' | 'ru'

export const DEFAULT_LOCALE: Locale = 'it'

export const LOCALES: { code: Locale; label: string }[] = [
  { code: 'it', label: 'Italiano' },
  { code: 'en', label: 'English' },
  { code: 'fr', label: 'Français' },
  { code: 'de', label: 'Deutsch' },
  { code: 'es', label: 'Español' },
  { code: 'pt', label: 'Português' },
  { code: 'ja', label: '日本語' },
  { code: 'bn', label: 'বাংলা' },
  { code: 'hi', label: 'हिन्दी' },
  { code: 'ar', label: 'العربية' },
  { code: 'zh', label: '中文' },
  { code: 'ru', label: 'Русский' },
]

export function isLocale(value: string): value is Locale {
  return LOCALES.some((l) => l.code === value)
}
