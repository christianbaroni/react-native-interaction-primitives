import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^react$/,
        replacement: path.resolve(rootDir, 'node_modules/react/index.js'),
      },
      {
        find: /^react-native$/,
        replacement: path.resolve(rootDir, 'tests/mocks/react-native.ts'),
      },
      {
        find: /^react-native\/Libraries\/Utilities\/codegenNativeCommands$/,
        replacement: path.resolve(rootDir, 'tests/mocks/codegenNativeCommands.ts'),
      },
      {
        find: /^react-native-reanimated$/,
        replacement: path.resolve(rootDir, 'tests/mocks/react-native-reanimated.ts'),
      },
    ],
  },
  test: {
    clearMocks: true,
    environment: 'jsdom',
    restoreMocks: true,
  },
});
