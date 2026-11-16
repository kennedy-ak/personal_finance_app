-- Personal Finance — close two gaps the Supabase linter found
--
-- Neither is a new bug. Both have been true since the functions were written;
-- they only became visible when the schema was stood up on a fresh project and
-- the security advisor was run against it.
--
-- INCOMPLETE ON ITS OWN — see 0010. The search_path half of this migration
-- worked. The revokes in section 1 did not: PostgreSQL grants EXECUTE to the
-- PUBLIC pseudo-role when a function is created, and `revoke ... from anon`
-- leaves that grant in place, so anon kept reaching every function through it.
-- 0010 revokes from PUBLIC and grants back explicitly. This file is kept as
-- applied rather than rewritten, so the repo and the deployed history match.
--
-- Safe to run more than once. Run after 0008.

-- =========================================================================
-- 1. seed_default_categories must not be callable by anon
-- =========================================================================
-- The function is `security definer`, so it writes with the owner's rights, and
-- it guards its argument with:
--
--     if auth.uid() is not null and p_user <> auth.uid() then raise ...
--
-- For a signed-in caller that is exactly right. For an unauthenticated one it
-- is not: auth.uid() is null, the left side of the `and` is false, the whole
-- condition is false, and the guard waves the call through. Since PostgREST
-- exposes every function in `public` as an endpoint, anyone holding the anon
-- key could POST /rest/v1/rpc/seed_default_categories with any user id and
-- seed category rows into that person's list.
--
-- The null case is reachable on purpose — the signup trigger calls this with
-- auth.uid() still null, which is the one legitimate reason to seed somebody
-- other than yourself. So the guard stays as it is and the fix is to take the
-- endpoint away from anon instead. `authenticated` keeps it: the app calls this
-- from CategoryRepository to re-seed a user's own defaults.
revoke execute on function public.seed_default_categories(uuid) from anon;

-- Same treatment for the other two the app calls as a signed-in user. Their
-- own guards are sound (both filter on `user_id = auth.uid()`, which matches
-- nothing when auth.uid() is null), so this is defence in depth rather than a
-- hole being closed.
revoke execute on function public.rename_category(uuid, text)   from anon;
revoke execute on function public.category_usage_count(uuid)    from anon;

-- handle_new_user is a trigger function and nothing should ever reach it
-- through the API. Calling it directly fails anyway — PostgreSQL refuses to run
-- a trigger function outside a trigger — but an endpoint that exists only to
-- return an error is still an endpoint. Revoking EXECUTE does not stop the
-- trigger firing: PostgreSQL checks EXECUTE when the trigger is created, not
-- each time it fires, and the insert into auth.users is made by
-- supabase_auth_admin regardless.
revoke execute on function public.handle_new_user() from anon, authenticated;

-- =========================================================================
-- 2. Pin search_path on the functions that lack it
-- =========================================================================
-- These nine are `security invoker`, so they carry less risk than a definer
-- function would — but an unpinned search_path still means the objects a body
-- resolves to depend on whoever is calling it. Every body here already
-- schema-qualifies what it touches (public.*, auth.uid()), so pinning changes
-- no behaviour; it just stops that being true only by accident.
--
-- ALTER rather than CREATE OR REPLACE on purpose: the bodies are correct and
-- restating them here would leave two copies of each to keep in step.
alter function public.recompute_account_balance(uuid)
  set search_path = public, pg_temp;

alter function public.transactions_balance_trigger()
  set search_path = public, pg_temp;

alter function public.accounts_opening_balance_trigger()
  set search_path = public, pg_temp;

alter function public.touch_ai_thread()
  set search_path = public, pg_temp;

alter function public.sms_insert_planned_txn(jsonb)
  set search_path = public, pg_temp;

alter function public.sms_import_txn(text, text, timestamptz, text, jsonb, jsonb, jsonb)
  set search_path = public, pg_temp;

alter function public.sms_hold_for_review(text, text, timestamptz, text, jsonb, jsonb)
  set search_path = public, pg_temp;

alter function public.sms_resolve_review(uuid, jsonb)
  set search_path = public, pg_temp;

alter function public.sms_ignore_message(text, text, timestamptz, text)
  set search_path = public, pg_temp;
