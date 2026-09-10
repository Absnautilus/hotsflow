// Shared ESLint flat-config base for every workspace in this repository.
// A workspace's own eslint.config.mjs imports this and spreads it first,
// then adds only what that workspace actually needs on top -- never a
// second, divergent copy of these rules.
import js from '@eslint/js'
import tseslint from 'typescript-eslint'

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
    ignores: ['dist/**', 'node_modules/**'],
  },
)
