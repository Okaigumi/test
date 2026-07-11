-- ============================================================
-- Phase 4-F-2B-5: add secure read RPCs for public.machines
--   (list_machines_secure / list_machines_admin_secure) so that index.html,
--   admin-app.html and genka-app.html can stop reading the machines table
--   directly.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-11)
--   - This file ONLY adds two new read RPCs (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--
--   [DB EXECUTION] (Supabase SQL Editor, by the user, 2026-07-11)
--     - The user ran the EXECUTION BODY manually in the Supabase SQL Editor.
--     - Result: Success. No rows returned.
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--
--   [PRE-CHECK RESULT] (C-1..C-9, Supabase SQL Editor, 2026-07-11 -- all passed)
--     - C-1: machines exists, schema = public, relkind = 'r', RLS = true,
--       FORCE RLS = false, owner = postgres.
--     - C-2: anon / authenticated SELECT = true;
--       anon / authenticated INSERT / UPDATE / DELETE = false.
--     - C-3: all 9 columns assumed by the RETURNS TABLE declarations exist with
--       matching types (id uuid, name text, company_id uuid, ownership text,
--       lease_company text, lease_start date, lease_end date,
--       lease_monthly integer, is_active boolean).
--     - C-4: 3 policies recorded -- machines_read_all / machines_update /
--       machines_write (context only; left untouched by this file).
--     - C-5: all 5 employee-session verification columns exist
--       (employee_sessions.employee_id / token_hash / expires_at,
--        employees.id / is_active).
--     - C-6: _verify_management_session(text) exists, SECURITY DEFINER = true,
--       owner = postgres, search_path = public, extensions.
--     - C-7: list_machines_secure / list_machines_admin_secure did not exist
--       beforehand (0 rows).
--     - C-8: machines counts -- total = 26, active = 22, inactive = 4,
--       null_active = 0.
--     - C-9: all 5 existing machines write RPCs present, attributes confirmed
--       (baseline snapshot for P-6).
--
--   [POST-CHECK RESULT] (P-1..P-6, Supabase SQL Editor, 2026-07-11 -- all passed)
--     - P-1: both new RPCs exist; SECURITY DEFINER = true; STABLE
--       (provolatile = 's'); owner = postgres; search_path = public, extensions.
--     - P-2: return types as declared -- list_machines_secure(text): 7 TABLE
--       columns; list_machines_admin_secure(text, boolean): 9 TABLE columns.
--     - P-3: anon EXECUTE = true, authenticated EXECUTE = true (both functions).
--     - P-3b: PUBLIC EXECUTE = none.
--     - P-4: machines table grants unchanged from the C-2 snapshot.
--     - P-5: RLS / FORCE RLS unchanged; policy list unchanged (3 policies,
--       identical to the C-4 snapshot).
--     - P-6: all 5 existing machines write RPCs unchanged from the C-9 snapshot.
--
--   [SMOKE TEST RESULT] (valid employee / management sessions, 2026-07-11)
--     - employee RPC (list_machines_secure): error = null, count = 22;
--       existing active direct read count = 22; sameRows = true (set equality).
--     - admin RPC (list_machines_admin_secure):
--         include_inactive = false -> error = null, count = 22.
--         include_inactive = true  -> error = null, count = 26.
--         include_inactive = null  -> error = null, count = 22.
--     - No real session token value is recorded here.
--
--   [STILL NOT DONE] (separate, later steps)
--     - front-end migration (index.html loadMachineLocations, admin-app.html
--       startApp / pageMachines / openMachineModal, genka-app.html startApp).
--     - machines direct read shutdown (the five direct reads are still live).
--     - REVOKE SELECT ON public.machines FROM anon, authenticated (NOT performed;
--       SELECT is still granted).
--     - DROP POLICY machines_read_all (NOT performed; the policy still exists).
--     - front-end Preview check / production screen check (not performed; the
--       front-end has not been migrated yet).
--
-- [PURPOSE]
--   The three front-ends currently read public.machines via direct SELECTs:
--     - index.html:2062      loadMachineLocations : select('*').eq('is_active',true).order('name')
--     - admin-app.html:331   startApp             : select('*').eq('is_active',true).order('name')
--     - admin-app.html:1457  pageMachines         : select('*').order('name')          (ALL rows, incl. inactive)
--     - admin-app.html:1499  openMachineModal     : select('*').eq('id',machineId).single()
--     - genka-app.html:534   startApp             : select('*').eq('is_active',true)
--   This step adds two SECURITY DEFINER read RPCs following the standard 3-stage
--   migration (read RPC -> front-end move -> direct read shutdown), matching
--   phase4f-2b-4-materials-read-rpc.sql (employee session) and
--   phase4f-2b-4-companies-read-rpc.sql (management session):
--
--     1. list_machines_secure(text)
--        - employee-session-verified (same inline verification as
--          list_materials_secure), for index.html (worker screen).
--        - returns ACTIVE machines only, with the columns the worker screen
--          actually uses: id, name, ownership, lease_company, lease_start,
--          lease_end, lease_monthly.
--
--     2. list_machines_admin_secure(text, boolean DEFAULT false)
--        - management-session-verified via the existing helper
--          public._verify_management_session(text) (same as list_companies_secure /
--          list_unit_rates_secure, which are already called from BOTH
--          admin-app.html and genka-app.html), for admin-app.html and
--          genka-app.html.
--        - include_inactive_input = false (or NULL) -> active machines only.
--        - include_inactive_input = true            -> all machines incl. inactive
--          (needed by admin-app.html pageMachines, which lists inactive machines
--          with an is_active badge).
--        - returns id, name, company_id, ownership, lease_company, lease_start,
--          lease_end, lease_monthly, is_active.
--
--   created_at is NOT returned by either RPC: no front-end reads machines.created_at
--   (verified read-only against index.html / admin-app.html / genka-app.html).
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration of the five direct reads listed above,
--     - any REVOKE on the machines table,
--     - any policy change / DROP POLICY on machines (including, if present, policies
--       such as machines_read_all / machines_update / machines_write -- whatever the
--       pre-check finds is left untouched).
--
-- [SCOPE]
--   Add TWO functions:
--     - public.list_machines_secure(session_token_input text)
--     - public.list_machines_admin_secure(session_token_input text,
--                                         include_inactive_input boolean DEFAULT false)
--   Set owner and EXECUTE privileges on those NEW functions only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - index.html / admin-app.html / genka-app.html (front-end migration is a later step).
--   - public.machines table grants (whatever the pre-check finds stays as-is).
--   - machines policies (NO change, NO drop).
--   - RLS / FORCE RLS on machines.
--   - machines data.
--   - existing machines write RPCs (create_machine_secure / update_machine_secure /
--     deactivate_machine_secure / create_machine_admin_secure /
--     update_machine_admin_secure) and their EXECUTE grants.
--   - public._verify_management_session(text) (reused as-is; NOT modified).
--   - machine_locations (its direct reads in index.html are a separate backlog item).
--   - any other table / role / privilege.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - C-1: machines missing, not an ordinary table, RLS not enabled, or owner not
--          postgres -> STOP.
--   - C-3: machines column set / types do not match the RETURNS TABLE assumptions
--          below (id uuid, name text, company_id uuid, ownership text,
--          lease_company text, lease_start date, lease_end date,
--          lease_monthly integer, is_active boolean) -> STOP (return-type / filter
--          assumptions broken; reconcile the declared types first).
--   - C-5: employee_sessions (employee_id / token_hash / expires_at) or employees
--          (id / is_active) verification columns missing -> STOP.
--   - C-6: _verify_management_session(text) missing, not SECURITY DEFINER, or owner
--          not postgres -> STOP.
--   - C-7: public.list_machines_secure(text) or
--          public.list_machines_admin_secure(text, boolean) already exists -> STOP
--          and reconcile (this file uses CREATE OR REPLACE, but an unexpected
--          pre-existing function means the environment differs from the assumed
--          state).
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   The commented DROP FUNCTION statements remove exactly the two functions this
--   file adds. Because this file is additive and touches no grant / policy / table,
--   dropping the new functions fully reverses this step (the front-end has not yet
--   been migrated at this stage, so nothing depends on them).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run by the user in the Supabase SQL Editor BEFORE the body (2026-07-11).
--   Results are recorded in [PRE-CHECK RESULT] in the header above; the queries
--   are kept re-runnable.
-- ============================================================

-- C-1. machines existence + relkind + RLS state + owner.
--    Expected: table exists, relkind = 'r', rls_enabled = true, rls_forced = false,
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
  and c.relname = 'machines';

-- C-2. anon / authenticated effective privileges on machines (context; unchanged here).
--    Record the result; this file does NOT change it.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machines', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.machines', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.machines', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.machines', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. machines columns exist with the exact types assumed by the RETURNS TABLE
--    declarations below.
--    Expected: id uuid, name text, company_id uuid, ownership text,
--      lease_company text, lease_start date, lease_end date,
--      lease_monthly integer, is_active boolean.
--    STOP if any column is missing or its type differs from the RETURNS TABLE
--    assumptions (reconcile the declared types first).
select
  a.attname     as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type
from pg_attribute a
where a.attrelid = 'public.machines'::regclass
  and a.attnum > 0
  and not a.attisdropped
  and a.attname in ('id', 'name', 'company_id', 'ownership', 'lease_company',
                    'lease_start', 'lease_end', 'lease_monthly', 'is_active')
order by a.attname;

-- C-4. machines pg_policies (context; unchanged here).
--    Record the result; this file does NOT drop or alter any policy.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machines'
order by cmd, policyname;

-- C-5. employee_sessions / employees verification columns exist
--    (same assumptions as list_materials_secure).
--    STOP if any of these verification columns is missing.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id', 'token_hash', 'expires_at'))
     or (table_name = 'employees'         and column_name in ('id', 'is_active'))
      )
order by table_name, column_name;

-- C-6. _verify_management_session(text): existence + SECURITY DEFINER + owner +
--    fixed search_path (reused as-is by list_machines_admin_secure; NOT modified).
--    Expected: 1 row, security_definer = true, owner = postgres,
--      config contains search_path=public, extensions.
--    STOP if missing, not SECURITY DEFINER, or owner not postgres.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';

-- C-7. Neither new function already exists.
--    Expected: 0 rows.
--    STOP if a row is returned (unexpected pre-existing function; reconcile first).
select
  p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure');

-- C-8. machines counts (context for the post-check row-count check).
--    Record total / active / inactive / null_active.
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.machines;

-- C-9. existing machines write RPCs are present (baseline for "did not break them").
--    Record the result; this file does NOT alter them.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_machine_secure', 'update_machine_secure',
                    'deactivate_machine_secure', 'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (C-1..C-9) are confirmed with no STOP condition hit.
--   NOTE: additive only -- two CREATE OR REPLACE FUNCTION statements plus
--         owner / EXECUTE settings on those NEW functions. No table grant, no RLS,
--         no policy, no existing routine is touched.
--   Execution order per function: CREATE -> ALTER OWNER -> REVOKE PUBLIC -> GRANT.
-- ============================================================

-- 1) list_machines_secure
--   Verify an employee session inline (invalid / expired raises), then return active
--   machines ordered by name. For the columns the worker screen uses, behaviour is
--   equivalent to the current direct SELECT
--   `select('*').eq('is_active', true).order('name')` (index.html:2062).
--
--   Authorization method (matches the existing employee-session read RPCs, e.g.
--   list_materials_secure in phase4f-2b-4-materials-read-rpc.sql):
--     - no shared helper is introduced; employee_sessions is referenced inline,
--     - token_hash = encode(digest(session_token_input, 'sha256'), 'hex'),
--     - expires_at > now(),
--     - employees is JOINed and is_active = true is confirmed,
--     - the employee_id is derived server-side from the session token (never taken
--       from the client),
--     - an invalid / expired session RAISEs 'Invalid or expired session'.
CREATE OR REPLACE FUNCTION public.list_machines_secure(
  session_token_input text
)
RETURNS TABLE (
  id            uuid,
  name          text,
  ownership     text,
  lease_company text,
  lease_start   date,
  lease_end     date,
  lease_monthly integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  -- Authorization: derive employee_id from the session token (employees JOIN with
  -- is_active = true). Invalid / expired session -> raise.
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
    SELECT m.id, m.name, m.ownership, m.lease_company,
           m.lease_start, m.lease_end, m.lease_monthly
    FROM   public.machines m
    WHERE  m.is_active = true
    ORDER  BY m.name;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only).
ALTER  FUNCTION public.list_machines_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_machines_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_machines_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_machines_secure(text) TO authenticated;


-- 2) list_machines_admin_secure
--   Verify a management session via the existing helper (invalid / expired raises
--   inside the helper), then return machines ordered by name.
--     - include_inactive_input = false or NULL -> active machines only
--       (admin-app.html startApp replacement scope / genka-app.html startApp).
--     - include_inactive_input = true          -> all machines incl. inactive
--       (admin-app.html pageMachines, which shows the is_active badge).
--   The helper public._verify_management_session(text) is the same one already used
--   by list_companies_secure / list_unit_rates_secure, both of which are called from
--   admin-app.html AND genka-app.html management sessions.
CREATE OR REPLACE FUNCTION public.list_machines_admin_secure(
  session_token_input    text,
  include_inactive_input boolean DEFAULT false
)
RETURNS TABLE (
  id            uuid,
  name          text,
  company_id    uuid,
  ownership     text,
  lease_company text,
  lease_start   date,
  lease_end     date,
  lease_monthly integer,
  is_active     boolean
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
    SELECT m.id, m.name, m.company_id, m.ownership, m.lease_company,
           m.lease_start, m.lease_end, m.lease_monthly, m.is_active
    FROM   public.machines m
    WHERE  COALESCE(include_inactive_input, false) = true
       OR  m.is_active = true
    ORDER  BY m.name;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only).
ALTER  FUNCTION public.list_machines_admin_secure(text, boolean) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_machines_admin_secure(text, boolean) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_machines_admin_secure(text, boolean) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_machines_admin_secure(text, boolean) TO authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
--   Consolidated where possible to reduce the number of manual runs.
-- ============================================================

-- P-1. Both functions exist exactly once each, with the expected attributes:
--    SECURITY DEFINER, STABLE (provolatile = 's'), owner postgres, fixed search_path.
--    Expected: 2 rows, is_security_definer = true, volatility = 's',
--      owner = postgres, config contains search_path=public, extensions.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config                 -- expect search_path=public, extensions
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
order by p.proname;

-- P-2. Return types.
--    Expected for list_machines_secure(text): 7 TABLE columns --
--      (id uuid, name text, ownership text, lease_company text, lease_start date,
--       lease_end date, lease_monthly integer).
--    Expected for list_machines_admin_secure(text, boolean): 9 TABLE columns --
--      (id uuid, name text, company_id uuid, ownership text, lease_company text,
--       lease_start date, lease_end date, lease_monthly integer, is_active boolean).
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
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by p.proname, t.ord;

-- P-3. EXECUTE privileges: anon = true, authenticated = true (both functions).
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machines_secure(text)',                'EXECUTE') as can_execute_employee_rpc,
  has_function_privilege(v.grantee, 'public.list_machines_admin_secure(text, boolean)', 'EXECUTE') as can_execute_admin_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-3b. PUBLIC EXECUTE is not present in either function ACL.
--    Expected: 0 rows for grantee = PUBLIC (= 0 in acl) with EXECUTE.
select
  p.proname,
  acl.grantee::regrole::text as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
  and acl.grantee = 0    -- 0 = PUBLIC
order by p.proname, acl.privilege_type;

-- P-4. machines table grants UNCHANGED from the C-2 pre-check snapshot.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machines', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.machines', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.machines', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.machines', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-5. machines RLS / FORCE RLS UNCHANGED, and the policy list UNCHANGED from the
--    C-4 pre-check snapshot (no policy added / dropped / altered).
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'machines') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'machines';

select
  policyname, permissive, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machines'
order by cmd, policyname;

-- P-6. Existing machines write RPCs UNCHANGED from the C-9 pre-check snapshot.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_machine_secure', 'update_machine_secure',
                    'deactivate_machine_secure', 'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;

-- P-7. RPC results match the machines table (row-count / set equality checks).
--    NOTE: requires VALID session tokens; run in the SMOKE TEST step.
--    (Replace <...> with real, valid tokens at run time; do NOT paste any real token
--     into this file.)
--
--   -- employee RPC vs active machines (expect 0 rows both ways):
--   with rpc as (
--     select id, name from public.list_machines_secure('<valid employee session token>')
--   ),
--   src as (
--     select id, name from public.machines where is_active = true
--   )
--   select 'rpc_only' as side, id, name from (select * from rpc except select * from src) d
--   union all
--   select 'src_only' as side, id, name from (select * from src except select * from rpc) d;
--
--   -- admin RPC, active only (expect count = C-8 active):
--   select count(*) from public.list_machines_admin_secure('<valid management session token>', false);
--
--   -- admin RPC, all rows (expect count = C-8 total):
--   select count(*) from public.list_machines_admin_secure('<valid management session token>', true);
--
--   -- admin RPC, NULL treated as false (expect count = C-8 active):
--   select count(*) from public.list_machines_admin_secure('<valid management session token>', null);
-- Any machines table REVOKE / policy change is NOT performed by this file and is
-- subject to a separate, later decision. P-4 / P-5 above confirm this file did not
-- change them.


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER running the body)
--   NOTE: this step is ADDITIVE. The front-end has NOT been migrated yet, so the
--         live screens still use the direct SELECTs and must keep working exactly
--         as before. The two new RPCs exist but are not yet called by any screen --
--         screen confirmation happens in the next (front-end migration) step, NOT
--         here.
--   - Employee RPC: with a VALID employee session token, run
--       select * from public.list_machines_secure('<valid employee session token>');
--     It must return the active machines (7 columns) ordered by name.
--   - Management RPC: with a VALID management session token (admin-app or genka-app),
--     run the three P-7 count checks (false / true / null).
--   - Negative checks: an invalid / expired token must raise on both functions, e.g.
--       select * from public.list_machines_secure('not-a-real-token');
--       select * from public.list_machines_admin_secure('not-a-real-token', false);
--   - Do NOT record any real session token value in this file or in the run log.
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Removes exactly the two functions this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on them yet.
-- ============================================================
-- DROP FUNCTION public.list_machines_secure(text);
-- DROP FUNCTION public.list_machines_admin_secure(text, boolean);
-- ============================================================
