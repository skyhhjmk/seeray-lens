import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.pw.mjs',
  fullyParallel: false,
  reporter: 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    browserName: 'chromium',
    locale: 'zh-CN',
    headless: true,
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node ./e2e/browser-fixture.mjs',
    url: 'http://127.0.0.1:4173/fixture',
    reuseExistingServer: false,
    timeout: 10_000,
  },
});
