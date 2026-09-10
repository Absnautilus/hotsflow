import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { resolveHousekeepingAccess } from './resolveHousekeepingAccess.ts'

describe('resolveHousekeepingAccess', () => {
  it('is not-entitled when the property has no guest_requests entitlement', () => {
    const result = resolveHousekeepingAccess({ entitled: false, legacyHotelId: null, hasCompatibleProfile: false })
    assert.deepEqual(result, { status: 'not-entitled' })
  })

  it('is not-entitled even if a stale hotelId/profile slipped through', () => {
    // Regression guard: entitlement must win over stale mapping/profile data,
    // e.g. a property whose module was just disabled.
    const result = resolveHousekeepingAccess({ entitled: false, legacyHotelId: 'hotel-1', hasCompatibleProfile: true })
    assert.deepEqual(result, { status: 'not-entitled' })
  })

  it('is no-mapping when entitled but the property has no bridged legacy hotel (e.g. Hotel Demo)', () => {
    const result = resolveHousekeepingAccess({ entitled: true, legacyHotelId: null, hasCompatibleProfile: false })
    assert.deepEqual(result, { status: 'no-mapping' })
  })

  it('is no-profile when entitled and mapped but the current user has no operational profile there', () => {
    const result = resolveHousekeepingAccess({ entitled: true, legacyHotelId: 'hotel-1', hasCompatibleProfile: false })
    assert.deepEqual(result, { status: 'no-profile' })
  })

  it('is compatible only when all three conditions hold, and carries the resolved hotelId', () => {
    const result = resolveHousekeepingAccess({ entitled: true, legacyHotelId: 'hotel-1', hasCompatibleProfile: true })
    assert.deepEqual(result, { status: 'compatible', hotelId: 'hotel-1' })
  })
})
