-- ============================================================
-- Phase 4-F-2B-1: remove UNUSED direct SELECT grants on the two category
--   master tables (company_categories / site_categories) for anon / authenticated.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file has NOT been run against any database.
--   - It is intended to be executed MANUALLY by the user in the Supabase SQL
--     Editor (pre-check -> body -> post-check, in order).
--   - Claude Code CLI does NOT connect to the DB and does NOT use the Supabase
--     CLI or psql. All DB execution and all checks (pre / post) are performed by
--     the user in the Supabase SQL Editor.
--
-- [PURPOSE]
--   Remove the UNUSED direct SELECT grant held by anon / authenticated on the two
--   category master tables. Front-end introspection (Phase 4-F-2B B-1..B-4) found
--   ZERO direct references to these tables from the three app HTML files
--   (index.html / admin-app.html / genka-app.html). The only DB-side consumers are
--   SECURITY DEFINER RPCs, which execute with their owner's privileges and are
--   therefore expected to be unaffected by revoking SELECT from anon / authenticated
--   -- but this MUST be confirmed against the LIVE database in the pre-check (P-2)
--   before running the body. This file targets EXISTING tables' direct SELECT grant
--   (pg_class.relacl) only.
--
-- [SCOPE]
--   Schema    : public only.
--   Tables    : company_categories, site_categories ONLY.
--   Grantees  : anon, authenticated ONLY.
--   Privilege : SELECT ONLY.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - INSERT / UPDATE / DELETE (never listed in any REVOKE below).
--   - RLS / policies (no DROP POLICY here; the matching SELECT policies are LEFT IN
--     PLACE and deferred to Phase 4-F-3 stale-policy cleanup).
--   - RPC definitions / function definitions / EXECUTE grants / SECURITY DEFINER.
--   - view definitions.
--   - HTML / JS / auth / PIN logic.
--   - default privileges (pg_default_acl).
--   - any other table.
--   - DROP POLICY.
--   - companies (INSERT/UPDATE residue -> Phase 4-F-2B-2),
--     admin_sessions / employee_sessions (high risk -> Phase 4-F-2B-3),
--     and the still-in-use direct SELECT tables (-> Phase 4-F-2B-4).
--
-- [REPO-CONFIRMED FACTS] (read-only, from the working tree; re-verified live in P-2)
--   - Front-end direct references to company_categories / site_categories in
--     index.html / admin-app.html / genka-app.html: 0 (zero) occurrences.
--   - The only repo SQL objects that JOIN these tables are the SECURITY DEFINER RPCs
--     in docs/sql/csv-export-secure-rpc.sql and docs/sql/report-void-rpc.sql
--     (all declared SECURITY DEFINER). P-2 below re-confirms this against the LIVE
--     database (repo files alone are NOT treated as authoritative).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - P-1: SELECT is already false for anon / authenticated on either target
--          (inconsistent with the B-1 result) -> STOP and re-investigate.
--   - P-2: any function that references either target table is SECURITY INVOKER
--          (prosecdef = false) -> STOP (would break for anon / authenticated).
--   - P-2: any SECURITY DEFINER function's OWNER cannot SELECT the referenced target
--          table -> STOP (the DEFINER path would break).
--   - P-2: any view (or matview) referencing either target table is returned at all
--          -> STOP (do NOT auto-conclude "safe"; assess it manually before the body).
--   - P-3: the SELECT direct grant is NOT actually present (nothing to revoke) ->
--          STOP (inconsistent with B-1).
--   - Any new front-end direct reference to these tables is discovered -> STOP (re-scope).
--   - The body would change any privilege / table outside SCOPE -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Assuming that no OTHER related state has been changed (policies, function
--   definitions, view definitions, ownership, default privileges, etc.), the two
--   commented GRANT SELECT statements restore the TABLE-PRIVILEGE layer to its
--   pre-REVOKE state. This is NOT asserted to be a full/complete restoration of the
--   system -- only of the direct SELECT grant that this file removes.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1a. Existence of the two target tables.
--    Expected: table_exists = true for BOTH. STOP if either is false.
select
  t.object_name,
  to_regclass(t.object_name) is not null as table_exists
from (values
  ('public.company_categories'),
  ('public.site_categories')
) as t(object_name)
order by t.object_name;

-- P-1b. Current SELECT + CRUD state for the 2 targets x 2 roles.
--    Expected: can_select = true for all 4 rows (matches B-1). Record can_insert /
--    can_update / can_delete now; POST-CHECK Q-2 must show these UNCHANGED.
--    STOP if can_select is already false anywhere (inconsistent with B-1).
select
  v.role_name,
  v.object_name,
  has_table_privilege(v.role_name, v.object_name, 'SELECT') as can_select,
  has_table_privilege(v.role_name, v.object_name, 'INSERT') as can_insert,
  has_table_privilege(v.role_name, v.object_name, 'UPDATE') as can_update,
  has_table_privilege(v.role_name, v.object_name, 'DELETE') as can_delete
from (values
  ('anon',          'public.company_categories'),
  ('authenticated', 'public.company_categories'),
  ('anon',          'public.site_categories'),
  ('authenticated', 'public.site_categories')
) as v(role_name, object_name)
order by v.object_name, v.role_name;

-- P-1c. RLS enabled state + the matching SELECT policies (informational only).
--    These policies are LEFT IN PLACE by this file (Phase 4-F-3 cleanup). Recorded
--    here so POST-CHECK Q-2 can confirm they are still present afterwards.
select
  n.nspname            as schema_name,
  c.relname            as table_name,
  c.relrowsecurity     as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('company_categories', 'site_categories')
order by c.relname;

select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles
from pg_policies
where schemaname = 'public'
  and tablename in ('company_categories', 'site_categories')
order by tablename, policyname;

-- P-2a. LIVE dependency scan: functions / procedures that reference either target table.
--    pg_depend alone can miss references inside PL/pgSQL bodies, so this searches
--    the full routine definition text via pg_get_functiondef.
--    For each such routine, show its signature, whether it is SECURITY DEFINER,
--    its owner, and whether the OWNER can SELECT each target table.
--    Expected: every referencing routine is SECURITY DEFINER (is_security_definer =
--    true) AND its owner can SELECT BOTH target tables (or at least the one it uses).
--    STOP if:
--      - any referencing routine is SECURITY INVOKER (is_security_definer = false), OR
--      - any SECURITY DEFINER routine's owner cannot SELECT a target table it uses.
--    NOTE: prokind is restricted to 'f' (functions) / 'p' (procedures) INSIDE a
--    MATERIALIZED CTE, so pg_get_functiondef is only ever called on those routines.
--    aggregate ('a') / window ('w') routines -- for which pg_get_functiondef raises
--    an error -- are filtered out first, independent of WHERE-predicate ordering.
with target_routines as materialized (
  select
    p.oid,
    p.prosecdef,
    p.proowner
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where p.prokind in ('f', 'p')
    and n.nspname not in ('pg_catalog', 'information_schema')
)
select
  r.oid::regprocedure::text as function_signature,
  r.prosecdef as is_security_definer,
  pg_get_userbyid(r.proowner) as owner,
  has_table_privilege(
    r.proowner,
    'public.company_categories',
    'SELECT'
  ) as owner_can_select_company_categories,
  has_table_privilege(
    r.proowner,
    'public.site_categories',
    'SELECT'
  ) as owner_can_select_site_categories
from target_routines r
where pg_get_functiondef(r.oid) ilike '%company_categories%'
   or pg_get_functiondef(r.oid) ilike '%site_categories%'
order by function_signature;

-- P-2b. LIVE dependency scan: views / materialized views that reference either
--    target table (definition text search via pg_get_viewdef).
--    A view normally runs with the VIEW OWNER's privileges; a view created with the
--    security_invoker = true option instead uses the QUERYING role's privileges.
--    Show owner and whether the security_invoker option is set.
--    Expected: 0 rows. No view is expected to reference these tables.
--    STOP if ANY row is returned: do NOT auto-conclude "safe". Any returned view is a
--    STOP-and-review signal. Manually assess each (security_invoker vs owner-privilege,
--    the owner's SELECT rights, and reachability by anon / authenticated) BEFORE
--    proceeding to the body. Do not run the body while any such view is unresolved.
select
  c.oid::regclass                                as view_name,
  c.relkind                                      as relkind,   -- 'v' = view, 'm' = matview
  pg_get_userbyid(c.relowner)                    as owner,
  coalesce(
    array_to_string(c.reloptions, ',') ilike '%security_invoker=true%',
    false
  )                                              as is_security_invoker
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('v', 'm')
  and n.nspname not in ('pg_catalog', 'information_schema')
  and (
        pg_get_viewdef(c.oid) ilike '%company_categories%'
     or pg_get_viewdef(c.oid) ilike '%site_categories%'
      )
order by view_name;

-- P-3. relacl / aclexplode: confirm the SELECT DIRECT grant actually exists for
--    anon / authenticated on both targets (so the REVOKE is meaningful, not a no-op).
--    Expected: exactly 4 rows (2 tables x 2 roles, all privilege_type = SELECT).
--    STOP if fewer than 4 rows (grant already absent -> inconsistent with B-1).
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname in ('company_categories', 'site_categories')
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type = 'SELECT'
order by table_name, grantee;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks pass with no STOP condition hit, and after P-1b's CRUD values
--         have been recorded for the POST-CHECK comparison.
--   NOTE: 2 statements total. One table per statement, alphabetical order.
--   NOTE: SELECT is the ONLY privilege listed. INSERT / UPDATE / DELETE are never
--         listed. No other table is listed. No DROP POLICY.
-- ============================================================

REVOKE SELECT ON TABLE public.company_categories FROM anon, authenticated;
REVOKE SELECT ON TABLE public.site_categories    FROM anon, authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- Q-1. Goal achieved: SELECT is now false for both targets x both roles.
--    Expected: can_select = false for all 4 rows. STOP if any is still true.
select
  v.role_name,
  v.object_name,
  has_table_privilege(v.role_name, v.object_name, 'SELECT') as can_select
from (values
  ('anon',          'public.company_categories'),
  ('authenticated', 'public.company_categories'),
  ('anon',          'public.site_categories'),
  ('authenticated', 'public.site_categories')
) as v(role_name, object_name)
order by v.object_name, v.role_name;

-- Q-2a. No collateral change: INSERT / UPDATE / DELETE must be UNCHANGED vs P-1b.
--    Compare row by row against P-1b. STOP if any value differs (guards against a
--    typo that revoked something other than SELECT).
select
  v.role_name,
  v.object_name,
  has_table_privilege(v.role_name, v.object_name, 'INSERT') as can_insert,
  has_table_privilege(v.role_name, v.object_name, 'UPDATE') as can_update,
  has_table_privilege(v.role_name, v.object_name, 'DELETE') as can_delete
from (values
  ('anon',          'public.company_categories'),
  ('authenticated', 'public.company_categories'),
  ('anon',          'public.site_categories'),
  ('authenticated', 'public.site_categories')
) as v(role_name, object_name)
order by v.object_name, v.role_name;

-- Q-2b. The matching SELECT policies are still present (NOT dropped by this file).
--    Expected: the same policy rows as in P-1c.
select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles
from pg_policies
where schemaname = 'public'
  and tablename in ('company_categories', 'site_categories')
order by tablename, policyname;

-- Q-3. relacl / aclexplode: the anon / authenticated SELECT direct grant is gone.
--    Expected: 0 rows. STOP if any row remains.
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname in ('company_categories', 'site_categories')
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type = 'SELECT'
order by table_name, grantee;

-- Q-4 (OPTIONAL, NOT auto-run here). Live smoke test of the SECURITY DEFINER
--    consumers is a MANUAL, optional confirmation to run only AFTER the DB-side
--    privilege checks above have passed. It is intentionally NOT included as an
--    executable statement in this file (it would require admin-session arguments and
--    is out of scope for a grant-only change). Example consumers to spot-check
--    manually if desired: the csv_export_* / export_*_secure RPCs that JOIN
--    site_categories / company_categories.


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Assuming NO other related state has been changed (policies, function
--   definitions, view definitions, ownership, default privileges, etc.), the two
--   GRANT SELECT statements below restore the TABLE-PRIVILEGE layer to its
--   pre-REVOKE state -- i.e. they re-add exactly the direct SELECT grant this file
--   removed. This is NOT a claim of full system restoration; it only reverses the
--   direct SELECT grant change.
-- ============================================================
-- GRANT SELECT ON TABLE public.company_categories TO anon, authenticated;
-- GRANT SELECT ON TABLE public.site_categories    TO anon, authenticated;
-- ============================================================
