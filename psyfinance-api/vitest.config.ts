import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Run test files sequentially so they don't race on the shared test DB.
    fileParallelism: false,
    testTimeout: 15000,
  },
});
