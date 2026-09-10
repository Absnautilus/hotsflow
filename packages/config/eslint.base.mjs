// Shared ESLint flat-config base for every workspace in this repository.
// A workspace's own eslint.config.mjs imports this and spreads it first,
// then adds only what that workspace actually needs on top -- never a
// second, divergent copy of these rules.
import js from '@eslint/js'
import tseslint from 'typescript-eslint'
import reactHooks from 'eslint-plugin-react-hooks'

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'error',
    },
  },
  {
    // Only the two long-stable rules -- not the plugin's full
    // "recommended-latest" preset, which bundles newer React Compiler
    // rules (purity, immutability, set-state-in-render, ...) that no
    // workspace here has been written against.
    plugins: { 'react-hooks': reactHooks },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
    },
  },
  {
    ignores: ['dist/**', 'node_modules/**'],
  },
)
