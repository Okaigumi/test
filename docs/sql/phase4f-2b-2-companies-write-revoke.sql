-- ============================================================
-- Phase 4-F-2B-2: remove residual direct INSERT / UPDATE grants on public.companies
--   for anon / authenticated.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file has NOT been run against any database.
--   - It is intended to be executed MANUALLY by the user in the Supabase SQL
--     Editor (pre-check -> body -> post-check, in order).
--   - Claude Code CLI does NOT connect to the DB and does NOT use the Supabase
--     CLI or psql. All DB execution and all checks (pre / post) are performed by
--     the user in the Supabase SQL Editor.
--   - The pre-check results recorded below (C-1..C-8) were produced by the user
--     running the read-only introspection in the Supabase SQL Editor prior to this
--     file. They are documented here as the basis for the REVOKE, and the same
--     queries are kept re-runnable so they can be re-confirmed before the body.
--
-- [PURPOSE]
--   Remove the direct INSERT / UPDATE grant currently held by anon / authenticated on
--   public.companies.
--     - Repository investigation and live DB introspection found NO in-app companies
--       write path that uses anon / authenticated:
--         * Front-end: 0 writes (only 1 direct SELECT in admin-app.html for a dropdown).
--         * RPC: no routine INSERTs / UPDATEs companies; all routine access is read-only
--           (JOIN / existence check), SECURITY DEFINER, owner postgres.
--         * RLS: companies has only a SELECT policy (companies_select_public); with no
--           INSERT / UPDATE policy present, those writes are blocked by RLS even while
--           the grant exists.
--     - DB management operations performed via privileged roles are OUT OF SCOPE for
--       this REVOKE (this file only touches anon / authenticated).
--     - This file does NOT assert anything about out-of-app create / update operations.
--   This file targets EXISTING table direct grants (pg_class.relacl) only.
--
-- [SCOPE]
--   Schema     : public only.
--   Table      : companies ONLY.
--   Grantees   : anon, authenticated ONLY.
--   Privileges : INSERT, UPDATE ONLY.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - SELECT grant (kept; still used by admin-app.html for the company dropdown;
--     any RPC-ization of that read is a separate later step, Phase 4-F-2B-4).
--   - DELETE grant (already false for anon / authenticated; not listed).
--   - RLS (not enabled/disabled/forced here).
--   - companies_select_public policy (LEFT IN PLACE; no DROP POLICY).
--   - RPC / function definitions / EXECUTE grants.
--   - view / materialized view definitions.
--   - trigger definitions.
--   - foreign key / constraint definitions, internal constraint triggers, and
--     child-table privileges (not changed here; FK existence alone is not a STOP condition).
--   - HTML / JS / auth / PIN logic.
--   - default privileges (pg_default_acl).
--   - any other table.
--   - docs/roadmap.md, docs/db-migrations.md (updated separately in the record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - C-2: INSERT or UPDATE already false for anon / authenticated (inconsistent with
--          the recorded pre-check) -> STOP and re-investigate.
--   - C-3: any INSERT / UPDATE policy exists on companies -> STOP (revoking would leave
--          it stale, and its usage path must be re-checked first).
--   - C-4: the anon / authenticated INSERT / UPDATE direct grant is NOT present
--          (fewer than 4 rows) -> STOP (nothing meaningful to revoke; inconsistent).
--   - C-5: STOP (and check manually) if any of the following is returned:
--          * body_inserts_companies = true or body_updates_companies = true for ANY
--            routine, regardless of SECURITY DEFINER / INVOKER;
--          * any SECURITY INVOKER routine that references companies;
--          * any routine whose owner lacks the privilege needed to read / write companies.
--   - C-6: any view / materialized view referencing companies is returned at all
--          -> STOP (do NOT auto-conclude "safe"; assess it manually before the body).
--   - C-7: any trigger on companies, or any trigger function that writes companies,
--          is returned -> STOP (a write path may depend on these grants).
--   - Any new front-end write to companies is discovered -> STOP (re-scope).
--   - The body would change any privilege / table outside SCOPE -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Assuming that no OTHER related state has been changed (policies, function / view
--   definitions, triggers, ownership, default privileges, etc.), the commented GRANT
--   restores the TABLE-PRIVILEGE layer to its pre-REVOKE state -- i.e. it re-adds
--   exactly the direct INSERT / UPDATE grant this file removed. This is NOT a claim of
--   full system restoration; it only reverses the direct INSERT / UPDATE grant change.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Recorded results below reflect the user's Supabase SQL Editor run prior to this
--   file. The queries are re-runnable to re-confirm before executing the body.
-- ============================================================

-- C-1. companies existence + RLS state.
--    Recorded: table exists, relkind = 'r', rls_enabled = true, rls_forced = false.
--    STOP if the table is missing, or rls_enabled is not true (unexpected).
select
  n.nspname            as schema_name,
  c.relname            as table_name,
  c.relkind            as relkind,          -- expected 'r' (ordinary table)
  c.relrowsecurity     as rls_enabled,      -- expected true
  c.relforcerowsecurity as rls_forced       -- expected false
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'companies';

-- C-2. anon / authenticated effective CRUD on companies.
--    Recorded: SELECT = true, INSERT = true, UPDATE = true, DELETE = false (both roles).
--    Record INSERT / UPDATE now; POST-CHECK Q-1 must show them false afterwards, and
--    SELECT unchanged (true) / DELETE unchanged (false).
--    STOP if INSERT or UPDATE is already false (inconsistent with the recorded state).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.companies', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.companies', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.companies', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. companies pg_policies (all rows).
--    Recorded: exactly 1 policy -- companies_select_public
--      (roles = {anon, authenticated}, cmd = SELECT, qual = (is_active = true)).
--      No INSERT / UPDATE policy exists.
--    STOP if any INSERT / UPDATE policy is present (would become stale after revoke;
--    re-check its usage path first).
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

-- C-4. relacl / aclexplode: explicit anon / authenticated INSERT / UPDATE direct grant.
--    Recorded: exactly 4 rows
--      (companies/anon/INSERT, companies/anon/UPDATE,
--       companies/authenticated/INSERT, companies/authenticated/UPDATE).
--    STOP if fewer than 4 rows (grant absent -> inconsistent; nothing to revoke).
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname = 'companies'
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type in ('INSERT', 'UPDATE')
order by grantee, acl.privilege_type;

-- C-5. LIVE dependency scan: routines that reference companies (body text search),
--    with SECURITY DEFINER flag, owner, owner privileges, and whether the body
--    actually writes companies. prokind is restricted to 'f' / 'p' INSIDE a
--    MATERIALIZED CTE so pg_get_functiondef is never called on aggregate / window
--    routines (which would error), independent of WHERE-predicate ordering.
--    Recorded: 7 referencing routines, all SECURITY DEFINER = true, owner = postgres,
--      owner_can_select / insert / update = true, body_inserts_companies = false,
--      body_updates_companies = false. The 7 routines:
--        create_machine_admin_secure(...), create_site_secure(...),
--        export_machine_details_secure(...), export_project_cost_details_secure(...),
--        export_projects_summary_secure(...), update_machine_admin_secure(...),
--        update_site_secure(...).
--    STOP (and check manually) if any of the following is returned:
--      * body_inserts_companies = true or body_updates_companies = true for ANY routine,
--        regardless of SECURITY DEFINER / INVOKER;
--      * any SECURITY INVOKER routine that references companies;
--      * any routine whose owner lacks the privilege needed to read / write companies.
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
  r.oid::regprocedure::text                                     as function_signature,
  r.prosecdef                                                   as is_security_definer,
  pg_get_userbyid(r.proowner)                                   as owner,
  has_table_privilege(r.proowner, 'public.companies', 'SELECT') as owner_can_select,
  has_table_privilege(r.proowner, 'public.companies', 'INSERT') as owner_can_insert,
  has_table_privilege(r.proowner, 'public.companies', 'UPDATE') as owner_can_update,
  (pg_get_functiondef(r.oid) ~* '\minsert\s+into\s+(public\.)?companies\M') as body_inserts_companies,
  (pg_get_functiondef(r.oid) ~* '\mupdate\s+(public\.)?companies\M')        as body_updates_companies
from target_routines r
where pg_get_functiondef(r.oid) ilike '%companies%'
order by function_signature;

-- C-6. LIVE dependency scan: views / materialized views referencing companies.
--    Recorded: 0 rows.
--    STOP if ANY row is returned: do NOT auto-conclude "safe". Any returned view is a
--    STOP-and-review signal. Manually assess each (security_invoker vs owner-privilege,
--    the owner's rights, and reachability by anon / authenticated) BEFORE the body.
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
  and pg_get_viewdef(c.oid) ilike '%companies%'
order by view_name;

-- C-7. LIVE dependency scan: triggers on companies, and trigger functions that write
--    companies. pg_get_functiondef is called only on user (non-internal) trigger
--    functions here.
--    Recorded: 0 user-defined triggers on companies, and 0 trigger functions that
--      INSERT / UPDATE companies.
--    STOP if ANY row is returned (a write path may depend on these grants).
select
  tn.nspname                              as table_schema,
  t.tgname                                as trigger_name,
  c.relname                               as on_table,
  p.oid::regprocedure::text               as trigger_function,
  p.prosecdef                             as is_security_definer,
  pg_get_userbyid(p.proowner)             as owner
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace tn
  on tn.oid = c.relnamespace
join pg_proc  p on p.oid = t.tgfoid
where not t.tgisinternal
  and (
        (
          tn.nspname = 'public'
          and c.relname = 'companies'
        )
     or pg_get_functiondef(p.oid) ~* '\m(insert\s+into|update)\s+(public\.)?companies\M'
      )
order by table_schema, on_table, t.tgname;

-- C-8. FK constraints that reference companies (informational only).
--    Recorded: 7 child tables reference companies
--      (employees, invoices, machines, site_budgets, sites, subcontractors, unit_rates).
--    This list is for information confirmation only. This file does NOT change FK
--    definitions, internal constraint triggers, or child-table privileges. Revoking the
--    anon / authenticated INSERT / UPDATE direct grant on public.companies does not
--    change any FK definition. The mere existence of FKs is NOT a STOP condition.
select
  conrelid::regclass          as child_table,
  conname                     as constraint_name,
  pg_get_constraintdef(oid)   as fk_def
from pg_constraint
where contype = 'f'
  and confrelid = 'public.companies'::regclass
order by child_table, conname;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (C-1..C-8) are re-confirmed with no STOP condition hit.
--   NOTE: 1 statement. INSERT / UPDATE are the ONLY privileges listed. SELECT and
--         DELETE are never listed. No other table. No DROP POLICY. No GRANT.
--   NOTE: re-runnable -- REVOKE of an already-absent privilege is a no-op.
-- ============================================================

REVOKE INSERT, UPDATE ON TABLE public.companies FROM anon, authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- Q-1. anon / authenticated effective CRUD on companies.
--    Expected: SELECT = true, INSERT = false, UPDATE = false, DELETE = false (both).
--    STOP if INSERT or UPDATE is still true, or if SELECT / DELETE changed vs C-2.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.companies', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.companies', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.companies', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- Q-2. companies pg_policies (unchanged).
--    Expected: companies_select_public still present; NO INSERT / UPDATE policy;
--    no policy was dropped (DROP POLICY not used by this file).
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

-- Q-3. relacl / aclexplode: anon / authenticated INSERT / UPDATE direct grant is gone.
--    Expected: 0 rows. STOP if any row remains.
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname = 'companies'
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type in ('INSERT', 'UPDATE')
order by grantee, acl.privilege_type;

-- Q-4. SELECT grant retained.
--    Expected: SELECT = true for both anon / authenticated (unchanged by this file).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.companies', 'SELECT') as can_select
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Assuming NO other related state has been changed (policies, function / view
--   definitions, triggers, ownership, default privileges, etc.), the GRANT below
--   restores the TABLE-PRIVILEGE layer to its pre-REVOKE state -- i.e. it re-adds
--   exactly the direct INSERT / UPDATE grant this file removed. This is NOT a claim of
--   full system restoration; it only reverses the direct INSERT / UPDATE grant change.
-- ============================================================
-- GRANT INSERT, UPDATE ON TABLE public.companies TO anon, authenticated;
-- ============================================================
