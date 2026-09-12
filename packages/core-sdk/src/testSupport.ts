// Shared test-only helper for mocking a Supabase query chain. Not exported
// from index.ts — nothing outside the SDK's own tests should import this.
import { vi } from 'vitest'

export interface MockQueryResult<T> {
  data: T
  error: { message: string } | null
}

interface MockQueryBuilder<T> extends PromiseLike<MockQueryResult<T>> {
  select: (...args: unknown[]) => MockQueryBuilder<T>
  eq: (...args: unknown[]) => MockQueryBuilder<T>
  in: (...args: unknown[]) => MockQueryBuilder<T>
  is: (...args: unknown[]) => MockQueryBuilder<T>
  or: (...args: unknown[]) => MockQueryBuilder<T>
  order: (...args: unknown[]) => MockQueryBuilder<T>
  insert: (...args: unknown[]) => MockQueryBuilder<T>
  update: (...args: unknown[]) => MockQueryBuilder<T>
  upsert: (...args: unknown[]) => MockQueryBuilder<T>
  delete: (...args: unknown[]) => MockQueryBuilder<T>
  returns: (...args: unknown[]) => MockQueryBuilder<T>
  maybeSingle: () => Promise<MockQueryResult<T>>
  single: () => Promise<MockQueryResult<T>>
}

// Chain methods (select/eq/order/returns) return the builder itself; the
// builder is also directly awaitable (mirrors supabase-js's real
// PostgrestFilterBuilder, which resolves to { data, error } without needing
// a terminal call when the caller expects an array) and maybeSingle()
// resolves to the same configured result.
export function mockQueryBuilder<T>(result: MockQueryResult<T>): MockQueryBuilder<T> {
  const builder = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    in: vi.fn(() => builder),
    is: vi.fn(() => builder),
    or: vi.fn(() => builder),
    order: vi.fn(() => builder),
    insert: vi.fn(() => builder),
    update: vi.fn(() => builder),
    upsert: vi.fn(() => builder),
    delete: vi.fn(() => builder),
    returns: vi.fn(() => builder),
    maybeSingle: vi.fn(() => Promise.resolve(result)),
    single: vi.fn(() => Promise.resolve(result)),
    then: (onFulfilled: (value: MockQueryResult<T>) => unknown) => Promise.resolve(result).then(onFulfilled),
  } as MockQueryBuilder<T>
  return builder
}

export function mockAuthenticatedUser(userId: string) {
  return { data: { user: { id: userId } } }
}

export function mockNoUser() {
  return { data: { user: null } }
}
