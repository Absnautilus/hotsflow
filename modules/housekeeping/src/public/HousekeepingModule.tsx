import type { SupabaseClient } from '@supabase/supabase-js'
import { LocaleProvider } from '@/lib/i18n/locale-context'
import { UiScaleProvider } from '@/lib/ui-scale-context'
import { configureSupabaseClient } from '@/lib/supabase'
import { StaffApp } from '@/staff/staff-app'
import '../embedded.css'

export interface HousekeepingCapabilities {
  /** Access to stays management inside Housekeeping. */
  staysView: boolean
  /** Access to Housekeeping management/configuration screens. */
  manage: boolean
}

export interface PlatformStaffManagementLink {
  /** Shell-owned destination where platform identities and access are managed. */
  href: string
  /** Shell-owned localized call to action. */
  label: string
  /** Shell-owned localized explanation shown instead of account creation. */
  description: string
}

export interface PlatformHotelSettings {
  /** "HH:mm" 24h default check-in time, or null if the shell has none set. */
  checkInTime: string | null
  /** "HH:mm" 24h default check-out time, or null if the shell has none set. */
  checkOutTime: string | null
}

export interface HousekeepingModuleProps {
  supabase: SupabaseClient
  hotelId: string
  basePath?: string
  /**
   * Core-owned authorization resolved by the Hotsflow shell.
   * Omit in standalone/compatibility integrations to preserve legacy behavior.
   */
  capabilities?: HousekeepingCapabilities
  /**
   * When supplied by an embedding shell, Housekeeping treats its Staff page as
   * a read-only module roster and delegates account lifecycle to this target.
   * Standalone mode deliberately keeps the legacy account-management flow.
   */
  platformStaffManagement?: PlatformStaffManagementLink
  /**
   * Shell-owned hotel-level configuration (edited once in Hotsflow Settings,
   * not duplicated here) -- currently just the default check-in/check-out
   * times used to prefill a new stay's dates. Omit in standalone mode.
   */
  hotelSettings?: PlatformHotelSettings
}

/**
 * Embeddable staff-only Housekeeping entry for the Hotsflow shell.
 *
 * The shell owns authentication, property selection, Core authorization and
 * the Supabase client. Guest routes, standalone login and the standalone
 * BrowserRouter remain in App.tsx and are deliberately not mounted here.
 */
export function HousekeepingModule({
  supabase,
  hotelId,
  basePath = '/housekeeping',
  capabilities,
  platformStaffManagement,
  hotelSettings,
}: HousekeepingModuleProps) {
  // This compatibility boundary must run before StaffApp effects or API calls
  // so integrated mode never creates Housekeeping's standalone Supabase client.
  configureSupabaseClient(supabase)

  return (
    <div className="hk-root hk-root--embedded">
      <LocaleProvider>
        <UiScaleProvider>
          <StaffApp
            mode="embedded"
            expectedHotelId={hotelId}
            basePath={basePath}
            capabilities={capabilities}
            platformStaffManagement={platformStaffManagement}
            hotelSettings={hotelSettings}
          />
        </UiScaleProvider>
      </LocaleProvider>
    </div>
  )
}
