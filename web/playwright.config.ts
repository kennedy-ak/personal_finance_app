import { defineConfig, devices } from '@playwright/test';
import { E2E } from './e2e/env';

/**
 * End-to-end tests against a throwaway FastAPI backend:
 *   npm run e2e:api    # once — starts ../backend on :8001 with a fresh SQLite db
 *   npm run e2e        # starts Next on :3100 pointed at it, runs the suite
 *
 * The env passed to the web server overrides .env.local, so the app under test
 * talks to 127.0.0.1:8001 and never to the real server.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    baseURL: E2E.baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `npx next dev -p ${E2E.port}`,
    url: `${E2E.baseURL}/login`,
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      NEXT_DIST_DIR: '.next-e2e',
      NEXT_PUBLIC_API_URL: E2E.apiUrl,
    },
  },
});
