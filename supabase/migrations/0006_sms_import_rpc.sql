-- Personal Finance — atomic SMS import
--
-- 0005 built the tables. This builds the one operation the importer cannot
-- express as a sequence of client calls.
--
-- Importing a message writes up to three rows: the transaction, the bank's fee
-- as its own transaction, and the sms_inbox row that marks the message dealt
-- with. Done from Dart that is three round trips, and every gap between them is
-- a state the books should never be in — a fee charged with nothing to explain
-- it, or a message marked imported whose transaction never arrived. A function
-- runs the whole thing inside one statement's transaction, so it either all
-- happens or none of it does.
--
-- Both functions are security invoker (the default), so RLS still applies and a
-- caller can only ever write its own rows. user_id is taken from auth.uid()
-- rather than trusted from the client.
--
-- Safe to run more than once. Run after 0005.

-- =========================================================================
-- Shared: insert one planned transaction, tolerating a re-import
-- =========================================================================
-- Returns the row's id whether this call created it or a previous sweep did.
-- The null-external_ref branch is unreachable from the importer — every planned
-- row carries a dedupe key — but a function that silently skipped the insert if
-- one were ever missing would be a bad way to find that out.
create or replace function public.sms_insert_planned_txn(p_txn jsonb)
returns uuid
language plpgsql
as $$
declare
  v_id  uuid;
  v_ref text := p_txn->>'external_ref';
begin
  if v_ref is null or length(trim(v_ref)) = 0 then
    raise exception 'sms_insert_planned_txn: external_ref is required';
  end if;

  insert into public.transactions (
    user_id, account_id, to_account_id, type, amount,
    category, description, date, source, external_ref
  )
  values (
    (select auth.uid()),
    (p_txn->>'account_id')::uuid,
    nullif(p_txn->>'to_account_id', '')::uuid,
    p_txn->>'type',
    (p_txn->>'amount')::numeric,
    p_txn->>'category',
    nullif(p_txn->>'description', ''),
    (p_txn->>'date')::date,
    'sms',
    v_ref
  )
  on conflict (user_id, external_ref) where external_ref is not null
    do nothing
  returning id into v_id;

  -- Conflict path: the row is already there from an earlier sweep. Return the
  -- existing id so the inbox row still gets pointed at its transaction.
  if v_id is null then
    select id into v_id
    from public.transactions
    where user_id = (select auth.uid()) and external_ref = v_ref;
  end if;

  return v_id;
end;
$$;

-- =========================================================================
-- Import: transaction (+ fee) + inbox row, all or nothing
-- =========================================================================
create or replace function public.sms_import_txn(
  p_sender      text,
  p_body        text,
  p_received_at timestamptz,
  p_dedupe_key  text,
  p_parsed      jsonb,
  p_txn         jsonb,
  p_fee         jsonb default null
)
returns uuid
language plpgsql
as $$
declare
  v_txn_id uuid;
begin
  v_txn_id := public.sms_insert_planned_txn(p_txn);

  -- The fee is a separate ledger row on purpose: folded into the amount, every
  -- merchant total would read a few cedis high forever.
  if p_fee is not null then
    perform public.sms_insert_planned_txn(p_fee);
  end if;

  insert into public.sms_inbox (
    user_id, sender, body, received_at, status, parsed, transaction_id, dedupe_key
  )
  values (
    (select auth.uid()), p_sender, p_body, p_received_at,
    'imported', p_parsed, v_txn_id, p_dedupe_key
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null
    do update set
      status         = 'imported',
      transaction_id = excluded.transaction_id,
      parsed         = excluded.parsed;

  return v_txn_id;
end;
$$;

-- =========================================================================
-- Review: fee (if any) + a pending inbox row
-- =========================================================================
-- The fee is written even though the transaction it belongs to is still
-- unresolved. A bank charge is unambiguous in a way its merchant is not —
-- holding it back would understate spending for as long as the queue sits
-- unread, which on a busy week is the whole week.
create or replace function public.sms_hold_for_review(
  p_sender      text,
  p_body        text,
  p_received_at timestamptz,
  p_dedupe_key  text,
  p_parsed      jsonb,
  p_fee         jsonb default null
)
returns void
language plpgsql
as $$
begin
  if p_fee is not null then
    perform public.sms_insert_planned_txn(p_fee);
  end if;

  insert into public.sms_inbox (
    user_id, sender, body, received_at, status, parsed, dedupe_key
  )
  values (
    (select auth.uid()), p_sender, p_body, p_received_at,
    'pending', p_parsed, p_dedupe_key
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null
    do nothing;
end;
$$;

-- =========================================================================
-- Resolve: turn a reviewed message into a transaction
-- =========================================================================
-- Called when the user answers the queue. Same all-or-nothing guarantee: the
-- inbox row flips to 'imported' only if the ledger row landed.
create or replace function public.sms_resolve_review(
  p_inbox_id uuid,
  p_txn      jsonb
)
returns uuid
language plpgsql
as $$
declare
  v_txn_id uuid;
begin
  v_txn_id := public.sms_insert_planned_txn(p_txn);

  update public.sms_inbox
  set status = 'imported', transaction_id = v_txn_id
  where id = p_inbox_id and user_id = (select auth.uid());

  if not found then
    raise exception 'sms_resolve_review: no such message';
  end if;

  return v_txn_id;
end;
$$;
