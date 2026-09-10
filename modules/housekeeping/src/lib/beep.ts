// A short synthesized chime — no audio asset to ship, and it survives the
// dashboard being open for days without a network request.
//
// One AudioContext, reused for the life of the tab, instead of a fresh one
// per alert: Safari/iOS creates a context in a "suspended" state unless
// it's resumed from inside a real user-gesture call stack, and a new
// request arrives via a realtime callback, not a tap — so a context made
// at alert time would just sit suspended and never make a sound. unlockAudio()
// resumes this same context from the app's first tap, so by the time a
// real alert needs to play, it's already running.
let sharedCtx: AudioContext | null = null

function getAudioContext(): AudioContext | null {
  const AudioContextCtor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  if (!AudioContextCtor) return null
  if (!sharedCtx) sharedCtx = new AudioContextCtor()
  return sharedCtx
}

export function unlockAudio() {
  const ctx = getAudioContext()
  if (ctx && ctx.state === 'suspended') ctx.resume().catch(() => {})
}

// Per-device preference (not per-hotel), so plain localStorage rather than
// a synced setting — whoever's phone/tablet this is controls its own
// volume, same as any other app's notification sound.
const VOLUME_KEY = 'roomcall.alertVolume'
const DEFAULT_VOLUME = 0.6

export function getAlertVolume(): number {
  try {
    const raw = localStorage.getItem(VOLUME_KEY)
    if (raw === null) return DEFAULT_VOLUME
    const n = Number(raw)
    return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : DEFAULT_VOLUME
  } catch {
    return DEFAULT_VOLUME
  }
}

export function setAlertVolume(volume: number) {
  const clamped = Math.min(1, Math.max(0, volume))
  try {
    localStorage.setItem(VOLUME_KEY, String(clamped))
  } catch {
    // localStorage unavailable (private browsing, quota) — volume just
    // won't persist across reloads, not worth failing the call over
  }
}

export function playAlertSound() {
  try {
    const volume = getAlertVolume()
    if (volume <= 0) return
    const ctx = getAudioContext()
    if (!ctx) return
    if (ctx.state === 'suspended') ctx.resume().catch(() => {})
    const now = ctx.currentTime
    const peak = 0.2 * volume
    ;[880, 1320].forEach((freq, i) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.type = 'sine'
      osc.frequency.value = freq
      gain.gain.setValueAtTime(0.0001, now + i * 0.16)
      gain.gain.exponentialRampToValueAtTime(peak, now + i * 0.16 + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, now + i * 0.16 + 0.22)
      osc.connect(gain).connect(ctx.destination)
      osc.start(now + i * 0.16)
      osc.stop(now + i * 0.16 + 0.24)
    })
  } catch {
    // audio isn't essential — the on-screen toast still carries the alert
  }
}
