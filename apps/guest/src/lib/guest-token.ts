const KEY = 'guest_token'

export function getGuestToken(): string | null {
  try {
    return localStorage.getItem(KEY)
  } catch {
    return null
  }
}

export function setGuestToken(token: string) {
  try {
    localStorage.setItem(KEY, token)
  } catch {
    // localStorage unavailable (private mode, etc.) — session just won't
    // survive a reload; the login screen is the safe fallback.
  }
}

export function clearGuestToken() {
  try {
    localStorage.removeItem(KEY)
  } catch {
    // see getGuestToken
  }
}
