// Web Push service worker: shows the notification and handles the
// "Accetta richiesta" / "Rifiuta richiesta" actions, or a tap on the
// notification body, by opening (or focusing) the Housekeeping module with
// ?claim=<id> or ?reject=<id>, which staff-app.tsx reads to auto-claim or
// auto-reject the request. /housekeeping, not /staff -- the embedded module
// mounts at that path in this shell (HousekeepingModuleGate's basePath),
// unlike the original standalone Housekeeping app's own /staff route.
self.addEventListener('push', (event) => {
  let data = { title: 'RoomCall', body: 'Nuova richiesta', data: {} }
  try {
    if (event.data) data = { ...data, ...event.data.json() }
  } catch {
    // ignore malformed payloads, fall back to the defaults above
  }

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/favicon.svg',
      badge: '/favicon.svg',
      data: data.data,
      actions: [
        { action: 'accept', title: 'Accetta richiesta' },
        { action: 'reject', title: 'Rifiuta richiesta' },
      ],
      requireInteraction: true,
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const requestId = event.notification.data?.requestId
  const url =
    event.action === 'reject' && requestId
      ? `/housekeeping?reject=${requestId}`
      : event.action === 'accept' && requestId
        ? `/housekeeping?claim=${requestId}`
        : (event.notification.data?.url ?? '/housekeeping')

  event.waitUntil(
    (async () => {
      const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      for (const client of clientsList) {
        if ('focus' in client) {
          await client.focus()
          if ('navigate' in client) await client.navigate(url)
          return
        }
      }
      await self.clients.openWindow(url)
    })(),
  )
})
