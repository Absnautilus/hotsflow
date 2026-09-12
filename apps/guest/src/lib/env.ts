function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`Missing ${name} — copy .env.example to .env and fill it in.`)
  }
  return value
}

export const SUPABASE_URL = required('VITE_SUPABASE_URL', import.meta.env.VITE_SUPABASE_URL)
export const SUPABASE_ANON_KEY = required('VITE_SUPABASE_ANON_KEY', import.meta.env.VITE_SUPABASE_ANON_KEY)

// This is one deployment shared by every hotel on one domain -- there is no
// per-deployment hotel configuration. Each hotel's own link is
// https://<this-domain>/<guest_slug>, e.g. /palazzo-veneziano (see
// supabase/migrations/20260912110000_hotels_guest_slug.sql). The slug isn't
// the hotel id itself -- resolveHotelFromSlug (guest-api.ts) looks it up
// against the database and caches the result here.
const HOTEL_ID_KEY = 'guest_hotel_id'
let cachedHotelId: string | null = null

export function getHotelId(): string {
  if (!cachedHotelId) {
    throw new Error('missing_hotel_id')
  }
  return cachedHotelId
}

// Called only by resolveHotelFromSlug once a slug has actually resolved to
// a real hotel id -- never with unverified user input.
export function setResolvedHotelId(hotelId: string): void {
  cachedHotelId = hotelId
  try {
    localStorage.setItem(HOTEL_ID_KEY, hotelId)
  } catch {
    // localStorage unavailable (private mode, etc.) -- the id still works
    // for this visit, it just won't survive a reload without the URL slug.
  }
}

export function getStoredHotelId(): string | null {
  try {
    return localStorage.getItem(HOTEL_ID_KEY)
  } catch {
    return null
  }
}

// The URL's first path segment, e.g. "palazzo-veneziano" from
// "/palazzo-veneziano". Null for a bare-origin visit (no slug at all).
export function getHotelSlugFromPath(): string | null {
  return window.location.pathname.split('/').filter(Boolean)[0] ?? null
}

// Optional: push notifications are simply unavailable (the on-duty toggle
// hides itself) when this isn't set, rather than throwing like the required
// Supabase vars above — lets the app run without it during local setup.
export const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY ?? null
