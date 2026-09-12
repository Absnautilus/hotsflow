import { useEffect, useState } from 'react'
import { Switch } from './Switch'
import { core } from '../core/client'
import { DEVICE_PUSH_SUPPORTED, getExistingPushSubscription, subscribeDevicePush, toSubscriptionKeys } from '../core/devicePush'

export function NotificationsToggle() {
  const [subscribed, setSubscribed] = useState<boolean | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!DEVICE_PUSH_SUPPORTED) {
      setSubscribed(false)
      return
    }
    let cancelled = false
    getExistingPushSubscription()
      .then((subscription) => (subscription ? core.isDevicePushSubscribed(subscription.endpoint) : false))
      .then((value) => {
        if (!cancelled) setSubscribed(value)
      })
      .catch(() => {
        if (!cancelled) setSubscribed(false)
      })
    return () => {
      cancelled = true
    }
  }, [])

  async function turnOff() {
    // Only the device_push_subscriptions row is removed -- the browser
    // subscription itself is left alone. It may be shared with
    // Housekeeping's own on-duty push flow, which never tears it down
    // either (see modules/housekeeping/src/lib/push.ts); unsubscribing at
    // the browser level here would silently break that unrelated feature.
    const previous = subscribed
    setSubscribed(false)
    try {
      const subscription = await getExistingPushSubscription()
      if (subscription) await core.deleteDevicePushSubscription(subscription.endpoint)
    } catch {
      setSubscribed(previous)
      setError('Non è stato possibile disattivare le notifiche.')
    }
  }

  async function turnOn() {
    setError(null)
    try {
      const subscription = await subscribeDevicePush()
      await core.saveDevicePushSubscription(toSubscriptionKeys(subscription))
      setSubscribed(true)
    } catch (cause) {
      setSubscribed(false)
      setError(
        cause instanceof Error && cause.message === 'permission_denied'
          ? 'Notifiche bloccate dal browser per questo sito.'
          : 'Non è stato possibile attivare le notifiche.',
      )
    }
  }

  if (!DEVICE_PUSH_SUPPORTED) {
    return <span className="settings-row-status">Non disponibile su questo dispositivo</span>
  }

  return (
    <span className="settings-row-control-inline">
      <Switch
        checked={Boolean(subscribed)}
        onChange={() => void (subscribed ? turnOff() : turnOn())}
        disabled={subscribed === null}
        aria-label="Notifiche push su questo dispositivo"
      />
      {error && <small className="form-error" role="alert">{error}</small>}
    </span>
  )
}
