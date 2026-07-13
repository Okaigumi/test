-- ============================================================
-- Phase 4-F-2B-7: add secure read RPCs for public.subcontractors
--   (list_subcontractors_secure / list_subcontractors_admin_secure) so that
--   index.html and genka-app.html can stop reading the subcontractors table
--   directly (admin-app.html's direct read is dead code and will simply be
--   removed in the front-end step).
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file ONLY adds two new read RPCs (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--
--   [PRE-CHECK RESULT] (C-1..C-12, Supabase SQL Editor, 2026-07-13 -- all passed,
--    measured by the user BEFORE this file was written)
--     - C-1: subcontractors exists, schema = public, relkind = 'r', RLS = true,
--       FORCE RLS = false, owner = postgres.
--     - C-2: anon / authenticated SELECT = true;
--       INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN =
--       false for both roles. (context only; left untouched by this file.)
--     - C-2b: ACL -- anon = SELECT only, authenticated = SELECT only, no PUBLIC
--       grant, no grant option.
--     - C-3: columns / types as assumed --
--       id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL,
--       is_active boolean NOT NULL DEFAULT true,
--       created_at timestamptz NOT NULL DEFAULT now(), company_id uuid NULL.
--       The front-end consumes only id / name.
--     - C-4: PK = subcontractors_pkey(id) (unique / valid / ready);
--       FK company_id -> companies(id); all constraints validated.
--     - C-5: policy count = 1 -- sub_read (PERMISSIVE, roles {public}, SELECT,
--       USING true, no WITH CHECK). (context only; left untouched by this file.)
--     - C-6: all employee-session verification columns exist
--       (employee_sessions.employee_id uuid / token_hash text /
--        expires_at timestamptz, employees.id / is_active).
--     - C-7: public._verify_management_session(text) exists, SECURITY DEFINER,
--       owner = postgres, search_path = public, extensions. It verifies BOTH
--       admin sessions and admin-role employee sessions (token hash, expiry,
--       active, admin role) and raises on an invalid session. Reused as-is here.
--     - C-8: list_subcontractors_secure / list_subcontractors_admin_secure did
--       not exist beforehand (0 rows; no name collision).
--     - C-9: existing RPC baseline -- export_projects_summary_secure:
--       SECURITY DEFINER, STABLE, owner postgres, fixed search_path, reads
--       subcontractors read-only, no PUBLIC EXECUTE, EXECUTE for anon /
--       authenticated / postgres / service_role. NOT modified by this file
--       (baseline snapshot for P-7).
--     - C-9b: export_projects_summary_secure EXECUTE ACL (measured) --
--       {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,
--        service_role=X/postgres}; no PUBLIC row; is_grantable = false for all
--       roles; explicit (non-NULL) ACL. (baseline snapshot for P-7b.)
--     - C-10: subcontractors counts -- total = 3, active = 3, inactive = 0,
--       is_active null = 0.
--     - C-11: orphan company_id = 0; orphan ids inside reports.subcontractor_ids = 0.
--     - C-12: subcontractors.name duplicates = 0; all 3 subcontractors have exactly one
--       matching unit_rates row (category = 'subcontractor', name match):
--       大須賀商店 / 岡井重機 / 高瀬興行, each 0円/式 (the 0-yen rates are the
--       intended operation, not an anomaly).
--
--   [STILL NOT DONE] (separate, later steps)
--     - front-end migration:
--         index.html:998   loadSubcontractors  -> list_subcontractors_secure
--         genka-app.html:535 startApp           -> list_subcontractors_admin_secure
--         admin-app.html:330 startApp           -> REMOVE (loaded into
--           _subcontractors but never used anywhere; dead code).
--     - subcontractors direct read shutdown (the three direct reads are still live).
--     - REVOKE SELECT ON public.subcontractors FROM anon, authenticated (NOT
--       performed; SELECT is still granted).
--     - DROP POLICY sub_read (NOT performed; the policy still exists).
--     - front-end Preview check / production screen check (not performed; the
--       front-end has not been migrated yet).
--
-- [PURPOSE]
--   The three front-ends currently read public.subcontractors via direct SELECTs:
--     - index.html:998      loadSubcontractors : select('*').eq('is_active',true).order('name')
--                           (employee session screen; consumes id / name only)
--     - admin-app.html:330  startApp           : select('*').eq('is_active',true).order('name')
--                           (management session; result assigned to _subcontractors
--                            and never used -- dead code, to be removed, not migrated)
--     - genka-app.html:535  startApp           : select('*').eq('is_active',true)
--                           (management session; consumes id / name only)
--   This step adds two SECURITY DEFINER read RPCs following the standard 3-stage
--   migration (read RPC -> front-end move -> direct read shutdown), matching
--   phase4f-2b-5-machines-read-rpc.sql (employee-session inline verification +
--   management-session helper) and phase4f-2b-6-machine-locations-read-rpc.sql
--   (file structure):
--
--     1. list_subcontractors_secure(text)
--        - employee-session-verified (same inline verification as
--          list_machines_secure / list_materials_secure), for index.html.
--        - returns ACTIVE subcontractors only, with the columns the worker screen
--          actually uses: id, name.
--
--     2. list_subcontractors_admin_secure(text)
--        - management-session-verified via the existing helper
--          public._verify_management_session(text) (same as list_companies_secure /
--          list_unit_rates_secure / list_machines_admin_secure), for
--          genka-app.html.
--        - returns ACTIVE subcontractors only, with id, name.
--        - NO include_inactive argument: no screen lists inactive subcontractors
--          (deliberate; can be added later if an admin management screen appears).
--
--   is_active / created_at / company_id are NOT returned by either RPC: no front-end
--   reads them (verified read-only against index.html / admin-app.html /
--   genka-app.html; both direct reads filter is_active server-side already).
--
--   ORDER BY name, id: name is the user-visible order (matches the current
--   index.html direct read's .order('name'); genka-app.html has no explicit order
--   today). id is added as a second key to make the order deterministic even if
--   duplicate names appear in the future (C-12 measured 0 duplicates today).
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration / removal of the three direct reads listed above,
--     - any REVOKE on the subcontractors table (SELECT stays granted),
--     - any policy change / DROP POLICY on subcontractors (sub_read is left exactly
--       as the pre-check found it),
--     - any change to export_projects_summary_secure.
--
-- [SCOPE]
--   Add TWO functions:
--     - public.list_subcontractors_secure(session_token_input text)
--     - public.list_subcontractors_admin_secure(session_token_input text)
--   Set owner and EXECUTE privileges on those NEW functions only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - index.html / admin-app.html / genka-app.html (front-end step comes later).
--   - public.subcontractors table grants (SELECT for anon / authenticated is NOT
--     revoked here).
--   - sub_read policy (NO change, NO drop).
--   - RLS / FORCE RLS on subcontractors.
--   - subcontractors data.
--   - export_projects_summary_secure (reads subcontractors internally as
--     SECURITY DEFINER; reused / unaffected, NOT modified).
--   - public._verify_management_session(text) (reused as-is; NOT modified).
--   - any other table / role / privilege / policy / routine.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [RE-RUN SAFETY]
--   - The body uses plain CREATE FUNCTION (NOT CREATE OR REPLACE). C-8 requires
--     0 pre-existing functions (mandatory); plain CREATE is the SECOND line of
--     defence -- an unexpected pre-existing function makes the body ERROR OUT
--     instead of being silently replaced (fail closed), matching the safe pattern
--     of phase4f-2b-6-machine-locations-read-rpc.sql.
--   - This file is a FIRST-TIME, additive-only creation script. The body runs as
--     ONE transaction (BEGIN ... COMMIT), so the first run is atomic: a failure on
--     either function rolls back the entire step and leaves nothing half-created.
--   - Do NOT re-run the body as-is after it has succeeded: a second run stops with
--     a "function already exists" error and the WHOLE transaction rolls back (no
--     partial changes). If the functions ever need to be re-created, first check
--     the current state and explicitly run the ROLLBACK section (DROP FUNCTION),
--     then run the body again.
--   - ALTER OWNER / REVOKE / GRANT are individually idempotent, but the body as a
--     whole is NOT idempotent (plain CREATE).
--   - PRE-CHECK and POST-CHECK are OUTSIDE this transaction (read-only; run them
--     separately).
--
-- [STOP CONDITIONS] (if any is hit when re-running the pre-check, do NOT run the
--  body; stop & report)
--   - C-1: subcontractors missing, not an ordinary table, RLS not enabled,
--          FORCE RLS enabled, or owner not postgres -> STOP.
--   - C-3: id uuid / name text / is_active boolean missing or of a different
--          type -> STOP (return-type / filter assumptions broken).
--   - C-6: employee_sessions (employee_id / token_hash / expires_at) or employees
--          (id / is_active) verification columns missing -> STOP.
--   - C-7: _verify_management_session(text) missing, not SECURITY DEFINER, or
--          owner not postgres -> STOP.
--   - C-8: public.list_subcontractors_secure(text) or
--          public.list_subcontractors_admin_secure(text) already exists -> STOP
--          and reconcile (C-8 MUST return 0 rows; this file uses plain CREATE
--          FUNCTION -- NOT CREATE OR REPLACE -- so an unexpected pre-existing
--          function makes the body error out instead of silently overwriting it;
--          the environment differs from the assumed additive-only state).
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--   NOTE: C-10..C-12 values are context / reference values only (used by the
--   post-check / smoke-test comparisons); they are NOT stop conditions.
--
-- [ROLLBACK] (see the commented section at the end -- NOT executed)
--   The commented DROP FUNCTION statements remove exactly the two functions this
--   file adds. Because this file is additive and touches no grant / policy / table,
--   dropping the new functions fully reverses this step (the front-end has not yet
--   been migrated at this stage, so nothing depends on them).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Already run by the user in the Supabase SQL Editor (2026-07-13); results are
--   recorded in [PRE-CHECK RESULT] in the header above. The queries are kept
--   re-runnable for verification just before executing the body.
-- ============================================================

-- C-1. subcontractors existence + relkind + RLS state + owner.
--    Expected: 1 row -- relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres.
--    STOP if the table is missing, relkind <> 'r', rls_enabled <> true,
--    rls_forced = true, or owner is not postgres.
select
  n.nspname                   as schema_name,
  c.relname                   as table_name,
  c.relkind                   as relkind,          -- expected 'r'
  c.relrowsecurity            as rls_enabled,      -- expected true
  c.relforcerowsecurity       as rls_forced,       -- expected false
  pg_get_userbyid(c.relowner) as owner             -- expected postgres
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'subcontractors';

-- C-2. anon / authenticated effective privileges on subcontractors
--    (context; this file does NOT change them -- SELECT stays granted).
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false for both roles.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.subcontractors', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.subcontractors', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.subcontractors', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.subcontractors', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.subcontractors', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.subcontractors', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. subcontractors columns exist with the types assumed by the RETURNS TABLE
--    declarations and the WHERE / ORDER BY below.
--    Expected: id uuid NOT NULL, name text NOT NULL, is_active boolean NOT NULL,
--      created_at timestamptz NOT NULL, company_id uuid NULL.
--    STOP if id / name / is_active is missing or its type differs.
select
  a.attname                            as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null
from pg_attribute a
where a.attrelid = 'public.subcontractors'::regclass
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

-- C-5. subcontractors pg_policies (context; unchanged here).
--    Expected: exactly 1 policy -- sub_read (PERMISSIVE, {public}, SELECT,
--      USING true, WITH CHECK null).
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
  and tablename = 'subcontractors'
order by cmd, policyname;

-- C-6. employee_sessions / employees verification columns exist
--    (same assumptions as list_machines_secure / list_materials_secure).
--    STOP if any of these verification columns is missing.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id', 'token_hash', 'expires_at'))
     or (table_name = 'employees'         and column_name in ('id', 'is_active'))
      )
order by table_name, column_name;

-- C-7. _verify_management_session(text): existence + SECURITY DEFINER + owner +
--    fixed search_path (reused as-is by list_subcontractors_admin_secure; NOT
--    modified).
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

-- C-8. Neither new function already exists.
--    Expected: 0 rows (MANDATORY).
--    STOP if a row is returned (unexpected pre-existing function; reconcile first).
--    The body uses plain CREATE FUNCTION as a second line of defence: even if this
--    check were skipped, a pre-existing function makes the body error out (and the
--    whole BEGIN..COMMIT transaction roll back) instead of being silently replaced.
select
  p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure');

-- C-9. export_projects_summary_secure baseline (reads subcontractors internally as
--    SECURITY DEFINER; baseline for "did not break it" -- P-7).
--    Record the result; this file does NOT alter it.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  p.provolatile   as volatility,             -- expected 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure';

-- C-9b. export_projects_summary_secure EXECUTE ACL baseline (for the P-7b
--    "ACL unchanged" comparison). This file does NOT alter it.
--    Expected (measured 2026-07-13):
--      - can_execute = true for anon / authenticated / postgres / service_role,
--      - ACL rows: exactly those 4 grantees with EXECUTE, is_grantable = false,
--      - NO PUBLIC row (grantee oid 0 absent),
--      - the ACL is explicit (proacl is non-NULL), i.e.
--        {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure'
order by v.grantee;

select
  p.proname,
  case
    when acl.grantee = 0 then 'PUBLIC'
    else acl.grantee::regrole::text
  end as grantee,
  acl.privilege_type,
  acl.is_grantable,
  (p.proacl is not null) as has_explicit_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure'
order by grantee, acl.privilege_type;

-- C-10. subcontractors counts (context for the post-check / smoke-test row-count
--    comparison). Measured 2026-07-13: total = 3, active = 3, inactive = 0,
--    null_active = 0. Reference values only (NOT a stop condition).
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.subcontractors;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks above are confirmed with no STOP condition hit.
--   NOTE: additive only -- two plain CREATE FUNCTION statements (NOT CREATE OR
--         REPLACE, so a pre-existing function of the same signature errors out
--         rather than being overwritten -- fail closed) plus owner / EXECUTE
--         settings on those NEW functions. No table grant, no RLS, no policy, no
--         existing routine is touched. C-8 MUST be 0 rows before running this body.
--   NOTE: this body is for the FIRST run only (NOT idempotent as a whole). After
--         it has succeeded, re-running it as-is stops with a "function already
--         exists" error and the WHOLE transaction rolls back (no partial changes).
--         Re-creating the functions requires a state check and an explicit
--         ROLLBACK (DROP FUNCTION; see the section at the end) first.
--   NOTE: the whole body runs as ONE transaction (BEGIN ... COMMIT below), so a
--         failure on either function rolls back the entire step and leaves nothing
--         half-created. PRE-CHECK and POST-CHECK are OUTSIDE this transaction
--         (read-only; run them separately).
--   Execution order per function: CREATE -> ALTER OWNER -> REVOKE PUBLIC -> GRANT.
-- ============================================================

BEGIN;

-- 1) list_subcontractors_secure
--   Verify an employee session inline (invalid / expired raises), then return active
--   subcontractors ordered by name (id as deterministic tie-breaker). For the columns
--   the worker screen uses (id / name), behaviour is equivalent to the current direct
--   SELECT `select('*').eq('is_active', true).order('name')` (index.html:998).
--
--   Authorization method (matches the existing employee-session read RPCs --
--   list_machines_secure in phase4f-2b-5-machines-read-rpc.sql /
--   list_materials_secure in phase4f-2b-4-materials-read-rpc.sql):
--     - no shared helper is introduced; employee_sessions is referenced inline,
--     - token_hash = encode(digest(session_token_input, 'sha256'), 'hex'),
--     - expires_at > now(),
--     - employees is JOINed and is_active = true is confirmed,
--     - the employee_id is derived server-side from the session token (never taken
--       from the client),
--     - an invalid / expired session RAISEs 'Invalid or expired session'.
CREATE FUNCTION public.list_subcontractors_secure(
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
    SELECT s.id, s.name
    FROM   public.subcontractors s
    WHERE  s.is_active = true
    ORDER  BY s.name, s.id;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only -- same convention as every phase4f-2b read RPC).
ALTER  FUNCTION public.list_subcontractors_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_subcontractors_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_subcontractors_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_subcontractors_secure(text) TO authenticated;


-- 2) list_subcontractors_admin_secure
--   Verify a management session via the existing helper (invalid / expired raises
--   inside the helper), then return active subcontractors ordered by name (id as
--   deterministic tie-breaker). Covers genka-app.html startApp
--   (`select('*').eq('is_active', true)`, genka-app.html:535 -- no explicit order
--   today; the RPC's ORDER BY name, id is deterministic and matches the
--   worker-screen ordering).
--
--   The helper public._verify_management_session(text) is the same one already used
--   by list_companies_secure / list_unit_rates_secure / list_machines_admin_secure,
--   all of which are called from admin-app.html AND genka-app.html management
--   sessions. It verifies both admin sessions and admin-role employee sessions
--   (token hash, expiry, active, admin role) and raises on an invalid session.
--
--   NO include_inactive argument: no screen lists inactive subcontractors today
--   (deliberate omission; add a boolean argument later only if an admin management
--   screen for subcontractors appears).
CREATE FUNCTION public.list_subcontractors_admin_secure(
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
    SELECT s.id, s.name
    FROM   public.subcontractors s
    WHERE  s.is_active = true
    ORDER  BY s.name, s.id;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only -- same convention as list_machines_admin_secure /
-- list_companies_secure).
ALTER  FUNCTION public.list_subcontractors_admin_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_subcontractors_admin_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_subcontractors_admin_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_subcontractors_admin_secure(text) TO authenticated;

-- End of the additive body. Commit both CREATE FUNCTION statements plus their
-- owner / EXECUTE settings as one atomic unit. If anything above failed (including
-- a "function already exists" collision), roll back instead.
COMMIT;


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
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname;

-- P-2. Identity arguments (input signature).
--    Expected for BOTH functions: "session_token_input text".
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname;

-- P-3. Return types (TABLE OUT columns).
--    Expected for BOTH functions: 2 TABLE columns -- (id uuid, name text).
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
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by p.proname, t.ord;

-- P-4. EXECUTE privileges: anon = true, authenticated = true (both functions).
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_subcontractors_secure(text)',       'EXECUTE') as can_execute_employee_rpc,
  has_function_privilege(v.grantee, 'public.list_subcontractors_admin_secure(text)', 'EXECUTE') as can_execute_admin_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-4b. PUBLIC EXECUTE is not present in either function ACL.
--    Expected: 0 rows (no PUBLIC EXECUTE grant on either function).
--    NOTE: grantee OID 0 is PUBLIC, which has no regrole entry, so casting it
--    directly with 0::regrole would error. Use a CASE to display 'PUBLIC' safely.
select
  p.proname,
  case
    when acl.grantee = 0 then 'PUBLIC'
    else acl.grantee::regrole::text
  end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname, acl.privilege_type;

-- P-5. subcontractors table grants UNCHANGED from the C-2 pre-check snapshot
--    (SELECT still granted; the other 7 privileges still not).
--    Expected (same as C-2): SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false for both roles.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.subcontractors', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.subcontractors', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.subcontractors', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.subcontractors', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.subcontractors', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.subcontractors', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-6. subcontractors RLS / FORCE RLS UNCHANGED, and the policy list UNCHANGED from
--    the C-5 pre-check snapshot (sub_read only; none added / dropped / altered).
--    Expected: rls_enabled = true, rls_forced = false, policy_count = 1.
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'subcontractors') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'subcontractors';

select
  policyname, permissive, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'subcontractors'
order by cmd, policyname;

-- P-7. export_projects_summary_secure UNCHANGED from the C-9 pre-check snapshot
--    (it reads subcontractors internally as SECURITY DEFINER; this file must not
--    have touched it).
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  p.provolatile   as volatility,             -- expected 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure';

-- P-7b. export_projects_summary_secure EXECUTE ACL UNCHANGED from the C-9b
--    pre-check snapshot.
--    Expected (same as C-9b): can_execute = true for anon / authenticated /
--    postgres / service_role; ACL rows = exactly those 4 grantees with EXECUTE,
--    is_grantable = false; NO PUBLIC row; explicit (non-NULL) ACL.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure'
order by v.grantee;

select
  p.proname,
  case
    when acl.grantee = 0 then 'PUBLIC'
    else acl.grantee::regrole::text
  end as grantee,
  acl.privilege_type,
  acl.is_grantable,
  (p.proacl is not null) as has_explicit_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure'
order by grantee, acl.privilege_type;

-- P-8. RPC results match the subcontractors table (count / set equality checks).
--    NOTE: requires VALID session tokens; run in the SMOKE TEST step.
--    (Replace <...> with real, valid tokens at run time; do NOT paste any real token
--     into this file.)
--
--   -- employee RPC vs active subcontractors (expect 0 rows both ways):
--   with rpc as (
--     select id, name from public.list_subcontractors_secure('<valid employee session token>')
--   ),
--   src as (
--     select id, name from public.subcontractors where is_active = true
--   )
--   select 'rpc_only' as side, id, name from (select * from rpc except select * from src) d
--   union all
--   select 'src_only' as side, id, name from (select * from src except select * from rpc) d;
--
--   -- employee RPC row count (expect C-10 active = 3):
--   select count(*) from public.list_subcontractors_secure('<valid employee session token>');
--
--   -- admin RPC row count (expect C-10 active = 3):
--   select count(*) from public.list_subcontractors_admin_secure('<valid management session token>');


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER running the body)
--   NOTE: this step is ADDITIVE. The front-end has NOT been migrated yet, so the
--         live screens still use the direct SELECTs and must keep working exactly
--         as before. The two new RPCs exist but are not yet called by any screen --
--         screen confirmation happens in the next (front-end migration) step, NOT
--         here.
--   - Employee RPC: with a VALID employee session token, run
--       select * from public.list_subcontractors_secure('<valid employee session token>');
--     It must return the 3 active subcontractors (2 columns: id, name) ordered by
--     name; compare against the P-8 set check (expect count = C-10 active = 3).
--   - Management RPC: with a VALID management session token (admin-app or genka-app),
--     run
--       select * from public.list_subcontractors_admin_secure('<valid management session token>');
--     Same expectation: 3 rows, id / name, ordered by name.
--   - Negative checks: an invalid / expired token must raise on both functions, e.g.
--       select * from public.list_subcontractors_secure('not-a-real-token');
--       select * from public.list_subcontractors_admin_secure('not-a-real-token');
--     (surfaced as an HTTP 400 RPC exception from PostgREST, as intended).
--   - Do NOT record any real session token value in this file or in the run log.
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; NOT executed -- kept for reference only)
--   Removes exactly the two functions this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on them yet.
-- ============================================================
-- DROP FUNCTION public.list_subcontractors_secure(text);
-- DROP FUNCTION public.list_subcontractors_admin_secure(text);
-- ============================================================
