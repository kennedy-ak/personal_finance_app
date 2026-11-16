-- Personal Finance — make 0009's revokes actually bite
--
-- 0009 ran `revoke execute ... from anon` and reported success, but the anon
-- role could still call every one of those functions afterwards.
--
-- The reason is a PostgreSQL default that is easy to miss: on creation, a
-- function is granted EXECUTE to PUBLIC — the pseudo-role every other role
-- inherits from. Revoking the privilege from `anon` removes a grant `anon`
-- never had directly, and leaves it reaching the function through PUBLIC. The
-- revoke has to name PUBLIC, and then the roles that *should* keep the function
-- need it granted back explicitly.
--
-- Checked with has_function_privilege('anon', oid, 'EXECUTE') rather than by
-- reading the migration back, which is what caught this in the first place.
--
-- Safe to run more than once. Run after 0009.

-- =========================================================================
-- Functions the app calls as a signed-in user
-- =========================================================================
-- authenticated keeps these; anon loses them. seed_default_categories is the
-- one that mattered: its `auth.uid() is not null and p_user <> auth.uid()`
-- guard passes for an unauthenticated caller, so reaching it without a session
-- let category rows be written for any user id (see 0009 for the full reading).
revoke execute on function public.seed_default_categories(uuid) from public, anon;
grant  execute on function public.seed_default_categories(uuid) to authenticated;

revoke execute on function public.rename_category(uuid, text) from public, anon;
grant  execute on function public.rename_category(uuid, text) to authenticated;

revoke execute on function public.category_usage_count(uuid) from public, anon;
grant  execute on function public.category_usage_count(uuid) to authenticated;

-- =========================================================================
-- The signup trigger function
-- =========================================================================
-- Nothing should reach this through the API, so no API role keeps it.
--
-- supabase_auth_admin is granted it explicitly, which is the belt to the
-- braces: GoTrue connects as that role to insert into auth.users, and until now
-- it held EXECUTE only by way of the PUBLIC grant this statement removes.
-- PostgreSQL checks EXECUTE on a trigger function when the trigger is created
-- rather than each time it fires, so in principle the revoke alone is harmless
-- — but "in principle" is a poor thing to rest signup on, and an explicit grant
-- costs nothing. postgres keeps access as the function's owner.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant  execute on function public.handle_new_user() to supabase_auth_admin;
