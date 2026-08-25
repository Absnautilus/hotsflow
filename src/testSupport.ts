// Shared test-only helper for mocking a Supabase query chain. Not exported
// from index.ts — nothing outside the SDK's own tests should import this.
import { vi } from 'vitest'

export interface MockQueryResult<T> {
  data: T
  error: { message: string } | null
}

// Chain methods (select/eq/order/returns) return the builder itself; the
// builder is also directly awaitable (mirrors supabase-js's real
// PostgrestFilterBuilder, which resolves to { data, error } without needing
// a terminal call when the caller expects an array) and maybeSingle()
// resolves to the same configured result.
export function mockQueryBuilder<T>(result: MockQueryResult<T>) {
  const builder = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    order: vi.fn(() => builder),
    returns: vi.fn(() => builder),
    maybeSingle: vi.fn(() => Promise.resolve(result)),
    then: (onFulfilled: (value: MockQueryResult<T>) => unknown) => Promise.resolve(result).then(onFulfilled),
  }
  return builder
}

export function mockAuthenticatedUser(userId: string) {
  return { data: { user: { id: userId } } }
}

export function mockNoUser() {
  return { data: { user: null } }
}
