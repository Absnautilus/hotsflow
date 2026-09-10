#!/usr/bin/env node
// Detects import cycles across every workspace's src/ tree, using only
// relative imports (workspace-crossing imports are already forbidden by
// check-workspace-boundaries.mjs, which runs first in CI) -- so any real
// cycle would have to be a same-workspace mistake.
import { dirname, resolve } from 'node:path'
import { existsSync, readFileSync } from 'node:fs'
import { discoverWorkspaces, listSourceFiles, extractImportSpecifiers } from './lib/workspaces.mjs'

const EXTENSIONS = ['', '.ts', '.tsx', '.js', '.jsx', '.mjs', '/index.ts', '/index.tsx']

function resolveRelative(fromFile, specifier) {
  const base = resolve(dirname(fromFile), specifier)
  for (const ext of EXTENSIONS) {
    const candidate = base + ext
    if (existsSync(candidate)) return candidate
  }
  return null
}

const graph = new Map() // file -> Set<file>

for (const ws of discoverWorkspaces()) {
  const srcDir = resolve(ws.dir, 'src')
  for (const file of listSourceFiles(srcDir)) {
    const source = readFileSync(file, 'utf8')
    const edges = new Set()
    for (const specifier of extractImportSpecifiers(source)) {
      if (!specifier.startsWith('.')) continue
      const resolved = resolveRelative(file, specifier)
      if (resolved) edges.add(resolved)
    }
    graph.set(file, edges)
  }
}

const WHITE = 0
const GRAY = 1
const BLACK = 2
const color = new Map()
const cycles = []

function visit(node, stack) {
  color.set(node, GRAY)
  stack.push(node)
  for (const next of graph.get(node) ?? []) {
    const state = color.get(next) ?? WHITE
    if (state === WHITE) {
      visit(next, stack)
    } else if (state === GRAY) {
      const cycleStart = stack.indexOf(next)
      cycles.push([...stack.slice(cycleStart), next])
    }
  }
  stack.pop()
  color.set(node, BLACK)
}

for (const node of graph.keys()) {
  if ((color.get(node) ?? WHITE) === WHITE) visit(node, [])
}

if (cycles.length > 0) {
  console.error('Circular imports found:\n')
  for (const cycle of cycles) {
    console.error(`  ${cycle.map((f) => f.replace(process.cwd() + '/', '')).join('\n    -> ')}`)
    console.error('')
  }
  console.error(`${cycles.length} cycle(s).`)
  process.exit(1)
}

console.log('No circular imports found.')
