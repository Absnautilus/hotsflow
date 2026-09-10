import base from '@hotsflow/config/eslint.base.mjs'

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
