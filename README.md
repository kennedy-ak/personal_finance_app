# Personal Finance App (Flutter)

Multi-user mobile rewrite of the Streamlit personal finance tracker.
Built with **Flutter + Supabase** (auth, Postgres, RLS).

## Features

- Email/password auth (Supabase Auth)
- Per-user accounts and transactions (RLS-enforced isolation)
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
- Model API key held server-side in a Supabase Edge Function, with a per-user-key fallback
- Account management (create / rename / adjust balance / delete)
- Server-side balance recomputation via Postgres trigger (no client drift)
- Default accounts auto-seeded on signup

## Stack

- Flutter 3.19+
- `supabase_flutter` — auth + DB
- `flutter_riverpod` — state management
- `go_router` — navigation
- `fl_chart` — charts
- `csv` + `share_plus` — CSV export
- `flutter_dotenv` — env config

---

## 1. Set up Supabase

1. Create a free project at https://supabase.com
2. In **SQL Editor**, run these in order:
   - [`supabase/schema.sql`](supabase/schema.sql) — base tables, RLS, triggers
   - [`supabase/migrations/0002_money_foundation.sql`](supabase/migrations/0002_money_foundation.sql) — transfers, account metadata, obligations, goals. Safe to re-run.
   - [`supabase/migrations/0003_convert_legacy_transfers.sql`](supabase/migrations/0003_convert_legacy_transfers.sql) — **optional, one-time.** Rewrites old faked transfer pairs as single rows. Back up first; your figures are already correct without it.
   - [`supabase/migrations/0004_coach_memory.sql`](supabase/migrations/0004_coach_memory.sql) — conversation threads and messages for the coach. Safe to re-run.
3. In **Authentication → Providers**, enable **Email**.
   For dev, disable "Confirm email" so signups log in immediately.
4. Grab your **Project URL** and **anon public key** from **Settings → API**.

## 2. Configure the app

```bash
cp .env.example .env
```

Edit `.env`:

```
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

> The anon key is safe to ship in the client — RLS policies enforce per-user access.

## 2b. Deploy the AI coach (optional but recommended)

The coach runs through a Supabase Edge Function so the model API key lives on the
server, not on every user's phone:

```bash
supabase secrets set OPENAI_API_KEY=sk-...
supabase functions deploy coach
```

Optionally `supabase secrets set COACH_MODEL=gpt-4o-mini` to pick the model.

Until you deploy it, the coach falls back to a per-user key entered in
**Settings → AI coach**, so nothing breaks — but that key sits on the device,
which is what the function exists to fix.

**The function does no financial reasoning.** It verifies the caller's JWT,
forwards the request, and returns the response. All the maths lives in the Dart
money engine, which is tested; a second implementation in TypeScript would drift
from it. Tools run on the client against that engine.

## 3. Run

```bash
flutter pub get
flutter run
```

Pick a connected Android device, iOS simulator, or run on web with `flutter run -d chrome`.

### Build release APK

```bash
flutter build apk --release
```

APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Project structure

```
lib/
  main.dart                       # entry, Supabase init
  app.dart                        # MaterialApp + router
  core/
    router.dart                   # go_router with auth redirect
    supabase_client.dart
    theme.dart
    formatters.dart               # currency / date helpers
    constants.dart                # category lists
    finance/
      money_engine.dart           # safe-to-spend, runway, headroom (pure, tested)
      alerts.dart                 # deterministic rules — what's worth saying, and why
      payment_planner.dart        # which account a payment should come from
      snapshot_provider.dart      # the app's single view of your money
  features/
    auth/
      data/auth_repository.dart
      presentation/login_screen.dart
      presentation/signup_screen.dart
    accounts/
      data/account_repository.dart
      domain/account.dart
      presentation/accounts_screen.dart
    transactions/
      data/transaction_repository.dart
      domain/transaction.dart
      presentation/add_transaction_screen.dart
      presentation/history_screen.dart
    payments/
      presentation/pay_screen.dart # "I need to send X — where from?"
    planning/
      domain/obligation.dart      # bills + expected income, with recurrence
      domain/goal.dart
      data/…                      # repositories
      presentation/plan_screen.dart
    dashboard/
      presentation/dashboard_screen.dart
      presentation/widgets/        # safe-to-spend hero, placement bar, alerts
  shared/
    widgets/home_shell.dart       # bottom nav
supabase/
  schema.sql                      # base tables, RLS, triggers
  migrations/                     # run after schema.sql, in order
```

## Currency

Defaults to GHS (Ghana cedi). Change in `lib/core/formatters.dart`.

## Roadmap (v2)

- Weekly reports tab (matches old Streamlit weekly view)
- AI financial insights (via Supabase Edge Function — keeps API key off-device)
- Migration script: SQLite (`expense_tracker.db`) → Supabase
- Recurring transactions
- Budget targets per category
- iOS build + Apple sign-in
