/**
 * E2E runs against a throwaway FastAPI backend on :8001 with its own SQLite
 * file (started by `npm run e2e:api`), never against the real server. The
 * Next app under test is pointed at it by playwright.config.ts.
 */
export const E2E = {
  port: 3100,
  baseURL: 'http://localhost:3100',
  apiUrl: 'http://127.0.0.1:8001',
} as const;
