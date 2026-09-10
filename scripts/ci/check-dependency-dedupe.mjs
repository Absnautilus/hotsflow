#!/usr/bin/env node
// Fails if more than one resolved version of a bundle-sensitive package
// (react, react-dom, @supabase/supabase-js) exists anywhere in the installed
// dependency tree -- the root cause of "two copies of React in the bundle"
// is always two resolved versions in node_modules, so catching it here (via
// the actual install, not guessing from package.json ranges) is exact and
// catches it long before any app is built.
import { execFileSync } from 'node:child_process'

const WATCHED = ['react', 'react-dom', '@supabase/supabase-js']

function collectVersions(tree, name, versions) {
  if (!tree || typeof tree !== 'object') return
  const deps = tree.dependencies ?? {}
  for (const [depName, dep] of Object.entries(deps)) {
    if (depName === name && dep.version) versions.add(dep.version)
    collectVersions(dep, name, versions)
  }
}

let failed = false

for (const name of WATCHED) {
  let tree
  try {
    const out = execFileSync('npm', ['ls', name, '--all', '--json'], {
      encoding: 'utf8',
      // npm exits non-zero when a peer/dep tree has *any* unrelated
      // problem (e.g. an unmet optional peer) -- we only care about the
      // resolved-versions shape, so ignore the exit code, not the output.
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    tree = JSON.parse(out)
  } catch (err) {
    if (err.stdout) {
      try {
        tree = JSON.parse(err.stdout)
      } catch {
        continue
      }
    } else {
      continue
    }
  }

  const versions = new Set()
  collectVersions(tree, name, versions)
  if (tree.version && tree.name === name) versions.add(tree.version)

  if (versions.size > 1) {
    console.error(`${name}: multiple resolved versions found in the install tree: ${[...versions].join(', ')}`)
    failed = true
  } else if (versions.size === 1) {
    console.log(`${name}: single resolved version (${[...versions][0]}) -- OK`)
  } else {
    console.log(`${name}: not installed -- OK`)
  }
}

if (failed) {
  console.error('\nDuplicate package versions found -- run `npm dedupe` and commit the updated lockfile.')
  process.exit(1)
}
