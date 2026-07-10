-- ============================================================
-- Phase 4-F-3: drop the STALE, currently-unused SELECT policies
--   cc_select (public.company_categories) / sc_select (public.site_categories).
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file is prepared for manual execution by the user in the Supabase SQL
--     Editor. The EXECUTION BODY (2 statements) has NOT been run yet.
--   - The PRE-CHECK results recorded below (D-1..D-5b) reflect the user's live
--     Supabase SQL Editor run against the current database; all checks PASSED and
--     no STOP condition was hit. The queries are kept re-runnable to re-confirm
--     immediately before executing the body.
--   - DB execution and all checks (pre / post) are performed manually by the user
--     in the Supabase SQL Editor. No DB connection / Supabase CLI / psql is used
--     from Claude Code CLI.
--
-- [PURPOSE]
--   Remove the two SELECT policies cc_select / sc_select, which are STALE after
--   Phase 4-F-2B-1:
--     - After 4-F-2B-1, the anon / authenticated effective SELECT privilege on both
--       tables is false; there is no grant for these PERMISSIVE SELECT policies to
--       act upon, so cc_select / sc_select are currently unused in practice.
--     - However, if SELECT were re-GRANTed to anon / authenticated in the future,
--       these policies would AGAIN become an active permit path.
--     - This DROP removes that latent permit path as a defense-in-depth tidy-up of
--       the policy layer.
--   The SECURITY DEFINER read path is unaffected: the only referencing routine,
--   export_projects_summary_secure(...), runs as owner postgres (SECURITY DEFINER,
--   BYPASSRLS, table owner of both tables; both tables FORCE RLS = false), and does
--   not depend on cc_select / sc_select (confirmed in D-5a). This file touches the
--   POLICY layer only.
--
-- [SCOPE]
--   Schema   : public only.
--   Tables   : company_categories, site_categories ONLY.
--   Policies : cc_select (company_categories), sc_select (site_categories) ONLY.
--   Action   : DROP POLICY only (2 statements).
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - table grants (any GRANT / REVOKE).
--   - SELECT / INSERT / UPDATE / DELETE privileges.
--   - RLS enabled state / FORCE RLS.
--   - RPC / function definitions / EXECUTE grants / SECURITY DEFINER.
--   - view / materialized view definitions.
--   - HTML / JS / auth / PIN logic.
--   - default privileges (pg_default_acl).
--   - any other table.
--   - employees_update_public.
--   - any OTHER policy (only cc_select / sc_select are dropped here).
--   - docs/roadmap.md, docs/db-migrations.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - D-1: either target table is missing, relkind <> 'r', or rls_enabled <> true.
--   - D-2: SELECT is already true for anon / authenticated on either target
--          (inconsistent with 4-F-2B-1; dropping the only permissive policy while the
--          grant exists would CLOSE direct SELECT for anon / authenticated) -> STOP.
--   - D-3: any policy OTHER than cc_select / sc_select exists on either target table,
--          OR either target policy does not match the expected shape
--          (PERMISSIVE / roles {anon,authenticated} / cmd SELECT / qual true /
--          with_check null) -> STOP.
--   - D-4b: any role that is a MEMBER of / inherits anon or authenticated has an
--          effective SELECT on either target table -> STOP (that role would lose its
--          policy permit path on DROP; re-assess first).
--   - D-5a: any routine referencing either target table is SECURITY INVOKER; OR is
--          SECURITY DEFINER but its owner cannot SELECT a referenced target; OR its
--          owner is neither superuser nor BYPASSRLS nor (table owner AND that table's
--          FORCE RLS = false) while no SELECT policy would apply to the owner after
--          DROP -> STOP.
--   - D-5b: any view / materialized view references either target table -> STOP
--          (do NOT auto-conclude "safe"; assess it manually before the body).
--   - Any new front-end direct reference to these tables is discovered -> STOP.
--   - The body would change any policy / privilege / table outside SCOPE -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   The commented CREATE POLICY statements restore ONLY the policy layer this file
--   removes. Phase 4-F-2B-1 already revoked the anon / authenticated SELECT grant and
--   this file does NOT restore it; therefore rollback alone does NOT re-enable direct
--   SELECT for anon / authenticated.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Recorded results below reflect the user's live Supabase SQL Editor run.
--   All PASSED; no STOP condition hit. Re-run to re-confirm before the body.
-- ============================================================

-- D-1. Existence + RLS state (enabled / forced) for the two targets.
--    Recorded: both exist, relkind = 'r', rls_enabled = true, rls_forced = false.
--    STOP if a table is missing, relkind <> 'r', or rls_enabled <> true.
select
  n.nspname             as schema_name,
  c.relname             as table_name,
  c.relkind             as relkind,             -- expected 'r'
  c.relrowsecurity      as rls_enabled,         -- expected true
  c.relforcerowsecurity as rls_forced           -- recorded false (used by D-5a logic)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('company_categories', 'site_categories')
order by c.relname;

-- D-2. anon / authenticated effective SELECT (post 4-F-2B-1 re-confirmation).
--    Recorded: can_select = false for all 4 rows.
--    STOP if SELECT is true for anon or authenticated on either target.
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

-- D-3. Target policy detail (list ALL policies on the two tables).
--    Recorded: exactly 2 policies -- company_categories/cc_select and
--      site_categories/sc_select. Both: permissive = PERMISSIVE,
--      roles = {anon,authenticated}, cmd = SELECT, qual = true, with_check = null.
--      No other policy exists on either table.
--    STOP if any other policy appears, or either target policy differs from the
--    expected shape.
select
  schemaname,
  tablename,
  policyname,
  permissive,     -- expected 'PERMISSIVE'
  roles,          -- expected {anon,authenticated}
  cmd,            -- expected 'SELECT'
  qual,           -- expected 'true'
  with_check      -- expected null
from pg_policies
where schemaname = 'public'
  and tablename in ('company_categories', 'site_categories')
order by tablename, policyname;

-- D-4a. Roles that are MEMBERS of / inherit anon or authenticated (excluding the two
--    themselves). cc_select / sc_select target TO anon, authenticated only, so only
--    member/inheriting roles can receive these policies; unrelated roles are out of
--    scope for this DROP's impact assessment.
--    Recorded: authenticator (rolinherit = false), supabase_storage_admin
--      (rolinherit = false), postgres (rolinherit = true).
select
  r.rolname,
  r.rolinherit,
  pg_has_role(r.rolname, 'anon', 'MEMBER')          as member_of_anon,
  pg_has_role(r.rolname, 'authenticated', 'MEMBER') as member_of_authenticated
from pg_roles r
where r.rolname not in ('anon', 'authenticated')
  and ( pg_has_role(r.rolname, 'anon', 'MEMBER')
     or pg_has_role(r.rolname, 'authenticated', 'MEMBER') )
order by r.rolname;

-- D-4b. Effective SELECT of the member/inheriting roles found in D-4a.
--    Recorded: authenticator -> SELECT false on both tables;
--      supabase_storage_admin -> SELECT false on both tables;
--      postgres -> SELECT true on both tables, BUT postgres is BYPASSRLS = true and
--      is the table owner of both tables, so its access does NOT depend on
--      cc_select / sc_select (RLS is bypassed regardless of these policies).
--    STOP if any role whose SELECT depends on an RLS policy path (i.e. not bypassing
--    RLS via superuser / BYPASSRLS / non-forced table ownership) has effective SELECT.
select
  r.rolname,
  r.rolsuper,
  r.rolbypassrls,
  has_table_privilege(r.rolname, 'public.company_categories', 'SELECT') as cc_can_select,
  has_table_privilege(r.rolname, 'public.site_categories',    'SELECT') as sc_can_select
from pg_roles r
where r.rolname in ('authenticator', 'supabase_storage_admin', 'postgres')
order by r.rolname;

-- D-5a. Routines referencing either target table, with full RLS-bypass determination
--    for the owner (do NOT infer "bypass" from SECURITY DEFINER alone).
--    prokind restricted to 'f' / 'p' inside a MATERIALIZED CTE so pg_get_functiondef
--    is never called on aggregate / window routines (which would error).
--    Recorded: exactly 1 routine -- export_projects_summary_secure(...), referencing
--      BOTH tables. is_security_definer = true, owner = postgres,
--      owner_can_select_cc = owner_can_select_sc = true, owner_is_superuser = true (n/a
--      but bypass holds), owner_has_bypassrls = true, owner_is_cc_table_owner = true,
--      owner_is_sc_table_owner = true, cc_force_rls = false, sc_force_rls = false.
--      => owner bypasses RLS; the routine does NOT depend on cc_select / sc_select.
--    STOP if: any referencing routine is SECURITY INVOKER; OR a SECURITY DEFINER
--      routine's owner cannot SELECT a referenced target; OR the owner is neither
--      superuser nor BYPASSRLS nor (table owner AND that table's FORCE RLS = false)
--      while no SELECT policy would apply to the owner after DROP.
with target_routines as materialized (
  select p.oid, p.prosecdef, p.proowner
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where p.prokind in ('f', 'p')
    and n.nspname not in ('pg_catalog', 'information_schema')
),
tbls as (
  select
    max(case when c.relname = 'company_categories' then c.relowner end)  as cc_owner,
    max(case when c.relname = 'site_categories'    then c.relowner end)  as sc_owner,
    bool_or(c.relname = 'company_categories' and c.relforcerowsecurity)  as cc_force_rls,
    bool_or(c.relname = 'site_categories'    and c.relforcerowsecurity)  as sc_force_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('company_categories', 'site_categories')
)
select
  r.oid::regprocedure::text                                             as function_signature,
  r.prosecdef                                                           as is_security_definer,
  pg_get_userbyid(r.proowner)                                           as owner,
  has_table_privilege(r.proowner, 'public.company_categories', 'SELECT') as owner_can_select_cc,
  has_table_privilege(r.proowner, 'public.site_categories',    'SELECT') as owner_can_select_sc,
  ro.rolsuper                                                           as owner_is_superuser,
  ro.rolbypassrls                                                       as owner_has_bypassrls,
  (r.proowner = t.cc_owner)                                             as owner_is_cc_table_owner,
  (r.proowner = t.sc_owner)                                             as owner_is_sc_table_owner,
  t.cc_force_rls,
  t.sc_force_rls
from target_routines r
cross join tbls t
join pg_roles ro on ro.oid = r.proowner
where pg_get_functiondef(r.oid) ilike '%company_categories%'
   or pg_get_functiondef(r.oid) ilike '%site_categories%'
order by function_signature;

-- D-5b. Views / materialized views referencing either target table.
--    Recorded: 0 rows.
--    STOP if ANY row is returned: do NOT auto-conclude "safe"; assess each manually
--    (security_invoker vs owner-privilege, reachability) BEFORE the body.
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


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (D-1..D-5b) are re-confirmed with no STOP condition hit.
--   NOTE: 2 statements. DROP POLICY only. No IF EXISTS (a missing policy or a name
--         mismatch MUST surface as an error). No CASCADE. No grant change. No RLS
--         change. No other policy touched. One table per statement.
-- ============================================================

DROP POLICY cc_select ON public.company_categories;
DROP POLICY sc_select ON public.site_categories;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- Q-1. The two target policies are gone; no policy remains on either target table
--    (pre-check D-3 confirmed there were no other policies).
--    Expected: 0 rows. STOP if cc_select / sc_select (or any row) remains.
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

-- Q-2. RLS state unchanged: enabled stays true, forced stays false (DROP POLICY does
--    not alter RLS enable/force state).
--    Expected: rls_enabled = true, rls_forced = false for both. STOP if changed.
select
  c.relname             as table_name,
  c.relrowsecurity      as rls_enabled,   -- expected true
  c.relforcerowsecurity as rls_forced     -- expected false
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('company_categories', 'site_categories')
order by c.relname;

-- Q-3. anon / authenticated effective CRUD unchanged (the policy DROP does not alter
--    table privileges).
--    Expected: SELECT / INSERT / UPDATE / DELETE = false for all 4 rows.
--    STOP if any value differs from the recorded pre-state.
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

-- Q-4. relacl / aclexplode: anon / authenticated direct grants (SELECT / INSERT /
--    UPDATE / DELETE) remain absent -- unchanged by this file.
--    Expected: 0 rows. STOP if any anon / authenticated grant row appears.
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
  and acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
order by table_name, grantee, acl.privilege_type;

-- Q-5 (OPTIONAL, NOT run here). A live smoke test of the SECURITY DEFINER consumer
--    export_projects_summary_secure(...) -- confirming category names still resolve --
--    can be performed as a SEPARATE step AFTER the DB post-checks above pass. It is
--    intentionally NOT executed inside this file (this file does not run any RPC).


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Restores ONLY the policy layer this file removes (identical to the definitions in
--   docs/sql/phase1-schema-categories.sql). Phase 4-F-2B-1 already revoked the
--   anon / authenticated SELECT grant and this file does NOT restore it; therefore
--   this rollback alone does NOT re-enable direct SELECT for anon / authenticated.
-- ============================================================
-- CREATE POLICY cc_select
--   ON public.company_categories
--   FOR SELECT
--   TO anon, authenticated
--   USING (true);
--
-- CREATE POLICY sc_select
--   ON public.site_categories
--   FOR SELECT
--   TO anon, authenticated
--   USING (true);
-- ============================================================
