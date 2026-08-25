-- Personal Finance — Coach memory
--
-- The old coach sent one question with no history, so every message started
-- from nothing. These tables give a conversation a past: what was asked, what
-- the coach looked up, and what it offered to do.
--
-- Safe to run more than once. Run after 0002.

create table if not exists public.ai_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ai_threads_user_updated_idx
  on public.ai_threads (user_id, updated_at desc);

alter table public.ai_threads enable row level security;

drop policy if exists "ai_threads_owner_all" on public.ai_threads;
create policy "ai_threads_owner_all" on public.ai_threads
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.ai_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  -- 'user'      — what the person typed
  -- 'assistant' — what the coach said, and/or the tools it asked to run
  -- 'tool'      — the result handed back to the coach
  role text not null check (role in ('user','assistant','tool')),

  -- Null on an assistant turn that only requested tools.
  content text,

  -- Tools the assistant asked for, in provider shape, so the thread can be
  -- replayed verbatim on the next request.
  tool_calls jsonb,

  -- Set on 'tool' rows: which request this answers, and which tool ran.
  tool_call_id text,
  name text,

  -- Actions offered to the user on this turn. Nothing here has happened —
  -- these are proposals awaiting a tap.
  actions jsonb,

  created_at timestamptz not null default now()
);

create index if not exists ai_messages_thread_idx
  on public.ai_messages (thread_id, created_at);

alter table public.ai_messages enable row level security;

drop policy if exists "ai_messages_owner_all" on public.ai_messages;
create policy "ai_messages_owner_all" on public.ai_messages
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Keep threads ordered by real activity, not creation.
create or replace function public.touch_ai_thread()
returns trigger
language plpgsql
as $$
begin
  update public.ai_threads
     set updated_at = now()
   where id = new.thread_id;
  return null;
end;
$$;

drop trigger if exists trg_ai_messages_touch on public.ai_messages;
create trigger trg_ai_messages_touch
  after insert on public.ai_messages
  for each row execute function public.touch_ai_thread();
