// Best-effort machine translation for admin-entered content (category/item
// names, descriptions, hotel name) that can't go through the hand-written
// dictionary. Uses Google Translate's unauthenticated `gtx` endpoint — free
// and keyless, but unofficial: it can rate-limit or change shape without
// notice. On any failure this falls back to the original text, so a broken
// endpoint degrades the UI, it never breaks it.
//
// Source language is auto-detected (sl=auto) rather than assumed Italian:
// admin-entered names are often typed in whatever language the person
// typing prefers (English category names on an otherwise-Italian menu are
// common), so a fixed sl=it silently skipped translating those into the
// viewer's actual locale, Italian included.
const cache = new Map<string, string>()

export async function autoTranslate(text: string, targetLang: string): Promise<string> {
  const trimmed = text.trim()
  if (!trimmed) return text

  const cacheKey = `${targetLang}:${trimmed}`
  const cached = cache.get(cacheKey)
  if (cached) return cached

  try {
    const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${targetLang}&dt=t&q=${encodeURIComponent(trimmed)}`
    const res = await fetch(url)
    if (!res.ok) return text

    const data = (await res.json()) as unknown
    const segments = Array.isArray(data) ? (data[0] as unknown) : null
    if (!Array.isArray(segments)) return text

    const translated = segments.map((segment) => (Array.isArray(segment) ? String(segment[0] ?? '') : '')).join('')
    if (!translated) return text

    cache.set(cacheKey, translated)
    return translated
  } catch {
    return text
  }
}
