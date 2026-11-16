# Personal Finance App (Flutter)

Multi-user mobile rewrite of the Streamlit personal finance tracker.
Built with **Flutter + a self-hosted FastAPI backend** ([`backend/`](backend/README.md)),
with a Next.js web twin in [`web/`](web/README.md) on the same server, so the
same logins and data work everywhere.

## Features

- Email/password auth (FastAPI + JWT — accounts work immediately, no email round trip)
- Per-user accounts and transactions (every query scoped to the token's user)
- Add Income / Expense transactions, categorized
- Dashboard: total balance, account list, recent transactions, expense-by-category pie chart
- Transaction history with filters (type / account / category / date range) and CSV export
- Transfers between your own accounts as a first-class type — never counted as income or spending
- Account metadata: kind, spendable / reserved / locked, a minimum balance to protect, and what it's for
- Commitments: recurring bills and expected income, so the app knows what is already owed
- Goals that hold money back from the spendable pool
- Money engine (`lib/core/finance/`): safe-to-spend, runway, burn rate, per-account headroom — pure, tested Dart
- Dashboard led by **safe-to-spend**, not total balance, with a verdict line on whether the money lasts
- "Where your money is" bar — spendable vs bills vs protected vs reserved vs locked
- Deterministic alerts: running short before payday, accounts under their floor, bills the account can't cover, category spikes. Detected in Dart, so they can't be hallucinated
- **"Where should this come from?"** — enter an amount and the app picks the account, says why not the others, splits across accounts when needed, and works out the top-up transfer when the money has to leave one specific account
- **A coach that remembers and acts** — threaded conversations, nine tools over the money engine (position, alerts, accounts, commitments, spending, transactions, payment planning), and proposals rendered as cards with an Apply button. It never does arithmetic and never moves money on its own
- Model API key held server-side (`POST /coach/complete`), with a per-user-key fallback
- SMS import (Android): MoMo and bank alerts become ledger rows, deduplicated server-side
- Account management (create / rename / adjust balance / delete)
- Server-side balance recomputation after every write (no client drift)
- Default accounts and categories auto-seeded on signup

## Stack

- Flutter 3.19+
- `backend/` — FastAPI + SQLAlchemy (SQLite by default, Postgres-ready)
- `flutter_riverpod` — state management
- `go_router` — navigation
- `fl_chart` — charts
- `csv` + `share_plus` — CSV export
- `flutter_dotenv` — env config

---

## 1. Run the backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8000
```

First boot creates the tables (SQLite file `backend/finance.db`). See
[`backend/README.md`](backend/README.md) for `JWT_SECRET`, the coach's
`OPENAI_API_KEY`, and pointing `DATABASE_URL` at Postgres.

## 2. Configure the app

```bash
cp .env.example .env
```

Edit `.env`:

```
API_URL=http://10.0.2.2:8000
```

`10.0.2.2` is your machine as seen from the Android emulator. On a real phone
use your machine's LAN IP, e.g. `http://192.168.1.20:8000` (same Wi-Fi).

## 2b. The AI coach

The backend proxies the model so the API key lives on the server, not on every
user's phone. Set `OPENAI_API_KEY` in `backend/.env` and restart it.

Until you do, the coach falls back to a per-user key entered in
**Settings → AI coach**, so nothing breaks — but that key sits on the device,
which is what the server path exists to fix.

**The proxy does no financial reasoning.** It verifies the caller's token,
forwards the request, and returns the response. All the maths lives in the Dart
money engine, which is tested; a second implementation would drift from it.
Tools run on the client against that engine.

## 3. Run

```bash
flutter pub get
flutter run
```

Pick a connected Android device or emulator.

### Build release APK

```bash
flutter build apk --release
```

APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Project structure

```
backend/
  app/                            # FastAPI: auth, ledger, SMS import, coach proxy
lib/
  main.dart                       # entry, ApiClient init
  app.dart                        # MaterialApp + router
  core/
    router.dart                   # go_router with auth redirect
    api_client.dart               # bearer-token HTTP client (the one way to the server)
    theme.dart
    formatters.dart               # currency / date helpers
    constants.dart                # category lists
    finance/
      money_engine.dart           # safe-to-spend, runway, headroom (pure, tested)
      alerts.dart                 # deterministic rules — what's worth saying, and why
      payment_planner.dart        # which account a payment should come from
      snapshot_provider.dart      # the app's single view of your money
  features/
    auth/ accounts/ transactions/ payments/ planning/ dashboard/
    categories/ insights/ sms/ settings/ reports/
  shared/
    widgets/home_shell.dart       # bottom nav
web/                              # Next.js twin on the same backend
supabase/                         # legacy — the schema the backend was ported from
```

## Currency

Defaults to GHS (Ghana cedi). Change in `lib/core/formatters.dart`.

## Roadmap (v2)

- Recurring transactions
- Budget targets per category
- iOS build + Apple sign-in
