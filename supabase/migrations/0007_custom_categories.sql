-- Personal Finance — categories the user owns
--
-- The built-in list was a guess, and a guess that does not match how someone
-- actually spends is worse than no list at all: every mismatched transaction
-- ends up under 'Other', and 'Other' explains nothing.
--
-- So categories become rows instead of a constant. Every user gets the old list
-- seeded as ordinary rows they may rename, hide or delete, and may add their
-- own alongside. transactions.category stays free text — nothing here is a
-- foreign key — so hiding or deleting a category never rewrites history or
-- breaks a report. It only decides what the pickers offer next time.
--
-- Safe to run more than once. Run after 0006.

-- =========================================================================
-- 1. The table
-- =========================================================================
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  -- Matches transactions.category verbatim. Renaming here does not touch
  -- existing rows; see rename_category below for the one that does.
  name text not null,

  kind text not null check (kind in ('expense','income')),

  -- A key into kPickableIcons on the client, not a codepoint. Storing the
  -- codepoint would break the moment Material renumbers an icon, and would
  -- also defeat tree-shaking of icon fonts.
  icon text,

  -- Hidden, not deleted: the label a hundred old transactions carry should
  -- stop being offered without disappearing from the ledger.
  is_hidden boolean not null default false,

  -- True for the seeded defaults. Only used to explain them in the UI.
  is_builtin boolean not null default false,

  sort_order int not null default 0,
  created_at timestamptz not null default now(),

  unique (user_id, kind, name)
);

create index if not exists categories_user_kind_idx
  on public.categories (user_id, kind, sort_order);

alter table public.categories enable row level security;

drop policy if exists "categories_owner_all" on public.categories;
create policy "categories_owner_all" on public.categories
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =========================================================================
-- 2. Seeding the old constants as rows
-- =========================================================================
create or replace function public.seed_default_categories(p_user uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  -- Security definer, so the argument has to be checked rather than trusted:
  -- without this any signed-in user could seed rows into someone else's list.
  -- auth.uid() is null when the signup trigger calls this, which is the one
  -- legitimate case for seeding a user other than yourself.
  if auth.uid() is not null and p_user <> auth.uid() then
    raise exception 'Not your account';
  end if;

  insert into public.categories (user_id, name, kind, icon, is_builtin, sort_order)
  select p_user, d.name, d.kind, d.icon, true, d.ord
  from (values
    ('Food & Dining',      'expense', 'restaurant',  0),
    ('Transportation',     'expense', 'bus',         1),
    ('Shopping',           'expense', 'shopping',    2),
    ('Entertainment',      'expense', 'movie',       3),
    ('Bills & Utilities',  'expense', 'bolt',        4),
    ('Healthcare',         'expense', 'medical',     5),
    ('Education',          'expense', 'school',      6),
    ('Travel',             'expense', 'flight',      7),
    ('Housing',            'expense', 'home',        8),
    ('Insurance',          'expense', 'shield',      9),
    ('Gifts & Donations',  'expense', 'gift',       10),
    ('Bank Charges',       'expense', 'receipt',    11),
    ('Other',              'expense', 'category',   12),
    ('Salary',             'income',  'work',        0),
    ('Business',           'income',  'business',    1),
    ('Investment',         'income',  'trending_up', 2),
    ('Gift',               'income',  'gift',        3),
    ('Refund',             'income',  'replay',      4),
    ('Other',              'income',  'category',    5)
  ) as d(name, kind, icon, ord)
  on conflict (user_id, kind, name) do nothing;
end;
$$;

-- Existing users get the same list, once.
do $$
declare r record;
begin
  for r in select id from auth.users loop
    perform public.seed_default_categories(r.id);
  end loop;
end $$;

-- New users get it at signup, alongside their starter accounts.
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
  perform public.seed_default_categories(new.id);
  return new;
end;
$$;

-- =========================================================================
-- 3. Renaming a category the user has already used
-- =========================================================================
-- Two writes that must not half-happen: the label on the category and the
-- label on every transaction wearing it. Done client-side that is two round
-- trips with a window where reports show both spellings as separate lines.
create or replace function public.rename_category(
  p_id uuid,
  p_new_name text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_old  text;
  v_kind text;
begin
  select name, kind into v_old, v_kind
  from public.categories
  where id = p_id and user_id = auth.uid();

  if v_old is null then
    raise exception 'Category not found';
  end if;
  if v_old = p_new_name then
    return;
  end if;

  update public.categories set name = p_new_name where id = p_id;

  -- Only rows of the matching direction: an expense 'Other' and an income
  -- 'Other' are different categories that happen to share a label.
  update public.transactions
     set category = p_new_name
   where user_id = auth.uid()
     and category = v_old
     and type = (case when v_kind = 'income' then 'Income' else 'Expense' end);
end;
$$;

-- How many transactions a category is holding, so the UI can warn before a
-- delete instead of after.
create or replace function public.category_usage_count(p_id uuid)
returns integer
language sql
security definer set search_path = public
as $$
  select count(*)::int
  from public.transactions t
  join public.categories c
    on c.id = p_id
   and c.user_id = auth.uid()
  where t.user_id = auth.uid()
    and t.category = c.name
    and t.type = (case when c.kind = 'income' then 'Income' else 'Expense' end);
$$;

grant execute on function public.seed_default_categories(uuid) to authenticated;
grant execute on function public.rename_category(uuid, text)   to authenticated;
grant execute on function public.category_usage_count(uuid)    to authenticated;
