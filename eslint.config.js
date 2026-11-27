import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  {
    ignores: ['node_modules/', 'dist/', 'build/', 'vite.config.ts', 'tests/'],
  },
  {
    files: ['**/*.ts', '**/*.tsx'],
    extends: [eslint.configs.recommended, ...tseslint.configs.recommended],
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    files: ['eslint.config.js'],
    languageOptions: {
      sourceType: 'module',
      parserOptions: {
        project: './tsconfig.eslint.json',
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  prettier
);
