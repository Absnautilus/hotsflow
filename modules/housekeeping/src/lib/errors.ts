// Supabase (PostgREST/RPC/Edge Function) failures are thrown as plain
// objects with a `message` string, not real Error instances — `err
// instanceof Error` misses them, and String(err) on a plain object just
// gives "[object Object]" instead of the actual reason. This checks for a
// usable message however the error is shaped.
export function getErrorMessage(err: unknown): string {
  if (err instanceof Error) return err.message
  if (typeof err === 'object' && err !== null && 'message' in err && typeof err.message === 'string') {
    return err.message
  }
  return String(err)
}

// The relational tenant-integrity triggers (hotsflow-core migration
// 20260909110434_enforce_guest_requests_hotel_integrity.sql) reject a
// cross-hotel reference by raising Postgres check_violation (23514) with
// one of these fixed strings as the message -- a stable, unique reference
// for this specific failure, unlike the generic wording every other error
// on these forms falls back to. Surfacing it verbatim in the UI lets staff
// report a precise, reproducible code instead of "something went wrong".
const TENANT_INTEGRITY_ERROR_REFS = new Set([
  'stays_room_hotel_mismatch',
  'stays_creator_hotel_mismatch',
  'guest_request_stay_hotel_mismatch',
  'guest_request_room_hotel_mismatch',
  'guest_request_type_hotel_mismatch',
  'guest_request_creator_hotel_mismatch',
  'guest_request_acceptor_hotel_mismatch',
])

export function tenantIntegrityErrorRef(err: unknown): string | null {
  if (typeof err !== 'object' || err === null) return null
  const code = 'code' in err ? (err as { code?: unknown }).code : undefined
  const message = 'message' in err ? (err as { message?: unknown }).message : undefined
  if (code !== '23514' || typeof message !== 'string' || !TENANT_INTEGRITY_ERROR_REFS.has(message)) return null
  return message
}
