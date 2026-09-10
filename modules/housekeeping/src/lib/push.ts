import { VAPID_PUBLIC_KEY } from '@/lib/env'
import { savePushSubscription, setOnDuty } from '@/lib/staff-api'

export const PUSH_SUPPORTED =
  typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && VAPID_PUBLIC_KEY !== null

function urlBase64ToUint8Array(base64url: string): Uint8Array {
  const padding = '='.repeat((4 - (base64url.length % 4)) % 4)
  const base64 = (base64url + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(base64)
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
}

// Requests notification permission, registers the service worker, subscribes
// to Web Push (or reuses an existing subscription), saves it, then flips
// on_duty on. Throws 'permission_denied' if the user declines the browser
// prompt — callers should surface that as an explanation, not a generic error.
export async function goOnDuty(staffId: string): Promise<void> {
  if (!PUSH_SUPPORTED) {
    await setOnDuty(true)
    return
  }

  const permission = await Notification.requestPermission()
  if (permission !== 'granted') throw new Error('permission_denied')

  const registration = await navigator.serviceWorker.register('/sw.js')
  await navigator.serviceWorker.ready

  let subscription = await registration.pushManager.getSubscription()
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY as string) as BufferSource,
    })
  }

  const json = subscription.toJSON()
  if (!json.endpoint || !json.keys?.p256dh || !json.keys?.auth) throw new Error('invalid_subscription')
  await savePushSubscription(staffId, { endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth })

  await setOnDuty(true)
}

// Only flips on_duty off — that alone is what stops notify-new-request from
// sending anything (it filters on on_duty=true), so there's no need to tear
// down the browser subscription too. Leaving it in place means going back
// on duty later doesn't need a fresh permission prompt.
export async function goOffDuty(): Promise<void> {
  await setOnDuty(false)
}
