# Pursely — web

The Next.js twin of the Flutter app, on the same FastAPI backend
(`../backend`), so the same logins and data work in both.

## Run it

1. Start the backend (see `../backend/README.md`) on :8000.
2. Point the web app at it:

   ```bash
   cp .env.example .env.local   # NEXT_PUBLIC_API_URL=http://localhost:8000
   ```

3. ```bash
   npm install
   npm run dev
   ```

   Open http://localhost:3000.

## Checks

```bash
npm run typecheck
npm run lint
npm test          # vitest — money engine, coach, reports
```

### End-to-end (Playwright)

The suite runs against a throwaway backend on :8001 with its own SQLite file,
never the real server:

```bash
npm run e2e:api   # terminal 1 — wipes e2e.db and starts ../backend on :8001
npm run e2e       # terminal 2 — starts Next on :3100 against it, runs the suite
```

## How it hangs together

- `src/lib/api/client.ts` — the one way to the server: bearer token in
  localStorage, a `pf_signed_in` marker cookie so `src/proxy.ts` can redirect
  signed-out visitors before a protected page renders.
- `src/lib/data/repositories.ts` — reads/writes per table, mirroring the Dart
  repositories under `../lib/features/*/data/`.
- `src/lib/finance/` — the money engine, a line-for-line twin of
  `../lib/core/finance/`. Keep both in step.
- `src/lib/coach/` — the coach: tools run in the browser against the engine;
  the model is reached only through the backend's `POST /coach/complete`.
