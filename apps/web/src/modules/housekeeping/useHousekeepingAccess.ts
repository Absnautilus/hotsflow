import { useEffect, useState } from 'react'
import { useModuleRuntime } from '../../core/ModuleRuntimeContext'
import { core, supabase } from '../../core/client'
import { resolveHousekeepingAccess } from './resolveHousekeepingAccess'
import type { HousekeepingAccessState as ResolvedState } from './resolveHousekeepingAccess'

// Housekeeping is entitled per-property (guest_requests module flag) but the
// legacy staff app underneath still gates access per staff_profiles row at a
// specific legacy hotel_id (see StaffApp's expectedHotelId check in the
// embedded module). A property can be entitled without being bridged to a
// legacy hotel at all (no-mapping — e.g. a brand-new property), and a user
// can be entitled and mapped without having an operational profile at that
// specific hotel (no-profile — e.g. a master whose own account lives at a
// different hotel). Both are dead ends once inside the module, so the shell
// resolves the same three-step check up front to decide whether Housekeeping
// should even be offered in nav/Home, and to explain deep-link access
// clearly rather than showing an ambiguous blank screen. The actual
// entitled/mapped/profile-exists -> status decision lives in
// resolveHousekeepingAccess.ts as a pure, independently tested function;
// this hook only resolves the async inputs it needs.
export type HousekeepingAccessState = { status: 'loading' } | { status: 'error'; message: string } | ResolvedState

function errorMessage(cause: unknown): string {
  if (cause && typeof cause === 'object') {
    const candidate = cause as { code?: unknown; message?: unknown; details?: unknown; hint?: unknown }
    return [candidate.code, candidate.message, candidate.details, candidate.hint]
      .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
      .join(' · ')
  }
  return cause instanceof Error ? cause.message : String(cause)
}

export function useHousekeepingAccess(): HousekeepingAccessState {
  const runtime = useModuleRuntime()
  const [state, setState] = useState<HousekeepingAccessState>({ status: 'loading' })

  const entitled = runtime.entitlements.some((item) => item.enabled && item.slug === 'guest_requests')
  const propertyId = runtime.property?.id ?? null
  const userId = runtime.session?.user.id ?? null

  useEffect(() => {
    let cancelled = false

    if (!entitled) {
      setState(resolveHousekeepingAccess({ entitled: false, legacyHotelId: null, hasCompatibleProfile: false }))
      return () => {
        cancelled = true
      }
    }
    if (!propertyId || !userId) {
      setState({ status: 'loading' })
      return () => {
        cancelled = true
      }
    }

    setState({ status: 'loading' })

    void core
      .getGuestRequestsLegacyHotelId(propertyId)
      .then(async (hotelId) => {
        if (cancelled) return
        if (!hotelId) {
          setState(resolveHousekeepingAccess({ entitled: true, legacyHotelId: null, hasCompatibleProfile: false }))
          return
        }
        const { data, error } = await supabase
          .from('staff_profiles')
          .select('id')
          .eq('auth_user_id', userId)
          .eq('hotel_id', hotelId)
          .eq('active', true)
          .maybeSingle()
        if (cancelled) return
        if (error) {
          setState({ status: 'error', message: errorMessage(error) })
          return
        }
        setState(resolveHousekeepingAccess({ entitled: true, legacyHotelId: hotelId, hasCompatibleProfile: Boolean(data) }))
      })
      .catch((cause: unknown) => {
        if (!cancelled) setState({ status: 'error', message: errorMessage(cause) })
      })

    return () => {
      cancelled = true
    }
  }, [propertyId, entitled, userId])

  return state
}
