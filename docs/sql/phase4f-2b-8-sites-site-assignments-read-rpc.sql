-- ============================================================
-- Phase 4-F-2B-8: add secure read RPCs for public.sites / public.site_assignments
--   (list_sites_secure / list_site_assignments_secure /
--    list_sites_admin_secure / get_site_admin_secure /
--    list_site_assignments_admin_secure) so that index.html, admin-app.html and
--    genka-app.html can stop reading sites / site_assignments directly.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file ONLY adds five new read RPCs (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / body / post-check / smoke are run by the user.
--   - Run this file SECTION BY SECTION in this order:
--     PRE-CHECK (P-1..P-13) -> EXECUTION BODY (single transaction) ->
--     POST-CHECK (POST-1..POST-16) -> SMOKE TEST -> ROLLBACK only if needed.
--
-- [PURPOSE]
--   The three front-ends currently read public.sites / public.site_assignments via
--   direct SELECTs (7 direct reads: sites x5, site_assignments x2, incl. 1 embedded
--   JOIN in admin-app.html pageSites). This step adds SECURITY DEFINER read RPCs so the
--   direct reads can be migrated away (front-end step) and the direct SELECT grant can
--   later be revoked (revoke step). This is the standard 3-stage migration
--   (read RPC -> front-end move -> direct read shutdown), matching
--   phase4f-2b-7-subcontractors-read-rpc.sql and phase4f-2b-6-machine-locations-read-rpc.sql.
--
--   Five RPCs:
--     1. list_sites_secure(text)                        -- employee session, index.html
--     2. list_site_assignments_secure(text)             -- employee session, index.html
--     3. list_sites_admin_secure(text)                  -- mgmt session, admin + genka
--        (includes active_assignment_count for the admin sites list)
--     4. get_site_admin_secure(text, uuid)              -- mgmt session, admin openSiteModal
--        (id lookup, NO is_active filter -- returns active OR inactive by id)
--     5. list_site_assignments_admin_secure(text, uuid) -- mgmt session, admin openSiteModal
--
--   Employee RPCs (1,2): verify the employee session INLINE (same method as
--   list_subcontractors_secure / list_machines_secure / list_materials_secure).
--   Management RPCs (3,4,5): verify via the existing helper
--   public._verify_management_session(text) (same as list_subcontractors_admin_secure /
--   list_companies_secure / list_machines_admin_secure).
--
--   Return only the columns the front-end actually uses (NOT select('*')):
--     sites   -> id, name, company_id, location, start_date, end_date
--               (+ active_assignment_count for list_sites_admin_secure).
--               is_active is a server-side filter; category_id / contract_amount /
--               created_at are NOT returned (no front-end reads them via direct read).
--     assignments -> site_id, employee_id (employee) / employee_id (admin per-site).
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration / removal of the 7 direct reads,
--     - any REVOKE on sites / site_assignments (SELECT stays granted),
--     - any policy change / DROP POLICY (sites_read_all / sa_read left exactly as-is),
--     - any change to existing write RPCs or sites-internal read RPCs.
--
-- [SCOPE]
--   Add FIVE functions and set owner + EXECUTE privileges on those NEW functions only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - index.html / admin-app.html / genka-app.html (front-end step comes later).
--   - public.sites / public.site_assignments table grants (SELECT NOT revoked here).
--   - policies: sites_read_all / anon_can_insert_sites / anon_can_update_sites /
--     sa_read / sa_write / sa_update (NO change, NO drop).
--   - RLS / FORCE RLS on either table.
--   - sites / site_assignments data.
--   - existing write RPCs (create_site_secure / update_site_secure /
--     deactivate_site_secure / set_site_assignment_secure /
--     replace_site_assignments_secure) -- reused / unaffected, NOT modified.
--   - sites-internal read RPCs (export_projects_summary_secure / create_invoice_secure /
--     update_invoice_secure / create_machine_location_secure) -- NOT modified.
--   - public._verify_management_session(text) (reused as-is; NOT modified).
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
--   [KNOWN, INTENTIONALLY UNCHANGED] PUBLIC EXECUTE currently exists on the 5 write RPCs
--   and on create_invoice_secure / update_invoice_secure. These are recorded as baseline
--   in P-12 / P-13 but are OUT OF SCOPE for this additive file and are NOT modified here
--   (and are NOT stop conditions for this file).
--
-- [RE-RUN SAFETY]
--   - The body uses plain CREATE FUNCTION (NOT CREATE OR REPLACE). P-9 must return 0
--     rows (no pre-existing function of these 5 names). Plain CREATE is the second line
--     of defence: an unexpected pre-existing function makes the body ERROR OUT (and the
--     whole BEGIN..COMMIT roll back) instead of being silently replaced (fail closed).
--   - The whole body runs as ONE transaction, so a failure on any function rolls back
--     the entire step and leaves nothing half-created.
--   - Do NOT re-run the body as-is after it has succeeded (a second run stops with
--     "function already exists" and rolls back). Re-creating requires an explicit
--     ROLLBACK (DROP FUNCTION; see the end) first.
--   - PRE-CHECK / POST-CHECK / SMOKE are OUTSIDE this transaction (run separately).
--
-- [STOP CONDITIONS] (if any is hit in the pre-check, do NOT run the body; stop & report)
--   - P-1: sites or site_assignments missing, relkind <> 'r', RLS <> true,
--          FORCE RLS <> false, or owner <> postgres.
--   - P-3: any required column missing or of a different type
--          (sites.id/name/company_id/location/start_date/end_date/is_active;
--           site_assignments.site_id/employee_id/is_active).
--   - P-9: any of the 5 new function names already exists (collision / overload).
--   - P-10: employee_sessions (employee_id / token_hash / expires_at) or employees
--           (id / is_active) verification columns missing / wrong type.
--   - P-11: _verify_management_session(text) missing, not SECURITY DEFINER, owner not
--           postgres, or fixed search_path missing.
--   - P-8: any integrity anomaly (orphan / duplicate / active->inactive) is non-zero.
--   - P-12 / P-13: an existing write RPC or sites-internal read RPC differs from the
--           recorded baseline in a way other than the KNOWN PUBLIC EXECUTE above.
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--   NOTE: KNOWN PUBLIC EXECUTE (write RPCs, create_invoice_secure, update_invoice_secure)
--   is recorded as baseline only and is NOT a stop condition for this file.
--
-- [PRE-CHECK BASELINE] (measured by the user; C-1..C-16 -- expected values referenced
--  by the P-* queries below and the POST-* invariants)
--   - C-1: sites / site_assignments -- relkind 'r', RLS true, FORCE RLS false, owner postgres.
--   - C-2 / C-2b: anon / authenticated SELECT=true, other 7 false; ACL anon+authenticated
--     SELECT only, no PUBLIC, no grant option (both tables).
--   - C-3: columns as listed in P-3 (sites 10 cols; site_assignments 5 cols).
--   - C-4: PK/FK/UNIQUE(site_id,employee_id) all validated=true.
--   - C-5: all indexes valid=true / ready=true.
--   - C-6: policies -- sites: sites_read_all(SELECT,qual true) / anon_can_insert_sites(INSERT)
--     / anon_can_update_sites(UPDATE); site_assignments: sa_read(SELECT,qual true) /
--     sa_write(INSERT) / sa_update(UPDATE). NOT changed here.
--   - C-7: sites total 20 / active 10 / inactive 10 / null 0;
--     site_assignments total 29 / active 11 / inactive 18 / null 0.
--   - C-8: orphan site_id 0 / orphan employee_id 0 / duplicate assignment 0 /
--     active->inactive site 0 / active->inactive employee 0.
--   - C-9: all 5 new names 0 rows, no overload.
--   - C-10: employee verification columns present.
--   - C-11: _verify_management_session(text) -> TABLE(actor_type text, actor_id uuid),
--     SECURITY DEFINER, VOLATILE, owner postgres, search_path public, extensions,
--     ACL postgres/service_role only (no PUBLIC/anon/authenticated EXECUTE).
--   - C-12: write RPCs (5) SECURITY DEFINER / VOLATILE / owner postgres / fixed
--     search_path; KNOWN PUBLIC EXECUTE present (unchanged).
--   - C-14: sites-internal read RPCs (4) SECURITY DEFINER / owner postgres / fixed
--     search_path; create_invoice_secure / update_invoice_secure KNOWN PUBLIC EXECUTE.
--   - C-15: active sites 10, active_assignment_count total 11, some active sites have 0.
--   - C-16: active assignments 11, no (site_id, employee_id) duplicate.
--
-- [ROLLBACK] (commented section at the end -- NOT executed)
--   DROP FUNCTION for exactly the 5 functions this file adds. Additive-only, so dropping
--   them fully reverses this step (front-end not yet migrated; nothing depends on them).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body. Any STOP condition -> stop.
-- ============================================================

-- P-1. sites / site_assignments table attributes.
--    Expected: 2 rows, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres (both). STOP if a table is missing or anything differs.
select
  n.nspname                   as schema_name,
  c.relname                   as table_name,
  c.relkind                   as relkind,          -- expected 'r'
  c.relrowsecurity            as rls_enabled,      -- expected true
  c.relforcerowsecurity       as rls_forced,       -- expected false  (STOP if true)
  pg_get_userbyid(c.relowner) as owner             -- expected postgres
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- P-2. anon / authenticated table grants (both tables).
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false, for both roles on both tables.
--    NOTE: 'MAINTAIN' needs PG17+; if it errors on an older server, re-run without it.
select
  v.tbl,
  v.role_name,
  has_table_privilege(v.role_name, v.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, v.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, v.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, v.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, v.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, v.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, v.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, v.tbl, 'MAINTAIN')   as can_maintain
from (
  select tbl, role_name
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
) as v(tbl, role_name)
order by v.tbl, v.role_name;

-- P-2b. SELECT ACL / PUBLIC / grant option (both tables).
--    Expected: anon SELECT + authenticated SELECT, is_grantable = false; NO PUBLIC row.
select
  c.relname as table_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by c.relname, grantee;

-- P-3. columns / types / NULL / default (both tables).
--    Expected (STOP if the columns the RPCs rely on differ):
--      sites: id uuid NOT NULL, name text NOT NULL, is_active boolean NOT NULL,
--        created_at timestamptz NOT NULL, start_date date NULL, end_date date NULL,
--        location text NULL, company_id uuid NULL, category_id uuid NULL,
--        contract_amount integer NULL.
--      site_assignments: id uuid NOT NULL, site_id uuid NOT NULL,
--        employee_id uuid NOT NULL, is_active boolean NOT NULL,
--        assigned_at timestamptz NOT NULL.
select
  c.relname                            as table_name,
  a.attname                            as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null,
  pg_get_expr(d.adbin, d.adrelid)      as default_expr
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and a.attnum > 0
  and not a.attisdropped
order by c.relname, a.attnum;

-- P-4. constraints (both tables).
--    Expected: sites_pkey(id); sites_company_id_fkey -> companies(id);
--      sites_category_id_fkey -> site_categories(id); site_assignments_pkey(id);
--      site_assignments_site_id_fkey -> sites(id);
--      site_assignments_employee_id_fkey -> employees(id);
--      UNIQUE(site_id, employee_id). All convalidated = true.
select
  rel.relname                     as table_name,
  con.conname                     as constraint_name,
  con.contype                     as type,      -- p=PK, f=FK, u=UNIQUE, c=CHECK
  con.convalidated                as validated, -- expected true
  pg_get_constraintdef(con.oid)   as definition
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname in ('sites', 'site_assignments')
order by rel.relname, con.contype, con.conname;

-- P-5. indexes valid / ready (both tables).
--    Expected: all indisvalid = true, indisready = true; PK + UNIQUE(site_id,employee_id).
select
  rel.relname   as table_name,
  idx.relname   as index_name,
  i.indisvalid  as is_valid,   -- expected true
  i.indisready  as is_ready,   -- expected true
  i.indisunique as is_unique,
  i.indisprimary as is_primary
from pg_index i
join pg_class rel on rel.oid = i.indrelid
join pg_class idx on idx.oid = i.indexrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname in ('sites', 'site_assignments')
order by rel.relname, idx.relname;

-- P-6. all policies (both tables) -- context only; this file changes NO policy.
--    Expected: sites -> sites_read_all(SELECT, {public}, qual true),
--      anon_can_insert_sites(INSERT), anon_can_update_sites(UPDATE);
--      site_assignments -> sa_read(SELECT, {public}, qual true),
--      sa_write(INSERT), sa_update(UPDATE).
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

-- P-7. counts baseline (INVARIANT vs POST-13).
--    Expected: sites total 20 / active 10 / inactive 10 / null 0;
--      site_assignments total 29 / active 11 / inactive 18 / null 0.
select 'sites' as table_name,
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.sites
union all
select 'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments;

-- P-8. integrity (5 checks). Expected: every count = 0. STOP if any is non-zero.
select
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where s.id is null)                                                   as orphan_site_id,
  (select count(*) from public.site_assignments sa
     left join public.employees e on e.id = sa.employee_id
     where e.id is null)                                                   as orphan_employee_id,
  (select count(*) from (
     select site_id, employee_id
     from public.site_assignments
     group by site_id, employee_id
     having count(*) > 1) d)                                               as duplicate_assignment_groups,
  (select count(*) from public.site_assignments sa
     join public.sites s on s.id = sa.site_id
     where sa.is_active = true and s.is_active = false)                    as active_asg_on_inactive_site,
  (select count(*) from public.site_assignments sa
     join public.employees e on e.id = sa.employee_id
     where sa.is_active = true and e.is_active = false)                    as active_asg_on_inactive_employee;

-- P-9. none of the 5 new function names already exists. Expected: 0 rows (MANDATORY).
--    STOP if any row is returned (plain CREATE would otherwise error and roll back).
select p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure');

-- P-10. employee-session verification columns exist (STOP if any missing).
--    Expected: employee_sessions.employee_id uuid / token_hash text / expires_at
--      timestamptz; employees.id uuid / is_active boolean.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id','token_hash','expires_at'))
     or (table_name = 'employees'         and column_name in ('id','is_active'))
      )
order by table_name, column_name;

-- P-11. _verify_management_session(text) attributes + EXECUTE ACL.
--    Expected: 1 row, security_definer = true, volatility 'v', owner postgres,
--      config contains search_path=public, extensions, identity args
--      "session_token_input text". ACL: EXECUTE for postgres / service_role only;
--      no PUBLIC / anon / authenticated EXECUTE. STOP if attributes differ.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as security_definer,   -- expect true
  p.provolatile                             as volatility,         -- expect 'v'
  pg_get_userbyid(p.proowner)               as owner,              -- expect postgres
  p.proconfig                               as config,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_result(p.oid)             as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = '_verify_management_session'
order by grantee;

-- P-12. existing write RPC baseline (5) -- attributes + EXECUTE ACL.
--    Expected: SECURITY DEFINER = true, volatility 'v', owner postgres, fixed
--      search_path. KNOWN: PUBLIC EXECUTE present (baseline only, NOT a stop condition,
--      NOT modified here). STOP only if an attribute other than the known PUBLIC EXECUTE
--      differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- P-13. sites-internal read RPC baseline (4) -- attributes + EXECUTE ACL.
--    Expected: SECURITY DEFINER = true, owner postgres, fixed search_path. KNOWN:
--      create_invoice_secure / update_invoice_secure have PUBLIC EXECUTE (baseline only,
--      NOT a stop condition, NOT modified here).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;


-- ============================================================
-- EXECUTION BODY
--   NOTE: first place that modifies DB state. Run ONLY after PRE-CHECK P-1..P-13 are
--         confirmed with no STOP condition hit (especially P-9 = 0 rows).
--   NOTE: additive only -- five plain CREATE FUNCTION statements (NOT CREATE OR REPLACE)
--         plus owner / EXECUTE settings on those NEW functions. No table grant, no RLS,
--         no policy, no existing routine is touched.
--   NOTE: FIRST-run only (NOT idempotent as a whole). One transaction (BEGIN..COMMIT):
--         a failure on any function rolls back the entire step.
--   Execution order per function: CREATE -> ALTER OWNER -> REVOKE PUBLIC -> GRANT.
-- ============================================================

BEGIN;

-- 1) list_sites_secure (employee session, index.html loadSites)
--   Employee-session inline verification (same as list_subcontractors_secure):
--   token_hash = encode(digest(session_token_input,'sha256'),'hex'), expires_at > now(),
--   employees.is_active = true; invalid/expired -> RAISE 'Invalid or expired session'.
--   Returns active sites, columns the worker screen uses (id/name/company_id/location/
--   start_date/end_date), ordered by name, id.
CREATE FUNCTION public.list_sites_secure(
  session_token_input text
)
RETURNS TABLE (
  id         uuid,
  name       text,
  company_id uuid,
  location   text,
  start_date date,
  end_date   date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  RETURN QUERY
    SELECT s.id, s.name, s.company_id, s.location, s.start_date, s.end_date
    FROM   public.sites s
    WHERE  s.is_active = true
    ORDER  BY s.name, s.id;
END;
$$;

ALTER  FUNCTION public.list_sites_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_sites_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_sites_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_sites_secure(text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.list_sites_secure(text) TO service_role;


-- 2) list_site_assignments_secure (employee session, index.html loadSiteAssignments)
--   Same inline verification. Returns ALL active assignments (site_id, employee_id),
--   ordered by site_id, employee_id. Inactive assignments are NOT returned.
CREATE FUNCTION public.list_site_assignments_secure(
  session_token_input text
)
RETURNS TABLE (
  site_id     uuid,
  employee_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  RETURN QUERY
    SELECT sa.site_id, sa.employee_id
    FROM   public.site_assignments sa
    WHERE  sa.is_active = true
    ORDER  BY sa.site_id, sa.employee_id;
END;
$$;

ALTER  FUNCTION public.list_site_assignments_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_site_assignments_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_secure(text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_secure(text) TO service_role;


-- 3) list_sites_admin_secure (management session, admin startApp/pageSites + genka startApp)
--   Management-session verification via the existing helper (raises on invalid).
--   Returns active sites plus active_assignment_count (correlated scalar subquery, so
--   no row duplication; sites with 0 active assignments return 0), ordered by name, id.
CREATE FUNCTION public.list_sites_admin_secure(
  session_token_input text
)
RETURNS TABLE (
  id                      uuid,
  name                    text,
  company_id              uuid,
  location                text,
  start_date              date,
  end_date                date,
  active_assignment_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT
      s.id,
      s.name,
      s.company_id,
      s.location,
      s.start_date,
      s.end_date,
      (SELECT count(*)
         FROM public.site_assignments sa
        WHERE sa.site_id = s.id
          AND sa.is_active = true) AS active_assignment_count
    FROM public.sites s
    WHERE s.is_active = true
    ORDER BY s.name, s.id;
END;
$$;

ALTER  FUNCTION public.list_sites_admin_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_sites_admin_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_sites_admin_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_sites_admin_secure(text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.list_sites_admin_secure(text) TO service_role;


-- 4) get_site_admin_secure (management session, admin openSiteModal single fetch)
--   Management-session verification. Returns the single site by id with NO is_active
--   filter (active OR inactive), matching the current
--   `.from('sites').select('*').eq('id', siteId).single()`. Non-existent id -> 0 rows
--   (the front-end applies .single()-equivalent to preserve current not-found behaviour).
CREATE FUNCTION public.get_site_admin_secure(
  session_token_input text,
  site_id_input       uuid
)
RETURNS TABLE (
  id         uuid,
  name       text,
  company_id uuid,
  location   text,
  start_date date,
  end_date   date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT s.id, s.name, s.company_id, s.location, s.start_date, s.end_date
    FROM   public.sites s
    WHERE  s.id = site_id_input;
END;
$$;

ALTER  FUNCTION public.get_site_admin_secure(text, uuid) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.get_site_admin_secure(text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_site_admin_secure(text, uuid) TO anon;
GRANT  EXECUTE ON FUNCTION public.get_site_admin_secure(text, uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.get_site_admin_secure(text, uuid) TO service_role;


-- 5) list_site_assignments_admin_secure (management session, admin openSiteModal)
--   Management-session verification. Returns the active employee_id list for one site,
--   ordered by employee_id. Non-existent site or no active assignments -> 0 rows.
--   No site-existence check is added (read-only).
CREATE FUNCTION public.list_site_assignments_admin_secure(
  session_token_input text,
  site_id_input       uuid
)
RETURNS TABLE (
  employee_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public._verify_management_session(session_token_input);

  RETURN QUERY
    SELECT sa.employee_id
    FROM   public.site_assignments sa
    WHERE  sa.site_id = site_id_input
      AND  sa.is_active = true
    ORDER  BY sa.employee_id;
END;
$$;

ALTER  FUNCTION public.list_site_assignments_admin_secure(text, uuid) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_site_assignments_admin_secure(text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_admin_secure(text, uuid) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_admin_secure(text, uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.list_site_assignments_admin_secure(text, uuid) TO service_role;

-- Commit all five CREATE FUNCTION statements plus their owner / EXECUTE settings as one
-- atomic unit. If anything above failed (incl. a "function already exists" collision),
-- roll back instead.
COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- POST-1. All 5 functions exist exactly once each; no unexpected overload.
--    Expected: 5 rows (one signature per name).
select
  p.proname,
  count(*) as overloads,
  string_agg(p.oid::regprocedure::text, ' | ' order by p.oid) as signatures
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
group by p.proname
order by p.proname;

-- POST-2. Attributes: SECURITY DEFINER = true, STABLE ('s'), owner postgres, fixed
--    search_path. Expected: 5 rows, is_security_definer = true, volatility = 's',
--    owner = postgres, config contains search_path=public, extensions.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's'
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;

-- POST-3. Identity arguments (input signature).
--    Expected: list_sites_secure / list_site_assignments_secure / list_sites_admin_secure
--      = "session_token_input text"; get_site_admin_secure /
--      list_site_assignments_admin_secure = "session_token_input text, site_id_input uuid".
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;

-- POST-4. RETURNS TABLE columns, correct ordinal from 1 (per function).
--    Uses row_number() over (partition by p.oid order by t.ord) so the input arguments
--    in proargtypes ordinality do NOT shift the OUT-column numbering.
--    Expected:
--      list_sites_secure: 1 id uuid, 2 name text, 3 company_id uuid, 4 location text,
--        5 start_date date, 6 end_date date.
--      list_site_assignments_secure: 1 site_id uuid, 2 employee_id uuid.
--      list_sites_admin_secure: 1 id uuid, 2 name text, 3 company_id uuid, 4 location text,
--        5 start_date date, 6 end_date date, 7 active_assignment_count bigint.
--      get_site_admin_secure: 1 id uuid, 2 name text, 3 company_id uuid, 4 location text,
--        5 start_date date, 6 end_date date.
--      list_site_assignments_admin_secure: 1 employee_id uuid.
select
  p.proname,
  row_number() over (
    partition by p.oid
    order by t.ord
  ) as return_ordinal,
  t.argname                    as out_column,
  format_type(t.argtype, null) as out_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
  with ordinality as t(argtype, argmode, argname, ord)
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by p.proname, return_ordinal;

-- POST-5. Effective EXECUTE for anon / authenticated / service_role / postgres = true
--    on all 5 functions.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_sites_secure(text)',                        'EXECUTE') as list_sites,
  has_function_privilege(v.grantee, 'public.list_site_assignments_secure(text)',             'EXECUTE') as list_sa,
  has_function_privilege(v.grantee, 'public.list_sites_admin_secure(text)',                  'EXECUTE') as list_sites_admin,
  has_function_privilege(v.grantee, 'public.get_site_admin_secure(text, uuid)',              'EXECUTE') as get_site_admin,
  has_function_privilege(v.grantee, 'public.list_site_assignments_admin_secure(text, uuid)', 'EXECUTE') as list_sa_admin
from (values ('anon'), ('authenticated'), ('service_role'), ('postgres')) as v(grantee)
order by v.grantee;

-- POST-6. Explicit ACL rows: exactly postgres / anon / authenticated / service_role with
--    EXECUTE, is_grantable = false, explicit (proacl non-NULL); NO PUBLIC row.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable,
  (p.proacl is not null) as has_explicit_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname, grantee, acl.privilege_type;

-- POST-7. PUBLIC EXECUTE absent on all 5 functions. Expected: 0 rows.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- POST-8. sites / site_assignments table attributes UNCHANGED (mirror P-1).
select
  c.relname                   as table_name,
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- POST-9. anon / authenticated table privileges UNCHANGED (mirror P-2:
--    SELECT = true; other 7 = false, both tables).
select
  v.tbl,
  v.role_name,
  has_table_privilege(v.role_name, v.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, v.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, v.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, v.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, v.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, v.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, v.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, v.tbl, 'MAINTAIN')   as can_maintain
from (
  select tbl, role_name
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
) as v(tbl, role_name)
order by v.tbl, v.role_name;

-- POST-10. SELECT ACL UNCHANGED (mirror P-2b: anon + authenticated SELECT, no PUBLIC).
select
  c.relname as table_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by c.relname, grantee;

-- POST-11. policies UNCHANGED (mirror P-6: sites 3 / site_assignments 3, none added,
--    dropped, or altered).
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

-- POST-12. counts UNCHANGED (mirror P-7): sites 20/10/10/0; site_assignments 29/11/18/0.
select 'sites' as table_name,
  count(*) as total,
  count(*) filter (where is_active = true)  as active,
  count(*) filter (where is_active = false) as inactive,
  count(*) filter (where is_active is null) as null_active
from public.sites
union all
select 'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments;

-- POST-13. integrity UNCHANGED (mirror P-8: all 0).
select
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where s.id is null)                                                   as orphan_site_id,
  (select count(*) from public.site_assignments sa
     left join public.employees e on e.id = sa.employee_id
     where e.id is null)                                                   as orphan_employee_id,
  (select count(*) from (
     select site_id, employee_id
     from public.site_assignments
     group by site_id, employee_id
     having count(*) > 1) d)                                               as duplicate_assignment_groups,
  (select count(*) from public.site_assignments sa
     join public.sites s on s.id = sa.site_id
     where sa.is_active = true and s.is_active = false)                    as active_asg_on_inactive_site,
  (select count(*) from public.site_assignments sa
     join public.employees e on e.id = sa.employee_id
     where sa.is_active = true and e.is_active = false)                    as active_asg_on_inactive_employee;

-- POST-14. existing write RPC baseline UNCHANGED (mirror P-12). KNOWN PUBLIC EXECUTE
--    remains as-is (NOT modified by this file).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- POST-15. sites-internal read RPC baseline UNCHANGED (mirror P-13). KNOWN PUBLIC
--    EXECUTE on create_invoice_secure / update_invoice_secure remains as-is.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- POST-16. _verify_management_session(text) UNCHANGED (mirror P-11): SECURITY DEFINER,
--    VOLATILE, owner postgres, fixed search_path, no PUBLIC/anon/authenticated EXECUTE.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   (a) NEGATIVE checks -- run in the SQL Editor with a bogus token. Each new RPC must
--       RAISE 'Invalid or expired session'. The DO blocks below catch ONLY the expected
--       raise (sqlstate P0001) around the call, then FAIL loudly OUTSIDE that inner
--       block if no raise occurred -- so a self-generated "SMOKE FAIL" is never swallowed
--       by a WHEN OTHERS. (No WHEN OTHERS is used.)
--
--       -- employee RPCs (invalid employee session) --
DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_sites_secure('smoke-invalid-token');
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_sites_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_sites_secure rejected invalid token';
END $$;

DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_site_assignments_secure('smoke-invalid-token');
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_site_assignments_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_site_assignments_secure rejected invalid token';
END $$;

--       -- management RPCs (invalid management session) --
DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_sites_admin_secure('smoke-invalid-token');
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_sites_admin_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_sites_admin_secure rejected invalid token';
END $$;

DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.get_site_admin_secure('smoke-invalid-token',
                                                '00000000-0000-0000-0000-000000000000'::uuid);
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: get_site_admin_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: get_site_admin_secure rejected invalid token';
END $$;

DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_site_assignments_admin_secure('smoke-invalid-token',
                                                '00000000-0000-0000-0000-000000000000'::uuid);
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_site_assignments_admin_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_site_assignments_admin_secure rejected invalid token';
END $$;

--   (b) POSITIVE checks -- require VALID session tokens. Do NOT paste any real token into
--       this file or the run log. Run these in the browser DevTools Console of a
--       logged-in app session, or in the SQL Editor with a token pasted at run time only.
--       Expected (per C-7 / C-15 / C-16 baseline):
--         - list_sites_secure               -> 10 rows (active sites), cols id/name/
--                                              company_id/location/start_date/end_date.
--         - list_site_assignments_secure    -> 11 rows (active assignments).
--         - list_sites_admin_secure         -> 10 rows; sum(active_assignment_count) = 11.
--         - get_site_admin_secure(<id>)     -> exactly 1 row for an existing id
--                                              (0 rows for a non-existent id).
--         - list_site_assignments_admin_secure(<site_id>) -> that site's active
--                                              assignment count (matches baseline).
--
--       -- SQL Editor examples (replace <...> at run time; never save a real token) --
--       select count(*) from public.list_sites_secure('<valid employee token>');                 -- expect 10
--       select count(*) from public.list_site_assignments_secure('<valid employee token>');       -- expect 11
--       select count(*) from public.list_sites_admin_secure('<valid management token>');           -- expect 10
--       select coalesce(sum(active_assignment_count),0)
--         from public.list_sites_admin_secure('<valid management token>');                         -- expect 11
--       select count(*) from public.get_site_admin_secure('<valid management token>', '<site id>');-- expect 1
--       select count(*) from public.list_site_assignments_admin_secure('<valid management token>', '<site id>');
--
--       -- browser Console example (employee app; anon key context, valid session) --
--       // const t = state.currentUser.session_token;
--       // console.log((await sb.rpc('list_sites_secure',{session_token_input:t})).data?.length);
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; NOT executed -- reference only)
--   Removes exactly the five functions this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on them yet. Touches NO table
--   grant, NO policy, NO existing RPC.
-- ============================================================
-- DROP FUNCTION public.list_sites_secure(text);
-- DROP FUNCTION public.list_site_assignments_secure(text);
-- DROP FUNCTION public.list_sites_admin_secure(text);
-- DROP FUNCTION public.get_site_admin_secure(text, uuid);
-- DROP FUNCTION public.list_site_assignments_admin_secure(text, uuid);
-- ============================================================
