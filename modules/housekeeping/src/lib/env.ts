function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(`Missing ${name} — copy .env.example to .env and fill it in.`)
  }
  return value
}

export const SUPABASE_URL = required('VITE_SUPABASE_URL', import.meta.env.VITE_SUPABASE_URL)
export const SUPABASE_ANON_KEY = required('VITE_SUPABASE_ANON_KEY', import.meta.env.VITE_SUPABASE_ANON_KEY)

// Standalone guest mode still uses a single-hotel deployment, but integrated
// staff mode receives its property/hotel scope from Hotsflow at runtime.
// Keep this lookup lazy so importing the staff module does not require
// VITE_HOTEL_ID at build/module-evaluation time.
export function getHotelId(): string {
  return required('VITE_HOTEL_ID', import.meta.env.VITE_HOTEL_ID)
}

// Optional: push notifications are simply unavailable (the on-duty toggle
// hides itself) when this isn't set, rather than throwing like the required
// Supabase vars above — lets the app run without it during local setup.
export const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY ?? null
