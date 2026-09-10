import { useEffect, useRef } from 'react'
import { playAlertSound } from '@/lib/beep'
import type { QueuedRequest } from '@/lib/staff-types'

const CHECK_INTERVAL_MS = 20_000
const UNCLAIMED_THRESHOLD_MS = 3 * 60_000
const IN_PROGRESS_THRESHOLD_MS = 10 * 60_000

function typeLabel(request: QueuedRequest): string {
  return request.request_types?.name ?? 'Richiesta'
}

// Escalation runs entirely in the browser tab, on the same "dashboard stays
// open" assumption as the rest of the MVP notification story: it re-checks
// on an interval rather than relying on a server-side scheduler, so there is
// no cron/edge-function job to deploy for this to work.
export function useRequestAlerts(queue: QueuedRequest[], onAlert: (message: string, tone: 'info' | 'warning') => void) {
  const firedRef = useRef(new Set<string>())

  useEffect(() => {
    function check() {
      const now = Date.now()
      for (const request of queue) {
        if (request.status === 'requested') {
          const waited = now - new Date(request.created_at).getTime()
          const key = `${request.id}:unclaimed`
          if (waited >= UNCLAIMED_THRESHOLD_MS && !firedRef.current.has(key)) {
            firedRef.current.add(key)
            onAlert(`Camera ${request.room_number}: "${typeLabel(request)}" in attesa da più di 3 minuti`, 'warning')
            playAlertSound()
          }
        } else if (request.status === 'in_progress' && request.accepted_at) {
          const inProgressFor = now - new Date(request.accepted_at).getTime()
          const key = `${request.id}:stalled`
          if (inProgressFor >= IN_PROGRESS_THRESHOLD_MS && !firedRef.current.has(key)) {
            firedRef.current.add(key)
            onAlert(`Camera ${request.room_number}: "${typeLabel(request)}" presa in carico da più di 10 minuti, non ancora completata`, 'warning')
            playAlertSound()
          }
        }
      }
    }

    check()
    const interval = setInterval(check, CHECK_INTERVAL_MS)
    return () => clearInterval(interval)
  }, [queue, onAlert])
}
