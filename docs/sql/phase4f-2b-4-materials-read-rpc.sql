-- ============================================================
-- Phase 4-F-2B-4: add an employee-session-verified read RPC for public.materials
--   (list_materials_secure) so that index.html can stop reading the materials
--   table directly.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file ONLY adds a new read RPC (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - Run MANUALLY by the user in the Supabase SQL Editor, one statement at a time.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--   - The pre-check results recorded below (C-1..C-7) reflect the user's Supabase
--     SQL Editor pre-check run prior to this file; the queries are kept re-runnable
--     to re-confirm before executing the body.
--
-- [PURPOSE]
--   index.html currently reads public.materials via a direct SELECT
--   (`sb.from('materials').select('*').eq('is_active', true).order('name')`,
--    index.html:970 -> loadMaterials) to populate the material chip list and the
--    material master list, and to resolve material_id -> material name for display.
--   This step adds a SECURITY DEFINER read RPC, list_materials_secure(text), that
--   returns only the columns the front-end actually uses (id, name) after verifying
--   an employee session. This is the first of the standard 3-stage migration
--   (read RPC -> front-end move -> direct SELECT REVOKE), matching Phase 4-C / 4-D
--   and phase4f-2b-4-companies-read-rpc.sql.
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration (index.html loadMaterials -> sb.rpc('list_materials_secure')),
--     - REVOKE SELECT ON public.materials FROM anon, authenticated,
--     - DROP POLICY materials_read_all (which becomes stale only AFTER the SELECT
--       grant is revoked).
--
--   Only id and name are returned because those are the only materials columns the
--   front-end reads (verified read-only against index.html):
--     - m.id   : chip value + `state.materials.find(m => m.id === id)`
--                (renderMaterialRows index.html:1155, renderMaster :1727, and the
--                 material-name resolution at :1473 / :1596 / :1626 / :1953 / :2020).
--     - m.name : chip display text + master list + name resolution (same locations).
--   is_active is used ONLY as a fetch filter (index.html:970), never read off the row
--   object; it is reproduced server-side as WHERE is_active = true. created_at is not
--   referenced anywhere for materials. See NON-SCOPE below.
--
-- [SCOPE]
--   Add ONE function: public.list_materials_secure(session_token_input text).
--   Set EXECUTE privileges on that NEW function only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - index.html / admin-app.html / genka-app.html (front-end migration is a later step).
--   - public.materials table grant (anon / authenticated SELECT stays as-is).
--   - materials_read_all policy (LEFT IN PLACE; no DROP POLICY).
--   - RLS / FORCE RLS on materials.
--   - materials data.
--   - existing routines (create_material_secure / deactivate_material_secure).
--   - EXECUTE grants on any existing function.
--   - any other table / role / privilege.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - C-1: materials missing, not an ordinary table, RLS not enabled, or owner not
--          postgres (unexpected) -> STOP.
--   - C-3: materials has an id / name / is_active column mismatch -> STOP (return-type
--          / filter assumptions broken).
--   - C-5: employee_sessions (employee_id / token_hash / expires_at) or employees
--          (id / is_active) verification columns missing -> STOP (authz assumptions
--          broken).
--   - C-7: public.list_materials_secure(text) already exists -> STOP and reconcile
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
--   Recorded results below reflect the user's Supabase SQL Editor pre-check run
--   prior to this file. The queries are re-runnable to re-confirm before executing
--   the body.
-- ============================================================

-- C-1. materials existence + relkind + RLS state + owner.
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
  and c.relname = 'materials';

-- C-2. anon / authenticated effective privileges on materials (context; unchanged here).
--    Recorded: SELECT = true for both; INSERT / UPDATE / DELETE = false for both.
--    This file does NOT change this.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.materials', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.materials', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.materials', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.materials', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. materials columns id / name / is_active exist with expected types.
--    Recorded: id uuid, name text, is_active boolean all present
--      (materials also has created_at timestamptz, which is NOT returned by the RPC).
--    STOP if id / name / is_active are missing or types differ from the RETURNS TABLE
--    / WHERE assumptions.
select
  a.attname     as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type
from pg_attribute a
where a.attrelid = 'public.materials'::regclass
  and a.attnum > 0
  and not a.attisdropped
  and a.attname in ('id', 'name', 'is_active')
order by a.attname;

-- C-4. materials pg_policies (context; unchanged here).
--    Recorded: exactly 1 policy -- materials_read_all
--      (permissive, roles = {public}, cmd = SELECT, qual = true, with_check = null).
--    This file does NOT drop or alter it.
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
  and tablename = 'materials'
order by cmd, policyname;

-- C-5. employee_sessions / employees verification columns exist.
--    Recorded: employee_sessions has employee_id uuid / token_hash text /
--      expires_at timestamptz; employees has id uuid / is_active boolean.
--    STOP if any of these verification columns is missing.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id', 'token_hash', 'expires_at'))
     or (table_name = 'employees'         and column_name in ('id', 'is_active'))
      )
order by table_name, column_name;

-- C-6. existing materials write RPCs are present (baseline for "did not break them").
--    Recorded: create_material_secure / deactivate_material_secure exist, each
--      SECURITY DEFINER = true, owner = postgres, search_path = public, extensions,
--      writing to materials only.
--    This file does NOT alter them.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_material_secure', 'deactivate_material_secure')
order by p.proname;

-- C-7. list_materials_secure(text) does NOT already exist.
--    Recorded: 0 rows (not yet created).
--    STOP if a row is returned (unexpected pre-existing function; reconcile first).
select
  p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_materials_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text';

-- C-8. materials counts (context for the post-check row-count check).
--    Recorded: total = 12, active = 10, inactive = 2.
--    The RPC returns the 10 active rows (id, name) ordered by name.
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive
from public.materials;


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
--   Execution order: CREATE 1 -> REVOKE PUBLIC 1 -> GRANT 1.
-- ============================================================

-- list_materials_secure
--   Verify an employee session inline (invalid / expired raises), then return active
--   materials as (id, name) ordered by name. Behaviour is equivalent to the current
--   direct SELECT `select('*').eq('is_active', true).order('name')` for the columns
--   the front-end uses (id, name).
--
--   Authorization method (matches the existing employee-session RPCs, e.g.
--   list_my_reports_secure in phase4c-1-my-reports-read-rpc.sql):
--     - no shared helper is introduced; employee_sessions is referenced inline,
--     - token_hash = encode(digest(session_token_input, 'sha256'), 'hex'),
--     - expires_at > now(),
--     - employees is JOINed and is_active = true is confirmed,
--     - the employee_id is derived server-side from the session token (never taken
--       from the client),
--     - an invalid / expired session RAISEs 'Invalid or expired session'.
CREATE OR REPLACE FUNCTION public.list_materials_secure(
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
    SELECT m.id, m.name
    FROM   public.materials m
    WHERE  m.is_active = true
    ORDER  BY m.name;
END;
$$;

-- EXECUTE privileges on this NEW function only (repo standard for the employee-session
-- read RPCs: PUBLIC revoked, granted to anon / authenticated only).
REVOKE ALL     ON FUNCTION public.list_materials_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_materials_secure(text) TO anon, authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
--   Consolidated where possible to reduce the number of manual runs.
-- ============================================================

-- P-1. Function identity + attributes in one row:
--    SECURITY DEFINER, STABLE (provolatile = 's'), owner postgres, fixed search_path.
--    Expected: 1 row, is_security_definer = true, volatility = 's', owner = postgres,
--      config contains search_path=public, extensions.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config                 -- expect search_path=public, extensions
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_materials_secure'
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
  and p.proname = 'list_materials_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text'
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by t.ord;

-- P-3. EXECUTE privileges: anon = true, authenticated = true; PUBLIC = false.
--    Expected: anon = true, authenticated = true.
select
  v.grantee,
  has_function_privilege(
    v.grantee,
    'public.list_materials_secure(text)',
    'EXECUTE'
  ) as can_execute
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-3b. PUBLIC EXECUTE is not present in the function ACL.
--    Expected: 0 rows for grantee = PUBLIC (= 0 in acl) with EXECUTE.
select
  acl.grantee::regrole::text as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'list_materials_secure'
  and pg_get_function_identity_arguments(p.oid) = 'session_token_input text'
  and acl.grantee = 0    -- 0 = PUBLIC
order by acl.privilege_type;

-- P-4. materials table grant UNCHANGED (SELECT still true; no INSERT/UPDATE/DELETE
--    added). Expected: SELECT = true, INSERT/UPDATE/DELETE = false (both roles).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.materials', 'SELECT') as can_select,
  has_table_privilege(v.role_name, 'public.materials', 'INSERT') as can_insert,
  has_table_privilege(v.role_name, 'public.materials', 'UPDATE') as can_update,
  has_table_privilege(v.role_name, 'public.materials', 'DELETE') as can_delete
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-5. materials RLS / FORCE RLS UNCHANGED, and materials_read_all UNCHANGED.
--    Expected: rls_enabled = true, rls_forced = false; policy materials_read_all still
--    present (SELECT, roles {public}, qual true); no policy dropped (no DROP POLICY).
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'materials') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'materials';

select
  policyname, permissive, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'materials'
order by cmd, policyname;

-- P-6. Existing materials write RPCs are UNCHANGED (still SECURITY DEFINER, postgres,
--    fixed search_path). Expected: 2 rows, unchanged from C-6.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_material_secure', 'deactivate_material_secure')
order by p.proname;

-- P-7. RPC result matches the active-materials list.
--    NOTE: requires a VALID employee session token; run in the SMOKE TEST step.
--    Expected: returns 10 rows (id, name), ordered by name, and each row equals an
--      active materials row. The set difference below must be EMPTY both ways.
--    (Replace <valid employee session token> with a real, valid token at run time;
--     do NOT paste any real token into this file.)
--
--   with rpc as (
--     select id, name from public.list_materials_secure('<valid employee session token>')
--   ),
--   src as (
--     select id, name from public.materials where is_active = true
--   )
--   select 'rpc_only' as side, id, name from (select * from rpc except select * from src) d
--   union all
--   select 'src_only' as side, id, name from (select * from src except select * from rpc) d;
--   -- Expected: 0 rows. Also confirm `select count(*) from rpc` = 10.
-- Direct SELECT REVOKE and policy DROP are NOT performed by this file (separate,
-- later steps). P-4 / P-5 above confirm they have not happened.


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER running the body)
--   NOTE: this step is ADDITIVE. The front-end has NOT been migrated yet, so the
--         live index.html screens still use the direct SELECT and must keep working
--         exactly as before. list_materials_secure exists but is not yet called by
--         any screen -- screen confirmation happens in the next (front-end migration)
--         step, NOT here.
--   - Direct RPC check: with a VALID employee session token, run
--       select * from public.list_materials_secure('<valid employee session token>');
--     It must return the active materials as (id, name) ordered by name (10 rows).
--     Then run P-7 above to confirm the RPC result equals the active-materials list.
--   - Negative check: an invalid / expired token must raise
--       'Invalid or expired session', e.g.
--       select * from public.list_materials_secure('not-a-real-token');
--   - Do NOT record any real session token value in this file or in the run log.
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Removes exactly the function this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on it yet.
-- ============================================================
-- DROP FUNCTION public.list_materials_secure(text);
-- ============================================================
