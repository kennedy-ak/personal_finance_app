# Moving this app to a new Supabase project

The old project is paused and past its one-click restore window, so the choice is
between **starting the schema fresh** (fast, loses old rows) and **recovering the
data out of the downloaded backup** (slower, needs Docker).

**Old project:** `personal finance` — ref `iavvszgzudxyuilzwdvs`, region `eu-north-1`,
Postgres `17.4.1.048`, status `INACTIVE`.

Because that project was created in July 2025 on Postgres 17, it uses **physical**
backups. The file you download is `db_cluster.backup`, a cluster image — *not* a
plain `.sql` file. You cannot feed it straight to `psql`. That is why Path B has a
local-restore step in the middle.

---

## Before anything else

Download both of these from the old project's dashboard page while it still
exists, even if you end up choosing Path A:

1. **the database backup** (`db_cluster.backup`)
2. **the Storage objects** — this app does not appear to use Storage, so expect
   this to be empty or absent

Do **not** delete the old project until the new one is verified. Deleting it
destroys the backups too, permanently.

> If the dashboard still offers **Resume project** rather than a download, take
> that instead — it is one click and keeps everything. Upgrading to Pro while the
> project is paused also re-enables the one-click restore, though a backup taken
> outside the compatibility window can still fail to restore.

### You may not need a second account

`kennedy-ak's Org` is on the free plan with **one** active project (`pragia-go`)
and nine paused. The free plan allows two active projects per organization, so
there is very likely a free slot in the account you already have — a brand new
project there would work for Path A without any account juggling. Worth checking
the billing page before creating a second account.

A second account is only genuinely required if that slot is taken, since one
account gets one free organization.

---

## What does not come across either way

Neither path carries these. They are dashboard/config state, not database state:

- **The `coach` Edge Function** — redeploy it and set its secret:
  ```bash
  supabase functions deploy coach --project-ref <NEW_REF>
  supabase secrets set OPENAI_API_KEY=sk-... --project-ref <NEW_REF>
  ```
- **Auth settings** — email confirmations, redirect URLs, providers
- **API keys** — new project means new URL and new anon key
- **`personal_finance_app/.env`** — point `SUPABASE_URL` and `SUPABASE_ANON_KEY`
  at the new project

Nothing else is needed: the schema uses no custom extensions, no Vault, no
`pg_cron`, and no Storage buckets.

---

## Path A — fresh schema, no old data

~15 minutes. Needs nothing installed.

1. Create the new account, then a new project on it. Note its ref, URL and anon key.
2. Dashboard → **SQL Editor** → **New query** → paste the whole of
   [`migrate_fresh_project.sql`](migrate_fresh_project.sql) → **Run**.
   Expect `Success. No rows returned.`
3. Do the three items under *What does not come across* above.
4. Sign up in the app. The `on_auth_user_created` trigger seeds the starter
   accounts and the default category list for the new user.

That file is `schema.sql` plus migrations 0002 and 0004–0010, concatenated in
dependency order. Every statement is idempotent, so re-running it is safe.

0009 and 0010 are the security hardening: they revoke `anon`'s access to the
`security definer` functions and pin `search_path` on the rest. They must travel
together — 0009's revokes named `anon` and so did nothing, because PostgreSQL's
default `EXECUTE` grant to `PUBLIC` outlived them; 0010 revokes from `PUBLIC`
and grants back explicitly. Afterwards the advisor still reports three
`authenticated can execute SECURITY DEFINER function` warnings for
`seed_default_categories`, `rename_category` and `category_usage_count`. Those
are intended: the app calls all three as a signed-in user.

`0003_convert_legacy_transfers.sql` is deliberately excluded — it converts
historical paired rows into single `Transfer` rows, and a fresh database has no
history to convert.

---

## Path B — bring the old data across

Needs **Docker Desktop running** (installed here, but the daemon was not up) and
**psql/pg_dump** (not installed here). The Supabase CLI can be run via `npx`
without installing.

### 1. Restore the backup into a local Postgres

Put `db_cluster.backup` in its own empty folder, then:

```bash
npx supabase init
mkdir -p supabase/.temp && echo '17.4.1.048' > supabase/.temp/postgres-version
npx supabase db start --from-backup /path/to/db_cluster.backup
```

The version must match the old project's Postgres build or the restore fails.
Verify the data arrived:

```bash
psql 'postgresql://postgres:postgres@localhost:54322/postgres' -c '\dt public.*'
```

### 2. Dump the restored database

Run these against the **local** instance, since the old project is unreachable:

```bash
LOCAL='postgresql://postgres:postgres@localhost:54322/postgres'
npx supabase db dump --db-url "$LOCAL" -f roles.sql  --role-only
npx supabase db dump --db-url "$LOCAL" -f schema.sql
npx supabase db dump --db-url "$LOCAL" -f data.sql --use-copy --data-only \
  -x "storage.buckets_vectors" -x "storage.vector_indexes"
```

`data.sql` has no schema filter, so it includes the `auth` schema — that is what
carries your existing users across. Every table here has a
`user_id -> auth.users(id)` foreign key, so the users must land before the rows,
which the ordering below handles.

### 3. Load it into the new project

Create the new project, reset its database password, and take the **Session
pooler** connection string from the **Connect** dialog.

```bash
psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname '<NEW_CONNECTION_STRING>'
```

`session_replication_role = replica` disables triggers during the load. That
matters a lot here: without it, `trg_transactions_balance` and
`trg_accounts_opening_balance` would fire on every inserted row and recompute
balances off already-correct data.

Known errors and their fixes, all from the Supabase guide:

| Error | Fix |
| --- | --- |
| permission denied on `ALTER ... OWNER TO "supabase_admin"` | comment those lines out of `schema.sql` |
| `GRANT "postgres" TO "cli_login_postgres"` fails | comment that line out of `roles.sql` |
| `cli_login_postgres` role conflicts | `DROP ROLE IF EXISTS cli_login_postgres;` |
| `object already exists` | expected, harmless |

### 4. Finish

Do the three items under *What does not come across*, then check in the app that
account balances match what you remember. If they drifted, the balance
recompute function can be re-run per account:

```sql
select public.recompute_account_balance(id) from public.accounts;
```

---

## Sources

- [Project pausing and the restore window](https://supabase.com/docs/guides/platform/free-project-pausing)
- [Time limits, and downloading a backup after the window](https://supabase.com/docs/guides/platform/upgrading#time-limits)
- [Restoring a downloaded backup locally](https://supabase.com/docs/guides/local-development/restoring-downloaded-backup)
- [Backup and restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
