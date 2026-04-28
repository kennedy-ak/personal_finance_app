-- Personal Finance — Supabase schema
-- Run this in the Supabase SQL editor for a fresh project.

-- =========================
-- Tables
-- =========================
create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists public.ai_chats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question text not null,
  answer text not null,
  created_at timestamptz not null default now()
);

create index if not exists ai_chats_user_created_idx
  on public.ai_chats (user_id, created_at desc);

alter table public.ai_chats enable row level security;

drop policy if exists "ai_chats_owner_all" on public.ai_chats;
create policy "ai_chats_owner_all" on public.ai_chats
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  type text not null check (type in ('Income','Expense')),
  amount numeric(12,2) not null check (amount > 0),
  category text not null,
  description text,
  date date not null,
  created_at timestamptz not null default now()
);

create index if not exists transactions_user_date_idx
  on public.transactions (user_id, date desc);

create index if not exists transactions_account_idx
  on public.transactions (account_id);

-- =========================
-- Row Level Security
-- =========================
alter table public.accounts enable row level security;
alter table public.transactions enable row level security;

drop policy if exists "accounts_owner_all" on public.accounts;
create policy "accounts_owner_all" on public.accounts
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "transactions_owner_all" on public.transactions;
create policy "transactions_owner_all" on public.transactions
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =========================
-- Default accounts on signup
-- =========================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.accounts (user_id, name, balance) values
    (new.id, 'Fidelity Account', 0),
    (new.id, 'Access Account',   0),
    (new.id, 'Mobile Money',     0),
    (new.id, 'Cash',             0);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================
-- Balance maintenance
-- Recompute affected account balances after txn changes.
-- =========================
create or replace function public.recompute_account_balance(p_account uuid)
returns void
language plpgsql
as $$
begin
  update public.accounts a
     set balance = coalesce((
       select sum(case when t.type = 'Income' then t.amount else -t.amount end)
       from public.transactions t
       where t.account_id = a.id
     ), 0)
   where a.id = p_account;
end;
$$;

create or replace function public.transactions_balance_trigger()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT') then
    perform public.recompute_account_balance(new.account_id);
  elsif (tg_op = 'UPDATE') then
    perform public.recompute_account_balance(new.account_id);
    if new.account_id <> old.account_id then
      perform public.recompute_account_balance(old.account_id);
    end if;
  elsif (tg_op = 'DELETE') then
    perform public.recompute_account_balance(old.account_id);
  end if;
  return null;
end;
$$;

drop trigger if exists trg_transactions_balance on public.transactions;
create trigger trg_transactions_balance
  after insert or update or delete on public.transactions
  for each row execute function public.transactions_balance_trigger();
