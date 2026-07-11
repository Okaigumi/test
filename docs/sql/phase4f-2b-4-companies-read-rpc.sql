-- ============================================================
-- Phase 4-F-2B-4: add a management-session-verified read RPC for public.companies
--   (list_companies_secure) so that admin-app.html can stop reading the companies
--   table directly.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-11)
--   - This file ONLY adds a new read RPC (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - Run MANUALLY by the user in the Supabase SQL Editor, one statement at a time.
--   - Execution results (Supabase SQL Editor):
--       * CREATE OR REPLACE FUNCTION ............ Success. No rows returned
--       * REVOKE ALL ... FROM PUBLIC ............ Success. No rows returned
--       * GRANT EXECUTE ... TO anon, authenticated  Success. No rows returned
--   - Pre-check  C-1..C-8 : all passed.
--   - Post-check P-1..P-5 : all passed.
--   - Screen smoke test: NOT performed at this stage -- the front-end has not been
--     migrated yet, so admin-app.html still uses the direct SELECT and
--     list_companies_secure is not yet called by any screen.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) were performed
--     manually by the user in the Supabase SQL Editor.
--   - The pre-check results recorded below (C-1..C-8) reflect the user's Supabase
--     SQL Editor run; the queries are kept re-runnable.
--
-- [PURPOSE]
--   admin-app.html currently reads public.companies via a direct SELECT
--   (`sb.from('companies').select('*').eq('is_active', true).order('name')`,
--    admin-app.html:333) to populate a company dropdown and to resolve
--    company_id -> company name for display.
--   This step adds a SECURITY DEFINER read RPC, list_companies_secure(text), that
--   returns only the columns the front-end actually uses (id, name) after verifying
--   a management session. This is the first of the standard 3-stage migration
--   (read RPC -> front-end move -> direct SELECT REVOKE), matching Phase 4-D.
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration (admin-app.html -> use sb.rpc('list_companies_secure')),
--     - REVOKE SELECT ON public.companies FROM anon, authenticated,
--     - DROP POLICY companies_select_public (which becomes stale only AFTER the
--       SELECT grant is revoked).
--
--   Only id and name are returned because those are the only companies columns the
--   front-end reads (verified read-only against admin-app.html):
--     - c.id   : dropdown <option> value + `_companies.find(c => c.id === id)`
--                (companyOptions admin-app.html:279 / companyName :283).
--     - c.name : dropdown display text + name resolution
--                (admin-app.html:279 / :284).
--   short_name / category_id / created_at are NOT referenced anywhere in
--   admin-app.html. is_active is used ONLY as a fetch filter (admin-app.html:333),
--   never read off the row object; it is reproduced server-side as WHERE is_active
--   = true. See NON-SCOPE below.
--
-- [SCOPE]
--   Add ONE function: public.list_companies_secure(session_token_input text).
--   Set EXECUTE privileges on that NEW function only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - admin-app.html / index.html / genka-app.html (front-end migration is a later step).
--   - public.companies table grant (anon / authenticated SELECT stays as-is).
--   - companies_select_public policy (LEFT IN PLACE; no DROP POLICY).
--   - RLS / FORCE RLS on companies.
--   - companies data.
--   - existing routines (the 7 companies-referencing routines; _verify_management_session).
--   - EXECUTE grants on any existing function.
--   - any other table / role / privilege.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - C-1: companies missing, not an ordinary table, RLS not enabled, or owner not
--          postgres (unexpected) -> STOP.
--   - C-3: companies has an id / name / is_active column mismatch -> STOP (return-type
--          / filter assumptions broken).
--   - C-6: _verify_management_session(text) is missing, is not SECURITY DEFINER, is
--          not owned by postgres, lacks the fixed search_path, or is EXECUTE-able by
--          anon / authenticated directly -> STOP (authz helper assumptions broken).
--   - C-8: public.list_companies_secure(text) already exists -> STOP and reconcile
--          (this file uses CREATE OR REPLACE, but an unexpected pre-existing function
--          means the environment differs from the recorded state).
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   The commented DROP FUNCTION removes exactly the function this file adds. Because
--   this file is additive and touches no grant / policy / table, dropping the new
--   function fully reverses this step (front-end has not yet been migrated at this
--   stage, so nothing depends on it).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Recorded results below reflect the user's Supabase SQL Editor run prior to this
--   file. The queries are re-runnable to re-confirm before executing the body.
-- ============================================================

-- C-1. companies existence + relkind + RLS state + owner.
--    Recorded: table exists, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres.
--    STOP if the table is missing, relkind <> 'r', rls_enabled <> true, or owner is
--    not postgres.
select
  n.nspname             as schema_name,
  c.relname             as table_name,
  c.relkind             as relkind,          -- expected 'r'
  c.relrowsecurity      as rls_enabled,      -- expected true
  c.relforcerowsecurity as rls_forced,       -- expected false
  pg_get_userbyid(c.relowner) as owner       -- expected postgres
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'companies';

-- C-2. anon / authenticated effective SELECT on companies (context; unchanged here).
--    Recorded: SELECT = true for both. This file does NOT change this.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. companies columns id / name / is_active exist with expected types.
--    Recorded: id uuid, name text, is_active boolean all present
--      (companies also has short_name text, created_at timestamptz, category_id uuid,
--       none of which are returned by the RPC).
--    STOP if id / name / is_active are missing or types differ from the RETURNS TABLE
--    / WHERE assumptions.
select
  a.attname     as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type
from pg_attribute a
where a.attrelid = 'public.companies'::regclass
  and a.attnum > 0
  and not a.attisdropped
  and a.attname in ('id', 'name', 'is_active')
order by a.attname;

-- C-4. companies pg_policies (context; unchanged here).
--    Recorded: exactly 1 policy -- companies_select_public
--      (roles = {anon, authenticated}, cmd = SELECT, qual = (is_active = true),
--       with_check = null).
--    This file does NOT drop or alter it.
select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'companies'
order by cmd, policyname;

-- C-6. _verify_management_session(text): existence + SECURITY DEFINER + owner +
--    fixed search_path + NOT EXECUTE-able by anon / authenticated.
--    Recorded: exists, prosecdef = true, owner = postgres,
--      proconfig contains search_path=public, extensions,
--      anon / authenticated EXECUTE = false (internal-only helper).
--    STOP if missing, prosecdef <> true, owner <> postgres, search_path not fixed,
--    or anon / authenticated can EXECUTE it directly.
select
  p.oid::regprocedure::text            as function_signature,
  p.prosecdef                          as is_security_definer,
  pg_get_userbyid(p.proowner)          as owner,
  p.proconfig                          as config,             -- expect search_path=public, extensions
  has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text';

-- C-8. list_companies_secure(text) does NOT already exist.
--    Recorded: 0 rows (not yet created).
--    STOP if a row is returned (unexpected pre-existing function; reconcile first).
select
  p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_companies_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text';


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (C-1..C-8) are re-confirmed with no STOP condition hit.
--   NOTE: additive only -- one CREATE OR REPLACE FUNCTION + REVOKE/GRANT of EXECUTE
--         on that NEW function. No table grant, no RLS, no policy, no existing
--         routine is touched.
--   NOTE: owner follows repo standard -- run this in the Supabase SQL Editor as
--         postgres (the existing *_secure functions are owned by postgres); no
--         explicit ALTER FUNCTION ... OWNER TO is issued, matching the other
--         docs/sql secure-RPC files.
-- ============================================================

-- list_companies_secure
--   Verify a management session (admin_sessions OR employee_sessions role=admin;
--   invalid / expired raises inside the helper), then return active companies as
--   (id, name) ordered by name. Behaviour is equivalent to the current direct SELECT
--   `select('*').eq('is_active', true).order('name')` for the columns the front-end
--   uses (id, name).
CREATE OR REPLACE FUNCTION public.list_companies_secure(
  session_token_input text
)
RETURNS TABLE (
  id   uuid,
  name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Authorization (invalid / expired session raises inside the helper).
  -- Return value is not needed here, so PERFORM.
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT c.id, c.name
    FROM   public.companies c
    WHERE  c.is_active = true
    ORDER  BY c.name;
END;
$$;

-- EXECUTE privileges on this NEW function only (repo standard for the dual-session
-- *_secure RPCs: PUBLIC revoked, granted to anon / authenticated only).
REVOKE ALL     ON FUNCTION public.list_companies_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_companies_secure(text) TO anon, authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. list_companies_secure(text) exists exactly once, with the expected
--    attributes: SECURITY DEFINER, STABLE (provolatile = 's'), owner postgres,
--    fixed search_path.
--    Expected: 1 row, is_security_definer = true, volatility = 's', owner = postgres,
--      config contains search_path=public, extensions.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  p.provolatile               as volatility,        -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,             -- expect postgres
  p.proconfig                 as config             -- expect search_path=public, extensions
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_companies_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text';

-- P-2. Return type is TABLE (id uuid, name text).
--    Expected: 2 rows -- (id, uuid), (name, text) -- as OUT/TABLE columns.
select
  p.proname,
  t.ord      as arg_position,
  t.argname  as out_column,
  format_type(t.argtype, null) as out_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
  with ordinality as t(argtype, argmode, argname, ord)
where n.nspname = 'public'
  and p.proname = 'list_companies_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text'
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by t.ord;

-- P-3. EXECUTE privileges: PUBLIC = false, anon = true, authenticated = true.
--    Expected: anon = true, authenticated = true, and PUBLIC has no EXECUTE.
select
  v.grantee,
  has_function_privilege(
    v.grantee,
    'public.list_companies_secure(text)',
    'EXECUTE'
  ) as can_execute
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-3b. PUBLIC EXECUTE is not present in the function ACL.
--    Expected: 0 rows for grantee = PUBLIC (=0/'' in acl) with EXECUTE.
select
  acl.grantee::regrole::text as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'list_companies_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text'
  and acl.grantee = 0    -- 0 = PUBLIC
order by acl.privilege_type;

-- P-4. companies table grant UNCHANGED (SELECT still true; no INSERT/UPDATE/DELETE
--    added). Expected: SELECT = true, INSERT/UPDATE/DELETE = false (both roles).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.companies', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.companies', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.companies', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-5. companies RLS / FORCE RLS UNCHANGED, and companies_select_public UNCHANGED.
--    Expected: rls_enabled = true, rls_forced = false; policy companies_select_public
--    still present (SELECT, roles {anon, authenticated}, qual (is_active = true));
--    no policy dropped (this file issues no DROP POLICY).
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'companies') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'companies';

select
  policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'companies'
order by cmd, policyname;
-- Direct SELECT REVOKE and policy DROP are NOT performed by this file (separate,
-- later steps). P-4 / P-5 above confirm they have not happened.


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER running the body)
--   NOTE: this step is ADDITIVE. The front-end has NOT been migrated yet, so the
--         live admin-app.html screens still use the direct SELECT and must keep
--         working exactly as before. list_companies_secure exists but is not yet
--         called by any screen.
--   - admin-app: perform a NEW login.
--   - Confirm the company dropdown is populated (現場 / 重機 / 従業員 modal).
--   - Confirm company-name display on: 現場一覧, 請求書一覧, 現場詳細, 重機一覧,
--     従業員一覧.
--   - logout.
--   - (Optional) Direct RPC check: call
--       select * from public.list_companies_secure('<valid management session token>');
--     ONLY with a valid admin / admin-role-employee session token; it must return
--     active companies as (id, name) ordered by name. An invalid / expired token
--     must raise 'Invalid or expired session'.
--   - Because the front-end is not migrated in this step, the production screens do
--     NOT yet call list_companies_secure; that switch happens in the next
--     (front-end migration) step.
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Removes exactly the function this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on it yet.
-- ============================================================
-- DROP FUNCTION public.list_companies_secure(text);
-- ============================================================
