import { describe, expect, it } from 'vitest'
import { createCoreClient } from './client'

describe('createCoreClient', () => {
  it('exposes the raw Supabase client plus the typed SDK methods', () => {
    const core = createCoreClient('https://example.supabase.co', 'anon-key-not-real')

    expect(core.raw).toBeDefined()
    expect(typeof core.getCurrentProfile).toBe('function')
    expect(typeof core.getAccessibleProperties).toBe('function')
    expect(typeof core.getMembership).toBe('function')
    expect(typeof core.hasPermission).toBe('function')
    expect(typeof core.getEnabledModules).toBe('function')
  })
})
