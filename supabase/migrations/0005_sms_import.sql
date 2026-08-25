-- Personal Finance — SMS import
--
-- Seven accounts, four of which announce every transaction by SMS. Typing those
-- in by hand is the single largest reason the ledger drifts out of date, so the
-- app reads them instead. Only cash stays manual — nothing texts you about cash.
--
-- Three things have to be true for that to be safe:
--
--   1. Importing the same message twice must be impossible, not merely
--      unlikely — hence transactions.external_ref and a unique index.
--   2. Money moving to IC Wealth or Black Star must land as a Transfer, never
--      as spending. Both are funded through MoMo, so their alerts are
--      indistinguishable from paying a shop until a rule says otherwise.
--   3. Nothing may be silently discarded. A message we cannot read is kept in
--      sms_inbox for review, because a parser that quietly drops transactions
--      looks exactly like a quiet month.
--
-- Safe to run more than once. Run after 0004.

-- =========================================================================
-- 1. Where a transaction came from
-- =========================================================================
alter table public.transactions
  add column if not exists source text not null default 'manual',
  -- The bank's own identifier for the movement, qualified by amount and time.
  -- Not the raw reference: Fidelity bills a transfer and its fee as two alerts
  -- sharing one session ID, and CBG's 'Ref' is just the masked account number,
  -- identical on every message it sends. See ParsedSms.dedupeKey.
  add column if not exists external_ref text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'transactions_source_check') then
    alter table public.transactions add constraint transactions_source_check
      check (source in ('manual','sms'));
  end if;
end $$;

-- The guarantee that makes re-scanning the inbox harmless. Partial, because
-- every hand-entered row leaves external_ref null and nulls must not collide.
create unique index if not exists transactions_external_ref_key
  on public.transactions (user_id, external_ref)
  where external_ref is not null;

-- =========================================================================
-- 2. Which account each sender speaks for
-- =========================================================================
create table if not exists public.sms_account_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  -- Matches BankSmsParser.id: 'fidelity', 'access', 'cbg', 'mtn_momo'.
  parser_id text not null,
  account_id uuid not null references public.accounts(id) on delete cascade,

  -- The user's own numbers as the banks write them: MoMo MSISDN, masked
  -- account numbers. Fidelity's narration for a wallet top-up names the
  -- destination MoMo number, and recognising it as the user's own is what
  -- turns a debit plus an unrelated credit into one transfer.
  identifiers text[] not null default '{}',

  created_at timestamptz not null default now(),
  unique (user_id, parser_id)
);

create index if not exists sms_account_links_account_idx
  on public.sms_account_links (account_id);

alter table public.sms_account_links enable row level security;

drop policy if exists "sms_account_links_owner_all" on public.sms_account_links;
create policy "sms_account_links_owner_all" on public.sms_account_links
  for all using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- =========================================================================
-- 3. What a counterparty means
-- =========================================================================
-- Learned once from the review queue, then applied silently forever. This is
-- what keeps the queue from becoming a second data-entry chore: after a few
-- weeks only genuinely new counterparties surface.
create table if not exists public.sms_routing_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  -- Restrict the rule to one sender, or leave null to match any.
  parser_id text,

  -- Counterparty text to look for, upper-cased and space-collapsed the same
  -- way ParsedSms.counterparty is, so 'INTERCITY STC COACHES  LIMITED' and the
  -- name typed normally are one rule rather than two.
  match_text text not null check (length(trim(match_text)) > 0),
  match_kind text not null default 'contains' check (match_kind in ('contains','exact')),

  txn_type text not null check (txn_type in ('Income','Expense','Transfer')),
  category text,

  -- The account at the *other* end of the movement, set only for transfers.
  -- One rule serves both directions: on a debit the money leaves the sender's
  -- account and lands here, on a credit it travels the other way. That is what
  -- makes redeeming an investment income-neutral instead of a fake payday.
  counterpart_account_id uuid references public.accounts(id) on delete cascade,

  -- Higher wins, so a specific merchant can override a broad rule.
  priority integer not null default 0,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sms_routing_rules_shape_check') then
    alter table public.sms_routing_rules add constraint sms_routing_rules_shape_check
      check (
        (txn_type = 'Transfer' and counterpart_account_id is not null and category is null)
        or
        (txn_type <> 'Transfer' and counterpart_account_id is null and category is not null)
      );
  end if;
end $$;

create index if not exists sms_routing_rules_user_idx
  on public.sms_routing_rules (user_id, priority desc);

create index if not exists sms_routing_rules_counterpart_idx
  on public.sms_routing_rules (counterpart_account_id)
  where counterpart_account_id is not null;

alter table public.sms_routing_rules enable row level security;

drop policy if exists "sms_routing_rules_owner_all" on public.sms_routing_rules;
create policy "sms_routing_rules_owner_all" on public.sms_routing_rules
  for all using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- =========================================================================
-- 4. The review queue
-- =========================================================================
-- Every message the app has seen, whether or not it became a transaction.
-- Keeping the body means a parser fixed next month can re-read what this
-- month's parser could not.
create table if not exists public.sms_inbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  sender text not null,
  body text not null,
  received_at timestamptz not null,

  -- 'pending'  — read successfully, waiting for a category or a confirmation
  -- 'imported' — became transaction_id
  -- 'ignored'  — deliberately not money, e.g. an OTP or a promo
  -- 'unparsed' — from a known sender in a shape we do not understand yet
  status text not null default 'pending'
    check (status in ('pending','imported','ignored','unparsed')),

  -- What the parser made of it. Null while unparsed.
  parsed jsonb,

  transaction_id uuid references public.transactions(id) on delete set null,

  -- Null while unparsed: a message we cannot read has no amount or reference
  -- to build a key from, and must not block a later one that shares its text.
  dedupe_key text,

  created_at timestamptz not null default now()
);

create unique index if not exists sms_inbox_dedupe_key
  on public.sms_inbox (user_id, dedupe_key)
  where dedupe_key is not null;

create index if not exists sms_inbox_user_status_idx
  on public.sms_inbox (user_id, status, received_at desc);

create index if not exists sms_inbox_transaction_idx
  on public.sms_inbox (transaction_id)
  where transaction_id is not null;

alter table public.sms_inbox enable row level security;

drop policy if exists "sms_inbox_owner_all" on public.sms_inbox;
create policy "sms_inbox_owner_all" on public.sms_inbox
  for all using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
