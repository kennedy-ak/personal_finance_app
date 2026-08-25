-- OPTIONAL, ONE-TIME. Back up your data before running this.
--
-- Converts historical faked transfers (an Expense + an Income row, both tagged
-- category 'Transfer', same user / date / amount) into single 'Transfer' rows.
--
-- You do not have to run this. The app already excludes legacy 'Transfer'
-- category rows from every spending figure, so your numbers are correct either
-- way. Running it just makes the history read honestly: one movement, one row.
--
-- Pairing is a heuristic. If you moved the same amount between two different
-- pairs of accounts on the same day, the pairing may cross them over — the
-- balances stay correct, but the from/to accounts on those two rows could swap.

begin;

with expenses as (
  select id, user_id, account_id, amount, date, description,
         row_number() over (partition by user_id, amount, date order by created_at) as rn
  from public.transactions
  where type = 'Expense' and category = 'Transfer' and to_account_id is null
),
incomes as (
  select id, user_id, account_id, amount, date,
         row_number() over (partition by user_id, amount, date order by created_at) as rn
  from public.transactions
  where type = 'Income' and category = 'Transfer' and to_account_id is null
),
paired as (
  select e.id as expense_id,
         i.id as income_id,
         i.account_id as to_account_id
  from expenses e
  join incomes i
    on  i.user_id = e.user_id
    and i.amount  = e.amount
    and i.date    = e.date
    and i.rn      = e.rn
    and i.account_id <> e.account_id
)
update public.transactions t
   set type = 'Transfer',
       to_account_id = p.to_account_id
  from paired p
 where t.id = p.expense_id;

-- Drop the now-redundant income halves.
with expenses as (
  select id, user_id, amount, date,
         row_number() over (partition by user_id, amount, date order by created_at) as rn
  from public.transactions
  where type = 'Transfer' and category = 'Transfer'
),
incomes as (
  select id, user_id, amount, date,
         row_number() over (partition by user_id, amount, date order by created_at) as rn
  from public.transactions
  where type = 'Income' and category = 'Transfer' and to_account_id is null
)
delete from public.transactions t
 using incomes i, expenses e
 where t.id = i.id
   and i.user_id = e.user_id
   and i.amount  = e.amount
   and i.date    = e.date
   and i.rn      = e.rn;

-- Balances are recomputed by the row triggers as these rows change, but settle
-- everything once more so nothing depends on trigger ordering.
do $$
declare r record;
begin
  for r in select id from public.accounts loop
    perform public.recompute_account_balance(r.id);
  end loop;
end $$;

commit;
