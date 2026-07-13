-- ============================================================
-- Phase 4-F-2B-6: add secure read RPCs for public.machine_locations
--   (list_machine_current_locations_secure /
--    list_machine_location_history_secure) so that index.html can stop
--   reading the machine_locations table directly.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-13)
--   - This file ONLY adds two new read RPCs (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--
--   [DB EXECUTION] (Supabase SQL Editor, by the user, 2026-07-13)
--     - The user ran the EXECUTION BODY manually in the Supabase SQL Editor.
--     - Result: Success. No rows returned.
--     - Both functions created:
--         public.list_machine_current_locations_secure(text)
--         public.list_machine_location_history_secure(text, uuid)
--     - Delivered via PR #111 (merge commit 5c74904; SQL source commit a186845).
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--
--   [PRE-CHECK RESULT] (C-1..C-12, Supabase SQL Editor, 2026-07-13 -- all passed)
--     - C-1: machine_locations exists, schema = public, relkind = 'r', RLS = true,
--       FORCE RLS = false, owner = postgres.
--     - C-2: columns / types as assumed --
--       id uuid NOT NULL DEFAULT gen_random_uuid(), machine_id uuid NOT NULL,
--       site_id uuid NULL, moved_by uuid NULL, memo text NULL,
--       moved_at timestamptz NOT NULL DEFAULT now().
--     - C-3: anon / authenticated SELECT = true;
--       anon / authenticated INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--       TRIGGER / MAINTAIN = false. (context only; left untouched by this file.)
--     - C-4: 2 policies recorded --
--       ml_read  (SELECT, roles public, USING true),
--       ml_write (INSERT, roles public, WITH CHECK true)
--       (context only; left untouched by this file).
--     - C-5: PK = id; FK machine_id -> machines(id), site_id -> sites(id),
--       moved_by -> employees(id); indexes = machine_locations_pkey(id) only
--       (no (machine_id, moved_at) composite index).
--     - C-6: all 5 employee-session verification columns exist
--       (employee_sessions.employee_id / token_hash / expires_at,
--        employees.id / is_active).
--     - C-7: list_machine_current_locations_secure /
--       list_machine_location_history_secure did not exist beforehand (0 rows).
--     - C-8: existing write RPC present --
--       create_machine_location_secure(text, uuid, uuid, text) RETURNS TABLE(id uuid),
--       SECURITY DEFINER = true, VOLATILE, owner = postgres,
--       search_path = public, extensions (baseline snapshot for P-7).
--     - C-9: machine_locations counts -- total_rows = 41, distinct_machine = 20,
--       site_id null = 21, moved_by null = 20, memo null = 20, moved_at null = 0.
--     - C-10: orphan machine_id = 0, orphan site_id = 0.
--     - C-11: duplicate (machine_id, moved_at) = 0.
--     - C-12: active machines = 22, with a latest location = 20,
--       active machines without any location = 2;
--       DISTINCT ON vs per-machine LIMIT 1 mismatch = 0.
--
--   [POST-CHECK RESULT] (P-1..P-7, Supabase SQL Editor, 2026-07-13 -- all passed)
--     - P-1: both new RPCs exist; SECURITY DEFINER = true; STABLE
--       (provolatile = 's'); owner = postgres; search_path = public, extensions.
--     - P-2: identity arguments as declared --
--       list_machine_current_locations_secure(session_token_input text);
--       list_machine_location_history_secure(session_token_input text,
--                                            machine_id_input uuid).
--     - P-3: both functions return 4 TABLE columns
--       (machine_id uuid, site_id uuid, moved_at timestamptz, memo text).
--     - P-4: anon EXECUTE = true, authenticated EXECUTE = true (both functions).
--     - P-4b: PUBLIC EXECUTE = none.
--     - P-5: machine_locations table grants unchanged from the C-3 snapshot
--       (SELECT still granted; the other 7 privileges still not).
--     - P-6: RLS / FORCE RLS unchanged; policy list unchanged (ml_read / ml_write).
--     - P-7: create_machine_location_secure unchanged from the C-8 snapshot.
--
--   [SMOKE TEST RESULT] (valid employee session, 2026-07-13)
--     - list_machine_current_locations_secure: error = null, count = 20;
--       return columns correct.
--     - list_machine_location_history_secure: error = null; the tested machine
--       returned its history (1 row for that machine); 10-row cap OK; moved_at DESC OK.
--     - Negative (invalid / expired token): both functions raise
--       'Invalid or expired session' (surfaced as an HTTP 400 RPC exception, as
--       intended).
--     - Negative (non-existent machine UUID): error = null, 0 rows (smoke tested).
--       An inactive machine also yields 0 rows by design (the JOIN to machines with
--       is_active = true filters it out), but that specific case was NOT separately
--       smoke tested.
--     - No real session token value is recorded here.
--
--   [STILL NOT DONE] (separate, later steps)
--     - front-end migration (index.html loadMachineLocations : N+1 direct read ->
--       list_machine_current_locations_secure; openMachineMove : direct history read
--       -> list_machine_location_history_secure).
--     - machine_locations direct read shutdown (the two direct reads are still live).
--     - REVOKE SELECT ON public.machine_locations FROM anon, authenticated (NOT
--       performed; SELECT is still granted).
--     - DROP POLICY ml_read (NOT performed; the policy still exists).
--     - front-end Preview check / production screen check (not performed; the
--       front-end has not been migrated yet).
--
-- [PURPOSE]
--   index.html currently reads public.machine_locations via direct SELECTs:
--     - index.html:2068  loadMachineLocations : for each active machine, run
--         select('*').eq('machine_id', m.id).order('moved_at', desc).limit(1)  (N+1)
--     - index.html:2173  openMachineMove      : for one machine, run
--         select('*').eq('machine_id', machineId).order('moved_at', desc).limit(10)
--   This step adds two SECURITY DEFINER read RPCs following the standard 3-stage
--   migration (read RPC -> front-end move -> direct read shutdown), matching
--   phase4f-2b-5-machines-read-rpc.sql (employee-session inline verification).
--   Only the front-end (index.html) reads this table; admin-app.html / genka-app.html
--   never touch machine_locations (verified read-only).
--
--     1. list_machine_current_locations_secure(text)
--        - employee-session-verified (same inline verification as
--          list_machines_secure), for index.html loadMachineLocations.
--        - returns the latest location per ACTIVE machine (DISTINCT ON), with the
--          columns the worker screen actually uses: machine_id, site_id, moved_at,
--          memo. Collapses the N+1 loop into a single call.
--
--     2. list_machine_location_history_secure(text, uuid)
--        - employee-session-verified (same inline verification), for index.html
--          openMachineMove.
--        - returns up to 10 most-recent location rows for the given machine, only if
--          that machine is active; machine_id / site_id / moved_at / memo.
--
--   Neither RPC returns moved_by or id (the worker screen does not read them), nor
--   the machine name / site name (resolved front-end side from list_machines_secure
--   and state.sites). Verified read-only against index.html.
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration of the two direct reads listed above,
--     - any REVOKE on the machine_locations table (SELECT stays granted),
--     - any policy change / DROP POLICY on machine_locations (ml_read / ml_write are
--       left exactly as the pre-check found them).
--
-- [SCOPE]
--   Add TWO functions:
--     - public.list_machine_current_locations_secure(session_token_input text)
--     - public.list_machine_location_history_secure(session_token_input text,
--                                                   machine_id_input uuid)
--   Set owner and EXECUTE privileges on those NEW functions only.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - index.html (front-end migration is a later step).
--   - public.machine_locations table grants (whatever the pre-check finds stays as-is;
--     SELECT for anon / authenticated is NOT revoked here).
--   - machine_locations policies ml_read / ml_write (NO change, NO drop).
--   - RLS / FORCE RLS on machine_locations.
--   - machine_locations data.
--   - existing write RPC create_machine_location_secure(text, uuid, uuid, text) and
--     its EXECUTE grant.
--   - any machines-related RPC (list_machines_secure / list_machines_admin_secure /
--     the machines write RPCs) -- reused / unaffected, NOT modified.
--   - any other table / role / privilege / policy.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - C-1: machine_locations missing, not an ordinary table, RLS not enabled, or owner
--          not postgres -> STOP.
--   - C-2: machine_locations column set / types do not match the assumptions below
--          (machine_id uuid, site_id uuid, moved_at timestamptz, memo text; id uuid) or
--          moved_at is not an orderable timestamp type -> STOP (return-type / ORDER BY
--          assumptions broken).
--   - C-6: employee_sessions (employee_id / token_hash / expires_at) or employees
--          (id / is_active) verification columns missing -> STOP.
--   - C-7: public.list_machine_current_locations_secure(text) or
--          public.list_machine_location_history_secure(text, uuid) already exists ->
--          STOP and reconcile (this file uses plain CREATE FUNCTION -- NOT CREATE OR
--          REPLACE -- so an unexpected pre-existing function makes the body error out
--          instead of silently overwriting it; the environment differs from the
--          assumed additive-only state).
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--   NOTE: C-9 counts are context / reference values only; they are NOT stop conditions.
--
-- [ROLLBACK] (see the commented section at the end)
--   The commented DROP FUNCTION statements remove exactly the two functions this
--   file adds. Because this file is additive and touches no grant / policy / table,
--   dropping the new functions fully reverses this step (the front-end has not yet
--   been migrated at this stage, so nothing depends on them).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run by the user in the Supabase SQL Editor BEFORE the body.
--   Results are recorded in [PRE-CHECK RESULT] in the header above; the queries
--   are kept re-runnable.
-- ============================================================

-- C-1. machine_locations existence + relkind + RLS state + owner.
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
  and c.relname = 'machine_locations';

-- C-2. machine_locations columns exist with the types assumed by the RETURNS TABLE
--    declarations and the query below.
--    Expected: id uuid, machine_id uuid, site_id uuid, moved_by uuid, memo text,
--      moved_at timestamp with time zone.
--    STOP if any of machine_id / site_id / moved_at / memo (or id) is missing or its
--    type differs (return-type / ORDER BY assumptions broken).
select
  a.attname                            as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null
from pg_attribute a
where a.attrelid = 'public.machine_locations'::regclass
  and a.attnum > 0
  and not a.attisdropped
  and a.attname in ('id', 'machine_id', 'site_id', 'moved_by', 'memo', 'moved_at')
order by a.attname;

-- C-3. anon / authenticated effective privileges on machine_locations
--    (context; this file does NOT change them -- SELECT stays granted).
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false for both roles.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machine_locations', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.machine_locations', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.machine_locations', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.machine_locations', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.machine_locations', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.machine_locations', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.machine_locations', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.machine_locations', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-4. machine_locations pg_policies (context; unchanged here).
--    Expected: ml_read (SELECT / public / USING true),
--      ml_write (INSERT / public / WITH CHECK true).
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
  and tablename = 'machine_locations'
order by cmd, policyname;

-- C-6. employee_sessions / employees verification columns exist
--    (same assumptions as list_machines_secure).
--    STOP if any of these verification columns is missing.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id', 'token_hash', 'expires_at'))
     or (table_name = 'employees'         and column_name in ('id', 'is_active'))
      )
order by table_name, column_name;

-- C-7. Neither new function already exists.
--    Expected: 0 rows.
--    STOP if a row is returned (unexpected pre-existing function; reconcile first).
select
  p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure');

-- C-8. existing write RPC create_machine_location_secure is present (baseline for
--    "did not break it"). Record the result; this file does NOT alter it.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  p.provolatile   as volatility,             -- expected 'v' (VOLATILE)
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
order by p.proname;

-- C-9. machine_locations counts (context for the DISTINCT ON validation).
--    Reference values only (NOT a stop condition).
select
  count(*)                                        as total_rows,
  count(distinct machine_id)                      as distinct_machine,
  count(*) filter (where site_id  is null)        as site_id_null,
  count(*) filter (where moved_by is null)        as moved_by_null,
  count(*) filter (where memo     is null)        as memo_null,
  count(*) filter (where moved_at is null)        as moved_at_null
from public.machine_locations;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (C-1..C-9) are confirmed with no STOP condition hit.
--   NOTE: additive only -- two plain CREATE FUNCTION statements (NOT CREATE OR
--         REPLACE, so a pre-existing function of the same signature errors out rather
--         than being overwritten) plus owner / EXECUTE settings on those NEW
--         functions. No table grant, no RLS, no policy, no existing routine is touched.
--   NOTE: the whole body runs as ONE transaction (BEGIN ... COMMIT below), so a
--         failure on either function (e.g. C-7 collision) rolls back the entire step
--         and leaves nothing half-created. PRE-CHECK and POST-CHECK are OUTSIDE this
--         transaction (read-only; run them separately).
--   Execution order per function: CREATE -> ALTER OWNER -> REVOKE PUBLIC -> GRANT.
-- ============================================================

BEGIN;

-- 1) list_machine_current_locations_secure
--   Verify an employee session inline (invalid / expired raises), then return the
--   latest location per ACTIVE machine via DISTINCT ON. For the columns the worker
--   screen uses (machine_id / site_id / moved_at / memo), behaviour is equivalent to
--   the current per-machine direct SELECT
--   `select('*').eq('machine_id', m.id).order('moved_at', desc).limit(1)`
--   (index.html:2068), collapsed into a single call.
--
--   Authorization method (matches list_machines_secure in
--   phase4f-2b-5-machines-read-rpc.sql):
--     - no shared helper is introduced; employee_sessions is referenced inline,
--     - token_hash = encode(digest(session_token_input, 'sha256'), 'hex'),
--     - expires_at > now(),
--     - employees is JOINed and is_active = true is confirmed,
--     - the employee_id is derived server-side from the session token (never taken
--       from the client),
--     - an invalid / expired session RAISEs 'Invalid or expired session'.
--
--   Tie-breaker: DISTINCT ON (ml.machine_id) with
--   ORDER BY ml.machine_id, ml.moved_at DESC, ml.id DESC makes the "latest" pick
--   deterministic even if two rows share moved_at (the current front-end direct read
--   has no tie-breaker). C-11 confirmed 0 duplicate (machine_id, moved_at) today.
CREATE FUNCTION public.list_machine_current_locations_secure(
  session_token_input text
)
RETURNS TABLE (
  machine_id uuid,
  site_id    uuid,
  moved_at   timestamptz,
  memo       text
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
    SELECT DISTINCT ON (ml.machine_id)
           ml.machine_id, ml.site_id, ml.moved_at, ml.memo
    FROM   public.machine_locations ml
    JOIN   public.machines m ON m.id = ml.machine_id
    WHERE  m.is_active = true
    ORDER  BY ml.machine_id, ml.moved_at DESC, ml.id DESC;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only).
ALTER  FUNCTION public.list_machine_current_locations_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_machine_current_locations_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_machine_current_locations_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_machine_current_locations_secure(text) TO authenticated;


-- 2) list_machine_location_history_secure
--   Verify an employee session inline (invalid / expired raises), then return up to
--   10 most-recent location rows for the given machine, but only if that machine is
--   active. For the columns the worker screen uses, behaviour is equivalent to the
--   current direct SELECT
--   `select('*').eq('machine_id', machineId).order('moved_at', desc).limit(10)`
--   (index.html:2173).
--
--   Same inline employee-session verification as function (1). A non-existent or
--   inactive machine yields 0 rows (the JOIN to machines with is_active = true filters
--   it out); no separate existence check / error is needed.
CREATE FUNCTION public.list_machine_location_history_secure(
  session_token_input text,
  machine_id_input     uuid
)
RETURNS TABLE (
  machine_id uuid,
  site_id    uuid,
  moved_at   timestamptz,
  memo       text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  -- Authorization: same as list_machine_current_locations_secure.
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
    SELECT ml.machine_id, ml.site_id, ml.moved_at, ml.memo
    FROM   public.machine_locations ml
    JOIN   public.machines m ON m.id = ml.machine_id
    WHERE  m.is_active = true
      AND  ml.machine_id = machine_id_input
    ORDER  BY ml.moved_at DESC, ml.id DESC
    LIMIT  10;
END;
$$;

-- Owner + EXECUTE privileges on this NEW function only (PUBLIC revoked, granted to
-- anon / authenticated only).
ALTER  FUNCTION public.list_machine_location_history_secure(text, uuid) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_machine_location_history_secure(text, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_machine_location_history_secure(text, uuid) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_machine_location_history_secure(text, uuid) TO authenticated;

-- End of the additive body. Commit both CREATE FUNCTION statements plus their owner /
-- EXECUTE settings as one atomic unit. If anything above failed, roll back instead.
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
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
order by p.proname;

-- P-2. Identity arguments (input signature).
--    Expected:
--      list_machine_current_locations_secure -> "session_token_input text"
--      list_machine_location_history_secure  -> "session_token_input text, machine_id_input uuid"
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
order by p.proname;

-- P-3. Return types (TABLE OUT columns).
--    Expected for BOTH functions: 4 TABLE columns --
--      (machine_id uuid, site_id uuid, moved_at timestamp with time zone, memo text).
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
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by p.proname, t.ord;

-- P-4. EXECUTE privileges: anon = true, authenticated = true (both functions).
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machine_current_locations_secure(text)',      'EXECUTE') as can_execute_current_rpc,
  has_function_privilege(v.grantee, 'public.list_machine_location_history_secure(text, uuid)', 'EXECUTE') as can_execute_history_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-4b. PUBLIC EXECUTE is not present in either function ACL.
--    Expected: 0 rows (no PUBLIC EXECUTE grant on either function).
--    NOTE: grantee OID 0 is PUBLIC, which has no regrole entry, so casting it directly
--    with 0::regrole would error. Use a CASE to display 'PUBLIC' safely.
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
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname, acl.privilege_type;

-- P-5. machine_locations table grants UNCHANGED from the C-3 pre-check snapshot
--    (SELECT still granted; the other 7 privileges still not).
--    Expected (same as C-3): SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false for both roles.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machine_locations', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.machine_locations', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.machine_locations', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.machine_locations', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.machine_locations', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.machine_locations', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.machine_locations', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.machine_locations', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-6. machine_locations RLS / FORCE RLS UNCHANGED, and the policy list UNCHANGED
--    from the C-4 pre-check snapshot (ml_read / ml_write; none added / dropped /
--    altered).
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'machine_locations') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'machine_locations';

select
  policyname, permissive, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations'
order by cmd, policyname;

-- P-7. Existing write RPC create_machine_location_secure UNCHANGED from the C-8
--    pre-check snapshot.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  p.provolatile   as volatility,             -- expected 'v' (VOLATILE)
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
order by p.proname;

-- P-8. RPC results match the direct-read behaviour (set / count checks).
--    NOTE: requires a VALID employee session token; run in the SMOKE TEST step.
--    (Replace <...> with a real, valid token at run time; do NOT paste any real token
--     into this file.)
--
--   -- current-locations RPC vs per-machine latest over active machines
--   -- (expect 0 rows both ways):
--   with rpc as (
--     select machine_id, site_id, moved_at, memo
--     from public.list_machine_current_locations_secure('<valid employee session token>')
--   ),
--   src as (
--     select distinct on (ml.machine_id)
--            ml.machine_id, ml.site_id, ml.moved_at, ml.memo
--     from public.machine_locations ml
--     join public.machines m on m.id = ml.machine_id
--     where m.is_active = true
--     order by ml.machine_id, ml.moved_at desc, ml.id desc
--   )
--   select 'rpc_only' as side, * from (select * from rpc  except select * from src) d
--   union all
--   select 'src_only' as side, * from (select * from src except select * from rpc) d;
--
--   -- current-locations RPC row count (expect C-12 "with a latest location" = 20):
--   select count(*) from public.list_machine_current_locations_secure('<valid employee session token>');
--
--   -- history RPC for one active machine (expect <= 10 rows, moved_at desc):
--   select * from public.list_machine_location_history_secure('<valid employee session token>', '<active machine uuid>');


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER running the body)
--   NOTE: this step is ADDITIVE. The front-end has NOT been migrated yet, so the
--         live screen still uses the direct SELECTs and must keep working exactly as
--         before. The two new RPCs exist but are not yet called by any screen --
--         screen confirmation happens in the next (front-end migration) step, NOT
--         here.
--   - current-locations RPC: with a VALID employee session token, run
--       select * from public.list_machine_current_locations_secure('<valid employee session token>');
--     It must return the latest location per active machine (4 columns);
--     compare against the P-8 set check.
--   - history RPC: with a VALID employee session token and an active machine id, run
--       select * from public.list_machine_location_history_secure('<valid employee session token>', '<active machine uuid>');
--     It must return <= 10 rows ordered by moved_at desc. An inactive / non-existent
--     machine id must return 0 rows.
--   - Negative checks: an invalid / expired token must raise on both functions, e.g.
--       select * from public.list_machine_current_locations_secure('not-a-real-token');
--       select * from public.list_machine_location_history_secure('not-a-real-token', '<any uuid>');
--   - Do NOT record any real session token value in this file or in the run log.
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Removes exactly the two functions this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on them yet.
-- ============================================================
-- DROP FUNCTION public.list_machine_current_locations_secure(text);
-- DROP FUNCTION public.list_machine_location_history_secure(text, uuid);
-- ============================================================
