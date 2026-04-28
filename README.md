# Personal Finance App (Flutter)

Multi-user mobile rewrite of the Streamlit personal finance tracker.
Built with **Flutter + Supabase** (auth, Postgres, RLS).

## Features

- Email/password auth (Supabase Auth)
- Per-user accounts and transactions (RLS-enforced isolation)
- Add Income / Expense transactions, categorized
- Dashboard: total balance, account list, recent transactions, expense-by-category pie chart
- Transaction history with filters (type / account / category / date range) and CSV export
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
2. In **SQL Editor**, paste and run [`supabase/schema.sql`](supabase/schema.sql)
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
    dashboard/
      presentation/dashboard_screen.dart
  shared/
    widgets/home_shell.dart       # bottom nav
supabase/
  schema.sql                      # tables, RLS, triggers
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
