import base from '@homisuite/config/eslint.base.mjs'

export default [
  ...base,
  {
    languageOptions: {
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
  },
]
