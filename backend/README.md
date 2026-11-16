# Personal Finance backend

The FastAPI replacement for Supabase. One server for both clients — the
Flutter app and `web/` — owning auth, the ledger, the SMS-import guarantees
and the AI-coach proxy.

## Run it

```bash
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000
```

First run creates `finance.db` (SQLite) next to this file. Interactive API
docs live at http://localhost:8000/docs.

## Configure

Copy `.env.example` to `.env`:

- `JWT_SECRET` — **required** before exposing the server beyond your machine.
- `OPENAI_API_KEY` / `COACH_MODEL` — the coach proxy; without a key the rest
  of the app works and the coach explains it is not configured.
- `DATABASE_URL` — point at Postgres (`postgresql+psycopg://…`) when SQLite
  is outgrown; tables are created on boot either way.
- `CORS_ORIGINS` — comma-separated origins, `*` by default.

## Point the clients at it

- **Flutter app**: set `API_URL=http://<your-machine>:8000` in the app's
  `.env` (the Android emulator reaches your machine at `10.0.2.2`).
- **Web**: set `NEXT_PUBLIC_API_URL=http://localhost:8000` in `web/.env.local`.

## What replaced what

| Supabase | Here |
| --- | --- |
| Auth (GoTrue) | `/auth/*` — bcrypt + 30-day JWT |
| RLS policies | every query filters on the token's user id |
| balance triggers (0001/0002) | `app/services/balances.py` after each write |
| signup trigger + category seed (0007) | `app/services/defaults.py` |
| `rename_category`, `category_usage_count` | `/categories/{id}/rename`, `/categories/{id}/usage` |
| `sms_import_txn` & friends (0006/0008) | `/sms/import`, `/sms/hold`, `/sms/ignore`, `/sms/inbox/{id}/resolve` |
| `coach` Edge Function | `POST /coach/complete` |

Email flows (confirmation, password reset) do not exist here — accounts work
immediately, and passwords change from Settings while signed in.
