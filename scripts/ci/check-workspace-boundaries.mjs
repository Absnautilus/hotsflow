#!/usr/bin/env node
// Enforces docs/architecture/monorepo.md's dependency rules:
//   apps/*     -> modules/*, packages/*         (allowed)
//   modules/*  -> packages/core-sdk, packages/ui (allowed; no other module,
//                                                  no apps/*)
//   packages/core-sdk, packages/ui -> no other @hotsflow/* runtime dep
//   no relative import ever crosses a workspace's own root directory
//   no deep import into another workspace's internals -- only its declared
//   package.json "exports" (or a bare package specifier)
//
// packages/config is build tooling only (tsconfig/eslint bases consumed via
// devDependencies), not part of this runtime graph, and is not checked here.
import { dirname, relative, resolve } from 'node:path'
import { discoverWorkspaces, listSourceFiles, extractImportSpecifiers } from './lib/workspaces.mjs'
import { readFileSync } from 'node:fs'

const workspaces = discoverWorkspaces()
const byName = new Map(workspaces.map((w) => [w.pkg.name, w]))
const violations = []

function allowedTargets(ws) {
  if (ws.group === 'apps') return null // apps may depend on any module/package
  if (ws.group === 'modules') return new Set(['@hotsflow/core-sdk', '@hotsflow/ui'])
  if (ws.group === 'packages' && (ws.name === 'core-sdk' || ws.name === 'ui')) return new Set()
  return null // other packages (e.g. future shared packages) unrestricted for now
}

function isRuntimeHotsflowDep(name) {
  return name.startsWith('@hotsflow/') && name !== '@hotsflow/config'
}

// 1. Dependency-direction check, from each workspace's own package.json.
for (const ws of workspaces) {
  if (ws.name === 'config') continue
  const allowed = allowedTargets(ws)
  if (allowed === null) continue
  const deps = { ...(ws.pkg.dependencies ?? {}) }
  for (const dep of Object.keys(deps)) {
    if (!isRuntimeHotsflowDep(dep)) continue
    if (ws.group === 'modules' && dep.startsWith('@hotsflow/') && !allowed.has(dep)) {
      violations.push(`${ws.pkg.name}: depends on ${dep}, but a module may only depend on @hotsflow/core-sdk or @hotsflow/ui`)
    } else if (ws.group === 'packages' && allowed.size === 0) {
      violations.push(`${ws.pkg.name}: depends on ${dep}, but packages/${ws.name} must have no @hotsflow/* runtime dependency`)
    }
  }
}

// 2. Import-level check: no relative import escapes its own workspace root,
//    no deep import into another workspace's internals.
for (const ws of workspaces) {
  const srcDir = resolve(ws.dir, 'src')
  for (const file of listSourceFiles(srcDir)) {
    const source = readFileSync(file, 'utf8')
    for (const specifier of extractImportSpecifiers(source)) {
      if (specifier.startsWith('.')) {
        const resolved = resolve(dirname(file), specifier)
        const rel = relative(ws.dir, resolved)
        if (rel.startsWith('..')) {
          violations.push(`${relative(process.cwd(), file)}: relative import '${specifier}' crosses out of its own workspace (${ws.pkg.name})`)
        }
        continue
      }
      const match = /^(@hotsflow\/[^/]+)(\/.*)?$/.exec(specifier)
      if (!match) continue
      const [, pkgName, subpath] = match
      if (pkgName === ws.pkg.name) continue // importing your own package name is fine
      const target = byName.get(pkgName)
      if (!target) continue // unknown/external -- not this check's concern
      if (subpath) {
        const exportKey = `.${subpath}`
        const exports = target.pkg.exports ?? {}
        if (!(exportKey in exports)) {
          violations.push(`${relative(process.cwd(), file)}: deep import '${specifier}' reaches into ${pkgName}'s internals -- only its declared package.json "exports" are a valid public API`)
        }
      }
    }
  }
}

if (violations.length > 0) {
  console.error('Workspace boundary violations found:\n')
  for (const v of violations) console.error(`  - ${v}`)
  console.error(`\n${violations.length} violation(s).`)
  process.exit(1)
}

console.log(`Workspace boundaries OK (${workspaces.length} workspace(s) checked).`)
