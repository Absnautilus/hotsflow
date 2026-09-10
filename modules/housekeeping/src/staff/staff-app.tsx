import { useEffect, useState } from 'react'
import { Route, Routes, useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { cancelRequest, claimRequest, fetchMyProfile } from '@/lib/staff-api'
import { unlockAudio } from '@/lib/beep'
import { useLocale } from '@/lib/i18n/locale-context'
import type { StaffProfile } from '@/lib/staff-types'
import type { HousekeepingCapabilities, PlatformHotelSettings, PlatformStaffManagementLink } from '@/public/HousekeepingModule'
import { StaffLogin } from '@/staff/staff-login'
import { DashboardHeader } from '@/staff/dashboard-header'
import { RequestQueue } from '@/staff/request-queue'
import { AdminHome } from '@/staff/admin/admin-home'
import { StaysPage } from '@/staff/stays/stays-page'

interface StaffAppProps {
  mode?: 'standalone' | 'embedded'
  expectedHotelId?: string
  basePath?: string
  capabilities?: HousekeepingCapabilities
  platformStaffManagement?: PlatformStaffManagementLink
  hotelSettings?: PlatformHotelSettings
}

export function StaffApp({ mode = 'standalone', expectedHotelId, basePath = '/housekeeping', capabilities, platformStaffManagement, hotelSettings }: StaffAppProps = {}) {
  const { t } = useLocale()
  const embedded = mode === 'embedded'
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState<StaffProfile | null>(null)
  const [searchParams, setSearchParams] = useSearchParams()

  useEffect(() => {
    let cancelled = false

    async function loadProfile() {
      try {
        const p = await fetchMyProfile()
        if (!cancelled) setProfile(p)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    if (embedded) {
      void loadProfile()
      return () => {
        cancelled = true
      }
    }

    async function loadStandalone() {
      const { data } = await supabase.auth.getSession()
      if (!data.session) {
        if (!cancelled) {
          setProfile(null)
          setLoading(false)
        }
        return
      }
      await loadProfile()
    }

    void loadStandalone()
    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      setLoading(true)
      void loadStandalone()
    })
    return () => {
      cancelled = true
      sub.subscription.unsubscribe()
    }
  }, [embedded])

  useEffect(() => {
    function onFirstPointer() {
      unlockAudio()
      document.removeEventListener('pointerdown', onFirstPointer)
    }
    document.addEventListener('pointerdown', onFirstPointer)
    return () => document.removeEventListener('pointerdown', onFirstPointer)
  }, [])

  useEffect(() => {
    const claimId = searchParams.get('claim')
    if (!claimId || !profile) return
    claimRequest(claimId, profile.id).finally(() => {
      const next = new URLSearchParams(searchParams)
      next.delete('claim')
      setSearchParams(next, { replace: true })
    })
  }, [searchParams, profile, setSearchParams])

  useEffect(() => {
    const rejectId = searchParams.get('reject')
    if (!rejectId || !profile) return
    cancelRequest(rejectId).finally(() => {
      const next = new URLSearchParams(searchParams)
      next.delete('reject')
      setSearchParams(next, { replace: true })
    })
  }, [searchParams, profile, setSearchParams])

  if (loading) {
    return (
      <div role="status" className="flex min-h-[16rem] items-center justify-center bg-background">
        <div aria-hidden="true" className="h-7 w-7 animate-spin rounded-full border-3 border-line-strong border-t-accent" />
        <span className="sr-only">{t('staff.availability.loading')}</span>
      </div>
    )
  }
  if (!profile) {
    if (embedded) {
      return <div className="rounded-lg border border-line bg-surface p-10 text-center text-sm text-muted">{t('staff.routeUnavailable')}</div>
    }
    return <StaffLogin />
  }
  if (!profile.active) {
    return <div className="flex min-h-[16rem] items-center justify-center bg-surface-2 px-4 text-center text-sm text-muted">{t('staff.accountDisabled')}</div>
  }
  if (expectedHotelId && profile.hotel_id !== expectedHotelId) {
    return <div className="rounded-lg border border-line bg-surface p-10 text-center text-sm text-muted">{t('staff.routeUnavailable')}</div>
  }

  // Standalone keeps the legacy role/department contract. Embedded Hotsflow
  // uses capabilities resolved by Core; the fallback is intentionally kept
  // during migration so existing integrators are not broken.
  const legacyAdminLike = profile.role === 'admin' || profile.role === 'master'
  const legacyStaysAllowed = legacyAdminLike || profile.department === 'reception'
  const manageAllowed = embedded && capabilities ? capabilities.manage : legacyAdminLike
  const staysAllowed = embedded && capabilities ? capabilities.staysView : legacyStaysAllowed

  const queueRoute = <Route index element={<RequestQueue profile={profile} />} />
  const staysRoute = staysAllowed ? <Route path="soggiorni" element={<StaysPage hotelId={profile.hotel_id} hotelSettings={hotelSettings} />} /> : null
  const adminRoute = manageAllowed ? (
    <Route
      path="admin/*"
      element={(
        <AdminHome
          profile={profile}
          basePath={`${basePath}/admin`}
          embedded
          platformStaffManagement={platformStaffManagement}
          hotelId={expectedHotelId}
        />
      )}
    />
  ) : null

  const routeContent = embedded ? (
    <Routes>
      {queueRoute}
      {staysRoute}
      {adminRoute}
      <Route path="*" element={<div className="rounded-lg border border-line bg-surface p-10 text-center text-sm text-muted">{t('staff.routeUnavailable')}</div>} />
    </Routes>
  ) : (
    <Routes>
      <Route path="/" element={<RequestQueue profile={profile} />} />
      {staysAllowed && <Route path="/soggiorni" element={<StaysPage hotelId={profile.hotel_id} />} />}
      {manageAllowed && <Route path="/admin/*" element={<AdminHome profile={profile} />} />}
      <Route path="*" element={<div className="rounded-lg border border-line bg-surface p-10 text-center text-sm text-muted">{t('staff.routeUnavailable')}</div>} />
    </Routes>
  )

  return (
    <div className={embedded ? undefined : 'min-h-full bg-surface-2'}>
      <DashboardHeader
        profile={profile}
        embedded={embedded}
        basePath={embedded ? basePath : '/staff'}
        capabilities={embedded ? { staysView: staysAllowed, manage: manageAllowed } : undefined}
      />
      {embedded ? (
        <div className="pt-4">{routeContent}</div>
      ) : (
        <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6">{routeContent}</main>
      )}
    </div>
  )
}
