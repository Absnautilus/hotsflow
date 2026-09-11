import { useEffect, useState } from 'react'
import { PublicHeader } from '@/components/public-header'
import { cn } from '@/lib/cn'
import { clearGuestToken, getGuestToken, setGuestToken } from '@/lib/guest-token'
import { getStayInfo, isInvalidSessionError, listMyRequests, type StayInfo } from '@/lib/guest-api'
import { useLocale } from '@/lib/i18n/locale-context'
import { LoginScreen } from '@/guest/login-screen'
import { RequestFlow } from '@/guest/request-flow'
import { StatusList } from '@/guest/status-list'
import { Greeting } from '@/guest/greeting'

type Tab = 'new' | 'status'

export function GuestApp() {
  const { t } = useLocale()
  const [token, setToken] = useState<string | null>(() => getGuestToken())
  // a token surviving in localStorage doesn't mean the stay is still valid
  // (checked out, cancelled, expired) — confirm before showing anything,
  // rather than waiting for the first write to fail
  const [checked, setChecked] = useState(false)
  const [stay, setStay] = useState<StayInfo | null>(null)
  const [tab, setTab] = useState<Tab>('new')
  const [refreshKey, setRefreshKey] = useState(0)

  function onSessionExpired() {
    clearGuestToken()
    setToken(null)
    setStay(null)
    setChecked(true)
  }

  function onLogout() {
    clearGuestToken()
    setToken(null)
    setStay(null)
    setTab('new')
  }

  useEffect(() => {
    if (!token) {
      setChecked(true)
      return
    }
    let cancelled = false
    listMyRequests(token)
      .then(() => {
        if (cancelled) return
        setChecked(true)
        getStayInfo(token).then((info) => {
          if (!cancelled) setStay(info)
        })
      })
      .catch((err) => {
        if (cancelled) return
        if (isInvalidSessionError(err)) {
          onSessionExpired()
        } else {
          // a transient/network error shouldn't log the guest out — let them in,
          // individual actions will surface their own errors if it's really down
          setChecked(true)
        }
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token])

  if (!checked) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="h-7 w-7 animate-spin rounded-full border-3 border-line-strong border-t-accent" />
      </div>
    )
  }

  if (!token) {
    return (
      <LoginScreen
        onSuccess={(newToken) => {
          setGuestToken(newToken)
          setToken(newToken)
          setChecked(true)
        }}
      />
    )
  }

  return (
    <div className="min-h-screen bg-surface-2 pb-10">
      <PublicHeader onLogout={onLogout} />
      <div className="mx-auto max-w-xl px-4 pt-4">
        {stay && <Greeting stay={stay} />}

        <div className="mb-5 flex gap-1 rounded-md bg-surface-2 p-1">
          <TabButton active={tab === 'new'} onClick={() => setTab('new')}>
            {t('tabs.new')}
          </TabButton>
          <TabButton active={tab === 'status'} onClick={() => setTab('status')}>
            {t('tabs.status')}
          </TabButton>
        </div>

        {tab === 'new' ? (
          <RequestFlow
            token={token}
            onSessionExpired={onSessionExpired}
            onCreated={() => {
              setRefreshKey((k) => k + 1)
              setTab('status')
            }}
          />
        ) : (
          <StatusList token={token} refreshKey={refreshKey} onSessionExpired={onSessionExpired} />
        )}
      </div>
    </div>
  )
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'flex-1 cursor-pointer rounded px-3 py-1.5 text-sm font-medium transition-colors',
        active ? 'bg-white text-foreground shadow-sm' : 'text-muted hover:text-foreground',
      )}
    >
      {children}
    </button>
  )
}
