import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['rules_test/**/*.test.ts'],
    // One emulator, one rules deployment, one shared Firestore instance. Two
    // files clearing it concurrently would delete each other's fixtures.
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 60_000,
  },
});
