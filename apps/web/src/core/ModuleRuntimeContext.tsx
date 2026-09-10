import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { PropsWithChildren } from 'react'
import type { Session } from '@supabase/supabase-js'
import type { Membership, ModuleEntitlement, Profile, Property } from '@hotsflow/core-sdk'
import { core, supabase } from './client'

type RuntimeStatus = 'loading' | 'signed-out' | 'no-property' | 'ready' | 'error'

interface ModuleRuntimeValue {
  status: RuntimeStatus
  error: Error | null
  session: Session | null
  profile: Profile | null
  properties: Property[]
  property: Property | null
  membership: Membership | null
  entitlements: ModuleEntitlement[]
  selectProperty: (propertyId: string) => void
  hasPermission: (permissionSlug: string) => Promise<boolean>
  refresh: () => Promise<void>
}

const ModuleRuntimeContext = createContext<ModuleRuntimeValue | null>(null)
const PROPERTY_STORAGE_KEY = 'hotsflow.activePropertyId'

export function ModuleRuntimeProvider({ children }: PropsWithChildren) {
  const [status, setStatus] = useState<RuntimeStatus>('loading')
  const [error, setError] = useState<Error | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [properties, setProperties] = useState<Property[]>([])
  const [property, setProperty] = useState<Property | null>(null)
  const [membership, setMembership] = useState<Membership | null>(null)
  const [entitlements, setEntitlements] = useState<ModuleEntitlement[]>([])

  const load = useCallback(async () => {
    setStatus('loading')
    setError(null)
    try {
      const { data, error: sessionError } = await supabase.auth.getSession()
      if (sessionError) throw sessionError
      setSession(data.session)

      if (!data.session) {
        setProfile(null)
        setProperties([])
        setProperty(null)
        setMembership(null)
        setEntitlements([])
        setStatus('signed-out')
        return
      }

      const [nextProfile, nextProperties] = await Promise.all([
        core.getCurrentProfile(),
        core.getAccessibleProperties(),
      ])
      setProfile(nextProfile)
      setProperties(nextProperties)

      if (nextProperties.length === 0) {
        setProperty(null)
        setMembership(null)
        setEntitlements([])
        setStatus('no-property')
        return
      }

      const storedId = localStorage.getItem(PROPERTY_STORAGE_KEY)
      const selected = nextProperties.find((item) => item.id === storedId) ?? nextProperties[0]
      localStorage.setItem(PROPERTY_STORAGE_KEY, selected.id)
      setProperty(selected)

      const [nextMembership, nextEntitlements] = await Promise.all([
        core.getMembership(selected.id),
        core.getEnabledModules(selected.id),
      ])
      setMembership(nextMembership)
      setEntitlements(nextEntitlements)
      setStatus('ready')
    } catch (cause) {
      setError(cause instanceof Error ? cause : new Error('Unable to load Hotsflow runtime'))
      setStatus('error')
    }
  }, [])

  useEffect(() => {
    void load()
    const { data } = supabase.auth.onAuthStateChange(() => void load())
    return () => data.subscription.unsubscribe()
  }, [load])

  const selectProperty = useCallback((propertyId: string) => {
    const selected = properties.find((item) => item.id === propertyId)
    if (!selected) return
    localStorage.setItem(PROPERTY_STORAGE_KEY, selected.id)
    setProperty(selected)
    setStatus('loading')
    Promise.all([core.getMembership(selected.id), core.getEnabledModules(selected.id)])
      .then(([nextMembership, nextEntitlements]) => {
        setMembership(nextMembership)
        setEntitlements(nextEntitlements)
        setStatus('ready')
      })
      .catch((cause) => {
        setError(cause instanceof Error ? cause : new Error('Unable to change property'))
        setStatus('error')
      })
  }, [properties])

  const hasPermission = useCallback(async (permissionSlug: string) => {
    if (!property) return false
    return core.hasPermission(property.id, permissionSlug)
  }, [property])

  const value = useMemo<ModuleRuntimeValue>(() => ({
    status,
    error,
    session,
    profile,
    properties,
    property,
    membership,
    entitlements,
    selectProperty,
    hasPermission,
    refresh: load,
  }), [status, error, session, profile, properties, property, membership, entitlements, selectProperty, hasPermission, load])

  return <ModuleRuntimeContext.Provider value={value}>{children}</ModuleRuntimeContext.Provider>
}

export function useModuleRuntime(): ModuleRuntimeValue {
  const value = useContext(ModuleRuntimeContext)
  if (!value) throw new Error('useModuleRuntime must be used inside ModuleRuntimeProvider')
  return value
}
