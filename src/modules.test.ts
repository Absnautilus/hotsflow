import { describe, expect, it } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './types/database'
import { getEnabledModules } from './modules'
import { mockQueryBuilder } from './testSupport'

describe('getEnabledModules', () => {
  it('maps enabled property_modules rows, joined with their module, to the domain shape', async () => {
    const client = {
      from: () =>
        mockQueryBuilder({
          data: [
            { enabled: true, modules: { id: 'mod-1', slug: 'guest_requests', display_name: 'Guest Requests' } },
            { enabled: true, modules: { id: 'mod-2', slug: 'shifts', display_name: 'Shift Planner' } },
          ],
          error: null,
        }),
    } as unknown as SupabaseClient<Database>

    await expect(getEnabledModules(client, 'property-1')).resolves.toEqual([
      { moduleId: 'mod-1', slug: 'guest_requests', displayName: 'Guest Requests', enabled: true },
      { moduleId: 'mod-2', slug: 'shifts', displayName: 'Shift Planner', enabled: true },
    ])
  })

  it('returns an empty array when nothing is enabled', async () => {
    const client = {
      from: () => mockQueryBuilder({ data: [], error: null }),
    } as unknown as SupabaseClient<Database>

    await expect(getEnabledModules(client, 'property-1')).resolves.toEqual([])
  })

  it('drops a row whose joined module is unexpectedly missing rather than crashing', async () => {
    const client = {
      from: () =>
        mockQueryBuilder({
          data: [{ enabled: true, modules: null }],
          error: null,
        }),
    } as unknown as SupabaseClient<Database>

    await expect(getEnabledModules(client, 'property-1')).resolves.toEqual([])
  })
})
