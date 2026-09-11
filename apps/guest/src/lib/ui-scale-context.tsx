import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'

// Three steps, not a free slider: an accessibility control people set once
// and forget, not something to fiddle with. Values scale the root font
// size, and since every Tailwind spacing/text utility here is rem-based,
// that scales padding and tap targets right along with the text — a
// bigger font alone wouldn't help someone who also needs bigger buttons.
export const UI_SCALES = ['small', 'normal', 'large'] as const
export type UiScale = (typeof UI_SCALES)[number]

const SCALE_FACTOR: Record<UiScale, number> = {
  small: 0.9,
  normal: 1,
  large: 1.3,
}

const STORAGE_KEY = 'roomcall_ui_scale'
const DEFAULT_SCALE: UiScale = 'normal'

function isUiScale(value: string): value is UiScale {
  return (UI_SCALES as readonly string[]).includes(value)
}

function readStoredScale(): UiScale {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored && isUiScale(stored)) return stored
  } catch {
    // ignore — default scale is a fine fallback
  }
  return DEFAULT_SCALE
}

interface UiScaleContextValue {
  scale: UiScale
  setScale: (scale: UiScale) => void
}

const UiScaleContext = createContext<UiScaleContextValue | null>(null)

export function UiScaleProvider({ children }: { children: ReactNode }) {
  const [scale, setScaleState] = useState<UiScale>(() => readStoredScale())

  useEffect(() => {
    document.documentElement.style.fontSize = `${16 * SCALE_FACTOR[scale]}px`
  }, [scale])

  function setScale(next: UiScale) {
    setScaleState(next)
    try {
      localStorage.setItem(STORAGE_KEY, next)
    } catch {
      // per-viewer convenience only — fine if it doesn't persist
    }
  }

  const value = useMemo<UiScaleContextValue>(() => ({ scale, setScale }), [scale])

  return <UiScaleContext.Provider value={value}>{children}</UiScaleContext.Provider>
}

export function useUiScale(): UiScaleContextValue {
  const ctx = useContext(UiScaleContext)
  if (!ctx) throw new Error('useUiScale must be used within a UiScaleProvider')
  return ctx
}
