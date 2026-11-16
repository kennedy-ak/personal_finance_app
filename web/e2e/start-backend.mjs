/**
 * Starts the FastAPI backend for E2E on :8001 with its own throwaway SQLite
 * file, wiped on every start so runs never depend on leftovers.
 *
 *   npm run e2e:api
 *
 * Uses backend/.venv (create it per backend/README.md first).
 */
import { spawn } from 'node:child_process';
import { rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const backendDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'backend');
const dbFile = join(backendDir, 'e2e.db');

try {
  rmSync(dbFile);
  console.log('Removed previous e2e.db');
} catch {
  /* first run */
}

const uvicorn =
  process.platform === 'win32'
    ? join(backendDir, '.venv', 'Scripts', 'uvicorn.exe')
    : join(backendDir, '.venv', 'bin', 'uvicorn');

const child = spawn(uvicorn, ['app.main:app', '--port', '8001'], {
  cwd: backendDir,
  stdio: 'inherit',
  env: {
    ...process.env,
    DATABASE_URL: `sqlite:///${dbFile.replaceAll('\\', '/')}`,
    JWT_SECRET: 'e2e-only-secret',
    OPENAI_API_KEY: '', // the suite mocks /coach/complete at the network layer
  },
});

child.on('exit', (code) => process.exit(code ?? 0));
