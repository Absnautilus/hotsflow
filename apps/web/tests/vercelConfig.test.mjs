import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { describe, it } from 'node:test'

const config = JSON.parse(
  await readFile(new URL('../vercel.json', import.meta.url), 'utf8'),
)

describe('Vercel routing', () => {
  it('falls back to the Vite entry point for client-side routes', () => {
    assert.deepEqual(config.rewrites, [
      {
        source: '/(.*)',
        destination: '/index.html',
      },
    ])
  })
})
