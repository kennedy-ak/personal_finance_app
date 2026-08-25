-- Personal Finance — Money foundation
--
-- Gives the app enough structure to answer questions it previously could not:
--   "how much of this is actually spendable?"i  -> accounts.liquidity + min_balance
--   "what is already committed?"               -> obligations
--   "where should I pay this from?"            -> account metadata + obligations
--   "move money from here to there"            -> transactions.type = 'Transfer'
--
-- Safe to run more than once. Run after 0001 (schema.sql).

-- =========================================================================
-- 1. Account metadata
-- =========================================================================
alter table public.accounts
  add column if not exists kind text not null default 'bank',
  add column if not exists liquidity text not null default 'liquid',
  add column if not exists min_balance numeric(12,2) not null default 0,
  add column if not exists purpose text,
  add column if not exists is_archived boolean not null default false,
  add column if not exists sort_order integer not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'accounts_kind_check') then
    alter table public.accounts add constraint accounts_kind_check
      check (kind in ('bank','momo','cash','savings','investment','credit'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'accounts_liquidity_check') then
    alter table public.accounts add constraint accounts_liquidity_check
      check (liquidity in ('liquid','reserved','locked'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'accounts_min_balance_check') then
    alter table public.accounts add constraint accounts_min_balance_check
      check (min_balance >= 0);
  end if;
end $$;

-- Opening balance, added separately so we can backfill it exactly once.
--
-- Why this matters: recompute_account_balance() overwrites accounts.balance with
-- the sum of transactions. Any balance a user typed in by hand (a starting
-- balance, or a manual correction) was silently erased the next time a
-- transaction on that account changed. Storing it explicitly makes the recompute
-- lossless.
do $$
declare
  v_fresh boolean;
begin
  v_fresh := not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name  = 'accounts'
      and column_name = 'opening_balance'
  );

  if v_fresh then
    alter table public.accounts
      add column opening_balance numeric(12,2) not null default 0;

    -- Preserve every currently displayed balance: whatever the balance is now
    -- that transactions do not explain becomes the opening balance.
    update public.accounts a
       set opening_balance = a.balance - coalesce((
             select sum(case when t.type = 'Income' then t.amount else -t.amount end)
             from public.transactions t
             where t.account_id = a.id
           ), 0);
  end if;
end $$;

-- =========================================================================
-- 2. Transfers as a first-class transaction type
-- =========================================================================
-- Previously a transfer was faked as an Expense on the source plus an Income on
-- the destination, both tagged category 'Transfer'. That double-counted into
-- every income/expense figure in the app and showed up in the spending pie as
-- if moving your own money were a purchase.
alter table public.transactions
  add column if not exists to_account_id uuid references public.accounts(id) on delete cascade;

alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check
  check (type in ('Income','Expense','Transfer'));

alter table public.transactions drop constraint if exists transactions_transfer_shape_check;
alter table public.transactions add constraint transactions_transfer_shape_check
  check (
    (type = 'Transfer' and to_account_id is not null and to_account_id <> account_id)
    or
    (type <> 'Transfer' and to_account_id is null)
  );

create index if not exists transactions_to_account_idx
  on public.transactions (to_account_id) where to_account_id is not null;

-- =========================================================================
-- 3. Obligations — money that is already spoken for, and money due to arrive
-- =========================================================================
create table if not exists public.obligations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  direction text not null default 'out' check (direction in ('out','in')),
  amount numeric(12,2) not null check (amount > 0),
  cadence text not null default 'monthly'
    check (cadence in ('once','weekly','biweekly','monthly','quarterly','yearly')),
  -- Anchor date: the next (or only) time this lands. Recurrence rolls forward
  -- from here in the app, so a single column covers every cadence.
  next_due date not null,
  account_id uuid references public.accounts(id) on delete set null,
  category text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists obligations_user_due_idx
  on public.obligations (user_id, next_due);

alter table public.obligations enable row level security;

drop policy if exists "obligations_owner_all" on public.obligations;
create policy "obligations_owner_all" on public.obligations
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =========================================================================
-- 4. Goals — money that exists but must not be treated as spendable
-- =========================================================================
create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  target_amount numeric(12,2) not null check (target_amount > 0),
  saved_amount numeric(12,2) not null default 0 check (saved_amount >= 0),
  target_date date,
  account_id uuid references public.accounts(id) on delete set null,
  priority integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists goals_user_idx on public.goals (user_id, priority);

alter table public.goals enable row level security;

drop policy if exists "goals_owner_all" on public.goals;
create policy "goals_owner_all" on public.goals
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =========================================================================
-- 5. Balance maintenance, corrected
-- =========================================================================
-- balance = opening_balance
--         + income
--         - expense
--         - transfers sent from this account
--         + transfers received into this account
create or replace function public.recompute_account_balance(p_account uuid)
returns void
language plpgsql
as $$
begin
  update public.accounts a
     set balance = a.opening_balance
       + coalesce((
           select sum(case
                        when t.type = 'Income'   then  t.amount
                        when t.type = 'Expense'  then -t.amount
                        when t.type = 'Transfer' then -t.amount
                      end)
           from public.transactions t
           where t.account_id = a.id
         ), 0)
       + coalesce((
           select sum(t.amount)
           from public.transactions t
           where t.to_account_id = a.id and t.type = 'Transfer'
         ), 0)
   where a.id = p_account;
end;
$$;

-- Recompute every account touched by the row, on both sides of a transfer.
create or replace function public.transactions_balance_trigger()
returns trigger
language plpgsql
as $$
begin
  if (tg_op in ('INSERT','UPDATE')) then
    perform public.recompute_account_balance(new.account_id);
    if new.to_account_id is not null then
      perform public.recompute_account_balance(new.to_account_id);
    end if;
  end if;

  if (tg_op in ('UPDATE','DELETE')) then
    perform public.recompute_account_balance(old.account_id);
    if old.to_account_id is not null then
      perform public.recompute_account_balance(old.to_account_id);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_transactions_balance on public.transactions;
create trigger trg_transactions_balance
  after insert or update or delete on public.transactions
  for each row execute function public.transactions_balance_trigger();

-- Editing opening_balance or creating an account must also settle the balance.
create or replace function public.accounts_opening_balance_trigger()
returns trigger
language plpgsql
as $$
begin
  perform public.recompute_account_balance(new.id);
  return null;
end;
$$;

drop trigger if exists trg_accounts_opening_balance on public.accounts;
create trigger trg_accounts_opening_balance
  after update of opening_balance on public.accounts
  for each row
  when (new.opening_balance is distinct from old.opening_balance)
  execute function public.accounts_opening_balance_trigger();

-- =========================================================================
-- 6. Sensible defaults for the accounts created at signup
-- =========================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.accounts (user_id, name, balance, kind, liquidity, sort_order) values
    (new.id, 'Fidelity Account', 0, 'bank',    'liquid', 0),
    (new.id, 'Access Account',   0, 'bank',    'liquid', 1),
    (new.id, 'Mobile Money',     0, 'momo',    'liquid', 2),
    (new.id, 'Cash',             0, 'cash',    'liquid', 3);
  return new;
end;
$$;

-- Settle every existing account once, so balances reflect the corrected formula.
do $$
declare r record;
begin
  for r in select id from public.accounts loop
    perform public.recompute_account_balance(r.id);
  end loop;
end $$;
