-- ============================================================
-- Phase 4-F-2B-4: companies direct read revoke
--   Remove the residual direct SELECT grant on public.companies for
--   anon / authenticated, and drop the now-unnecessary companies_select_public
--   policy, after the front-end has been migrated to the list_companies_secure RPC.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-11)
--   - Manually executed by the user in the Supabase SQL Editor, ONE statement at a
--     time.
--       * REVOKE SELECT:  "Success. No rows returned".
--       * DROP POLICY:    "Success. No rows returned".
--   - Pre-check all passed (no STOP condition hit).
--   - Post-check all passed.
--   - Production smoke test passed: after REVOKE, a production reload / new login
--     showed the company dropdown working; after the policy DROP, the final
--     production smoke test also passed.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--   - The pre-check results recorded below reflect the user's Supabase SQL Editor
--     run; the queries are kept re-runnable.
--   - Recorded in docs/db-migrations.md (2026-07-11 Phase 4-F-2B-4 companies direct
--     read撤廃 section).
--
-- [PURPOSE]
--   - admin-app.html's companies fetch has been migrated to the
--     public.list_companies_secure RPC (front-end migration PR #99).
--   - Remove the direct SELECT grant held by anon / authenticated on
--     public.companies (no longer used by the app).
--   - Drop the companies_select_public policy, which becomes unnecessary once the
--     direct SELECT grant is removed.
--
-- [SCOPE]
--   - public.companies SELECT privilege for anon / authenticated.
--   - public.companies companies_select_public policy.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - companies data.
--   - INSERT / UPDATE / DELETE privileges.
--   - RLS enabled state.
--   - FORCE RLS.
--   - RPC definitions (list_companies_secure and others).
--   - front-end code.
--   - other tables / other policies.
--
-- [PRE-CHECK results] (SELECT only; recorded from the user's Supabase SQL Editor run)
--   - anon SELECT = true.
--   - authenticated SELECT = true.
--   - both roles INSERT / UPDATE / DELETE = false.
--   - policies on companies: exactly 1 -- companies_select_public.
--   - companies_select_public content:
--       * PERMISSIVE
--       * roles {anon, authenticated}
--       * command SELECT
--       * qual (is_active = true)
--       * with_check null
--   - After PR #99 merge, production company dropdown and company-name display
--     verified working.
--
-- [PRE-CHECK queries] (re-runnable; SELECT only)
--
-- anon / authenticated privileges on companies.
-- select
--   v.role_name,
--   has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select,
--   has_table_privilege(v.role_name, 'public.companies', 'INSERT') as can_insert,
--   has_table_privilege(v.role_name, 'public.companies', 'UPDATE') as can_update,
--   has_table_privilege(v.role_name, 'public.companies', 'DELETE') as can_delete
-- from (values ('anon'), ('authenticated')) as v(role_name)
-- order by v.role_name;
--
-- companies policies.
-- select policyname, permissive, roles, cmd, qual, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename = 'companies'
-- order by cmd, policyname;


-- ============================================================
-- EXECUTION BODY
--   Run ONLY after the pre-checks are re-confirmed with no STOP condition hit.
--   Run ONE statement at a time in the Supabase SQL Editor.
-- ============================================================

REVOKE SELECT
ON TABLE public.companies
FROM anon, authenticated;

DROP POLICY companies_select_public
ON public.companies;

-- [Execution results]
--   - REVOKE SELECT: Success. No rows returned.
--   - DROP POLICY:   Success. No rows returned.
--   - Executed by the user in the Supabase SQL Editor, one statement at a time.
--   - No DB connection / Supabase CLI / psql from Claude Code CLI.


-- ============================================================
-- POST-CHECK results (SELECT only; recorded from the user's Supabase SQL Editor run)
-- ============================================================
--   - anon SELECT = false.
--   - authenticated SELECT = false.
--   - companies policy_count = 0.
--   - After REVOKE, a production reload / new login showed the company dropdown
--     working.
--   - The final production smoke test after the policy DROP also passed.
--
-- [POST-CHECK queries] (re-runnable; SELECT only)
--
-- anon / authenticated SELECT on companies (expect false / false).
-- select
--   v.role_name,
--   has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select
-- from (values ('anon'), ('authenticated')) as v(role_name)
-- order by v.role_name;
--
-- companies policy count (expect 0).
-- select count(*) as policy_count
-- from pg_policies
-- where schemaname = 'public' and tablename = 'companies';


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Restores the direct SELECT grant and re-creates the public SELECT policy.
-- ============================================================
-- GRANT SELECT
-- ON TABLE public.companies
-- TO anon, authenticated;
--
-- CREATE POLICY companies_select_public
-- ON public.companies
-- AS PERMISSIVE
-- FOR SELECT
-- TO anon, authenticated
-- USING (is_active = true);
-- ============================================================
