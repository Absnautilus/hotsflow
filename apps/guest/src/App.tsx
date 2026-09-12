import { GuestApp } from '@/guest/guest-app'
import { LocaleProvider } from '@/lib/i18n/locale-context'
import { UiScaleProvider } from '@/lib/ui-scale-context'

// The original Housekeeping repo mounted this under /g/* alongside a
// sibling /staff/* app in the same deployment; apps/guest is now its own
// single-purpose deployment, one shared domain for every hotel (the hotel
// id travels in the URL, see src/lib/env.ts), so it owns the whole origin
// directly instead of a path prefix.
export function App() {
  return (
    <LocaleProvider>
      <UiScaleProvider>
        <GuestApp />
      </UiScaleProvider>
    </LocaleProvider>
  )
}
