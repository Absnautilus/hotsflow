import { test, expect } from '@playwright/test'

// Always runnable: only needs the dev server up (see playwright.config.ts's
// webServer) and *some* value in apps/web/.env.local for
// VITE_SUPABASE_URL/VITE_SUPABASE_ANON_KEY -- client construction doesn't
// make a network call, so a placeholder is enough (same assumption the
// existing packages/core-sdk/src/client.test.ts unit test makes).
test('shows the login form when signed out', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('heading', { name: 'Bentornato' })).toBeVisible()
  await expect(page.getByLabel('Email o identificativo')).toBeVisible()
  await expect(page.getByLabel('Password', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Accedi' })).toBeVisible()
})

// Requires a real local Supabase stack (`supabase start`) with the one
// fixed test user provisioned by scripts/e2e/create-test-user.mjs, and
// apps/web/.env.local pointed at that local stack's real URL/anon key.
// See docs/e2e-testing.md. Skips instead of failing when that setup hasn't
// been done, so this file stays runnable (Test 1 above) without it.
test('logs in and reaches Home', async ({ page }) => {
  test.skip(
    !process.env.E2E_TEST_EMAIL || !process.env.E2E_TEST_PASSWORD,
    'requires a local Supabase instance and a provisioned test user -- see docs/e2e-testing.md',
  )

  const consoleErrors: string[] = []
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text())
  })

  await page.goto('/')
  await page.getByLabel('Email o identificativo').fill(process.env.E2E_TEST_EMAIL!)
  await page.getByLabel('Password', { exact: true }).fill(process.env.E2E_TEST_PASSWORD!)
  await page.getByRole('button', { name: 'Accedi' }).click()

  await expect(page.getByRole('heading', { name: 'Home' })).toBeVisible()
  expect(consoleErrors).toEqual([])
})
