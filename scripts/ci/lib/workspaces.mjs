import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

const GROUPS = ['apps', 'modules', 'packages']
const REPO_ROOT = new URL('../../../', import.meta.url).pathname

// Discovers every workspace under apps/*, modules/*, packages/* that has its
// own package.json -- the same set `npm workspaces` would resolve, found by
// walking the filesystem directly so these scripts have no dependency on npm
// being installed or configured a particular way.
export function discoverWorkspaces() {
  const workspaces = []
  for (const group of GROUPS) {
    const groupDir = join(REPO_ROOT, group)
    let entries
    try {
      entries = readdirSync(groupDir)
    } catch {
      continue
    }
    for (const name of entries) {
      const dir = join(groupDir, name)
      if (!statSync(dir).isDirectory()) continue
      const pkgPath = join(dir, 'package.json')
      let pkg
      try {
        pkg = JSON.parse(readFileSync(pkgPath, 'utf8'))
      } catch {
        continue
      }
      workspaces.push({ group, name, dir, pkgPath, pkg })
    }
  }
  return workspaces
}

export function listSourceFiles(dir) {
  const files = []
  const walk = (current) => {
    let entries
    try {
      entries = readdirSync(current, { withFileTypes: true })
    } catch {
      return
    }
    for (const entry of entries) {
      if (entry.name === 'node_modules' || entry.name === 'dist') continue
      const full = join(current, entry.name)
      if (entry.isDirectory()) {
        walk(full)
      } else if (/\.(ts|tsx|js|jsx|mjs)$/.test(entry.name) && !entry.name.endsWith('.test.ts') && !entry.name.endsWith('.test.mjs')) {
        files.push(full)
      }
    }
  }
  walk(dir)
  return files
}

const IMPORT_RE = /(?:from|require\()\s*['"]([^'"]+)['"]/g

export function extractImportSpecifiers(source) {
  const specifiers = []
  let match
  while ((match = IMPORT_RE.exec(source))) {
    specifiers.push(match[1])
  }
  return specifiers
}

export { REPO_ROOT }
