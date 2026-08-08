import js from '@eslint/js';

export default [
  {
    ignores: ['node_modules/**', 'coverage/**'],
  },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
      globals: {
        process: 'readonly',
        console: 'readonly',
        URL: 'readonly',
      },
    },
    rules: {
      // D2: no TypeScript, so the cheap static guards matter more than usual.
      eqeqeq: ['error', 'always'],
      'no-console': 'warn',
      'no-var': 'error',
      'prefer-const': 'error',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-promise-executor-return': 'error',
      'no-unmodified-loop-condition': 'error',
      // Deliberately NOT enabled: require-await. Fastify plugins and route
      // handlers must be async by the framework's own contract, so an async
      // function with no await is idiomatic here, not a smell. The rule that
      // would genuinely help — catching floating promises — is a typed-lint
      // rule and unavailable without TypeScript. Code review carries that.
    },
  },
];
