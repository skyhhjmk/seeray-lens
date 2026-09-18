import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default [
  js.configs.recommended,
  {
    files: ['e2e/**/*.mjs', 'playwright.config.mjs'],
    languageOptions: {
      globals: {
        URL: 'readonly',
        process: 'readonly',
        window: 'readonly',
        localStorage: 'readonly',
        sessionStorage: 'readonly',
      },
    },
  },
  ...tseslint.configs.recommended,
];
