// One shared domain for every hotel's guest app -- unset in an environment
// where that deployment doesn't exist yet, in which case Settings' guest
// link row simply hides itself rather than showing a broken link.
const raw = import.meta.env.VITE_GUEST_APP_URL as string | undefined
export const GUEST_APP_URL = raw ? raw.replace(/\/+$/, '') : null
