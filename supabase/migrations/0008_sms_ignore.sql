-- Personal Finance — ignoring non-money messages
--
-- 0005 keeps every message from a linked sender, by design: a parser that
-- quietly drops transactions looks exactly like a quiet month. But a linked
-- sender also texts OTPs, promos and bundle notices, and those must not pile
-- up in the review queue — they are money-adjacent at best, and the queue is
-- only useful while everything in it deserves a human's answer.
--
-- The Dart parser classifies those messages as 'not money' before any
-- transaction is considered. This gives that classification the same
-- all-or-nothing write path the importer and the review queue have, so
-- re-scanning the inbox stays idempotent for them too.
--
-- Safe to run more than once. Run after 0006.

create or replace function public.sms_ignore_message(
  p_sender      text,
  p_body        text,
  p_received_at timestamptz,
  p_dedupe_key  text
)
returns void
language plpgsql
as $$
begin
  insert into public.sms_inbox (
    user_id, sender, body, received_at, status, dedupe_key
  )
  values (
    (select auth.uid()), p_sender, p_body, p_received_at,
    'ignored', p_dedupe_key
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null
  do nothing;
end;
$$;
