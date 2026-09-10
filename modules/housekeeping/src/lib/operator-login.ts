// operatore accounts log in with a username + 6-digit PIN chosen by the
// admin, not a real email — Supabase Auth only speaks email+password, so we
// synthesize one from the username. This exact normalization is duplicated
// in supabase/functions/create-staff-account/index.ts; keep both in sync.
const OPERATOR_EMAIL_DOMAIN = 'staff.local'

export function normalizeUsername(username: string): string {
  return username.trim().toLowerCase().replace(/\s+/g, '')
}

export function usernameToEmail(username: string): string {
  return `${normalizeUsername(username)}@${OPERATOR_EMAIL_DOMAIN}`
}

export function isValidPin(pin: string): boolean {
  return /^\d{6}$/.test(pin)
}
