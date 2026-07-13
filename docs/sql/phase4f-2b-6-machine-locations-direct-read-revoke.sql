-- ============================================================
-- Phase 4-F-2B-6: machine_locations direct read revoke
--   Remove the residual direct SELECT grant on public.machine_locations for
--   anon / authenticated, and drop the now-unnecessary ml_read policy, after the
--   front-end (index.html) has been migrated to the machine_locations read RPCs
--   (list_machine_current_locations_secure / list_machine_location_history_secure).
-- ============================================================
-- [STATUS] NOT YET EXECUTED (created 2026-07-13)
--   - This file removes exactly ONE privilege (SELECT for anon / authenticated on
--     public.machine_locations) and drops exactly ONE policy (ml_read). Nothing else
--     is touched.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / body / post-check are run by the user.
--   - Run this file SECTION BY SECTION in this order:
--     PRE-CHECK (C-1..C-7) -> EXECUTION BODY (single transaction) -> POST-CHECK
--     (P-1..P-6) -> SMOKE TEST (browser) -> ROLLBACK only in an emergency.
--
-- [PURPOSE]
--   - index.html has been migrated to the machine_locations read RPCs
--     (front-end migration PR #113); machine_locations direct read is 0 in the
--     front-end application code (index.html / admin-app.html / genka-app.html).
--     NOTE: the string `.from('machine_locations')` still appears inside this
--     docs/sql file (comments and the smoke-test example) -- those documentation
--     string hits are excluded; only application code is what matters here.
--   - Remove the direct SELECT grant held by anon / authenticated on
--     public.machine_locations (no longer used by the app).
--   - Drop the ml_read policy, which becomes unnecessary once the direct SELECT grant
--     is removed.
--
-- [SCOPE]
--   - public.machine_locations SELECT privilege for anon / authenticated.
--   - public.machine_locations ml_read policy.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - machine_locations data (no DML; row count must be unchanged -- see C-7 / P-6).
--   - INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN privileges
--     for anon / authenticated (already false; unchanged).
--   - ml_write policy (INSERT; left EXACTLY as-is -- never touched).
--   - RLS enabled state / FORCE RLS / owner.
--   - read RPC definitions (list_machine_current_locations_secure /
--     list_machine_location_history_secure) and their EXECUTE grants.
--   - write RPC definition create_machine_location_secure(text, uuid, uuid, text) and
--     its EXECUTE grant.
--   - postgres / service_role / any other role's privileges.
--   - front-end code.
--   - other tables / other policies.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo / production BEFORE this file;
--   SQL cannot check these -- recorded here as confirmed facts; see C-6)
--   - machine_locations direct read (`.from('machine_locations')` /
--     `.from("machine_locations")`) = 0 in the front-end application code
--     (index.html / admin-app.html / genka-app.html); documentation string hits
--     inside docs/sql (this file's comments / search examples) are excluded.
--   - machine_locations direct write (insert / update / delete / upsert) = 0 in the
--     front-end application code.
--   - index.html uses list_machine_current_locations_secure and
--     list_machine_location_history_secure; create_machine_location_secure call remains.
--   - Front-end migration PR #113 merged.
--   - Preview and production verified (machines list / current location / history).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence)
--   - C-1: machine_locations is missing, relkind <> 'r', RLS <> true, FORCE RLS <>
--          false, or owner <> postgres.
--   - C-2: anon or authenticated SELECT is already false (state differs from the
--          assumption), or any of INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--          TRIGGER / MAINTAIN is true.
--   - C-3: ml_read is missing or its definition differs (PERMISSIVE / roles {public} /
--          SELECT / qual true), or ml_write is missing or differs (PERMISSIVE /
--          roles {public} / INSERT / with_check true), or any additional policy
--          exists, or policy_count <> 2.
--   - C-4: either read RPC is missing, not SECURITY DEFINER, not STABLE, owner not
--          postgres, search_path not fixed, return type differs, anon / authenticated
--          EXECUTE not true, or PUBLIC EXECUTE present.
--   - C-5: create_machine_location_secure is missing, not SECURITY DEFINER, not
--          VOLATILE, owner not postgres, search_path not fixed, return type differs, or
--          its EXECUTE grant differs.
--   - C-6: any front-end / repository precondition above is NOT satisfied
--          (e.g. a machine_locations direct read reappears in the front-end
--          application code) -> STOP; do NOT run the body.
--   - C-7: (data baseline) record the row count; it is used as an invariant vs P-6.
--          This file performs NO DML, so the body must not change it.
--
-- [ROLLBACK] (see the commented section at the end)
--   Restores the direct SELECT grant and re-creates ml_read exactly as recorded in
--   C-3 (PERMISSIVE / FOR SELECT / TO public / USING (true)). ml_write is never
--   touched. Emergency use only; normally unnecessary because the front-end is
--   already on the RPCs.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. machine_locations table attributes.
--    Expected: 1 row, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres.
--    STOP if the table is missing or anything differs.
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

-- C-2. anon / authenticated table grants on machine_locations.
--    Expected: SELECT = true (both roles); INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false (both roles).
--    STOP if SELECT is already false, or if any of the other 7 privileges is true.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this project
--      runs PG 17.x per the Phase 4-F-2A record). If this query errors on MAINTAIN on
--      an older server, re-run it without the can_maintain column -- treat that safely
--      and do NOT skip the other columns.
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

-- C-2b. machine_locations SELECT ACL (grant source), so the REVOKE reliably closes it.
--    Expected: exactly one direct SELECT ACL for anon and one for authenticated;
--      NO PUBLIC SELECT ACL.
--    STOP if a PUBLIC SELECT ACL exists (a plain REVOKE FROM anon, authenticated would
--      NOT close a PUBLIC grant), or if the direct anon / authenticated SELECT ACL is
--      missing while C-2 effective SELECT = true (grant source is unexpected --
--      reconcile before running the body).
select
  case
    when acl.grantee = 0 then 'PUBLIC'
    else r.rolname
  end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n
  on n.oid = c.relnamespace
cross join lateral aclexplode(
  coalesce(c.relacl, acldefault('r', c.relowner))
) as acl
left join pg_roles r
  on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machine_locations'
  and acl.privilege_type = 'SELECT'
  and (
    acl.grantee = 0
    or r.rolname in ('anon', 'authenticated')
  )
order by grantee;

-- C-3. machine_locations policies -- full definitions (also the ROLLBACK source).
--    Expected: exactly 2 rows, matching EXACTLY:
--      1) ml_read  : PERMISSIVE, roles {public}, cmd SELECT, qual true,
--         with_check null.
--      2) ml_write : PERMISSIVE, roles {public}, cmd INSERT, qual null,
--         with_check true.
--    STOP if ml_read is missing or differs, if ml_write is missing or differs, if any
--    additional policy exists, or if policy_count <> 2.
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations'
order by cmd, policyname;

select count(*) as policy_count   -- expect 2 (ml_read + ml_write)
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations';

-- C-4. machine_locations read RPCs (must KEEP working after the revoke).
--    Expected: 2 rows -- list_machine_current_locations_secure(text) and
--      list_machine_location_history_secure(text, uuid) -- each SECURITY DEFINER =
--      true, volatility = 's' (STABLE), owner = postgres, config contains
--      search_path=public, extensions.
--    STOP if either is missing or any attribute differs.
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

-- C-4b. read RPC return types (TABLE OUT columns).
--    Expected for BOTH: 4 columns (machine_id uuid, site_id uuid,
--      moved_at timestamp with time zone, memo text).
--    STOP if the return type differs.
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

-- C-4c. read RPC EXECUTE privileges.
--    Expected: anon = true / true, authenticated = true / true.
--    STOP if any is false.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machine_current_locations_secure(text)',      'EXECUTE') as can_execute_current_rpc,
  has_function_privilege(v.grantee, 'public.list_machine_location_history_secure(text, uuid)', 'EXECUTE') as can_execute_history_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- C-4d. read RPC PUBLIC EXECUTE is absent.
--    Expected: 0 rows. STOP if any row is returned.
--    NOTE: grantee OID 0 is PUBLIC; display it with a CASE to avoid casting 0::regrole.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- C-5. machine_locations write RPC baseline (must be UNCHANGED in P-5).
--    Expected: 1 row -- create_machine_location_secure(text, uuid, uuid, text),
--      security_definer = true, volatility = 'v' (VOLATILE), owner = postgres,
--      config contains search_path=public, extensions,
--      result_type = TABLE(id uuid).
--    STOP if it is missing or any attribute (incl. result type) differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,      -- expect true
  p.provolatile               as volatility,            -- expect 'v' (VOLATILE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid)             as result_type,  -- expect TABLE(id uuid)
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
order by p.proname;

-- C-5b. write RPC EXECUTE privileges (baseline; UNCHANGED in P-5).
--    Expected: anon = true, authenticated = true.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute_write_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- C-5c. write RPC PUBLIC EXECUTE is absent (baseline; UNCHANGED in P-5c).
--    Expected: 0 rows. STOP if any row is returned (an unexpected PUBLIC EXECUTE on
--      the write RPC would be a privilege problem, though this file does not change
--      function privileges).
--    NOTE: coalesce(..., acldefault('f', proowner)) catches a NULL proacl (default
--      PUBLIC EXECUTE); grantee OID 0 = PUBLIC.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- C-6. front-end / repository preconditions (NOT checkable from SQL; confirmed from
--    the repo / production BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html / genka-app.html.
--    Documentation string hits inside docs/sql (this file's comments / search
--    examples) are EXCLUDED from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - machine_locations direct read (`.from('machine_locations')` /
--      `.from("machine_locations")`) = 0 in the front-end application code.
--    - machine_locations direct write (insert / update / delete / upsert) = 0 in the
--      front-end application code.
--    - index.html references list_machine_current_locations_secure (loadMachineLocations).
--    - index.html references list_machine_location_history_secure (openMachineMove).
--    - index.html references create_machine_location_secure (confirmMachineMove; unchanged).
--    - Preview verified OK.
--    - Production verified OK (machines list / current location / history; RPC 200;
--      no Console errors; no machine_locations direct SELECT in Network).

-- C-7. machine_locations data baseline (INVARIANT, not reference-only).
--    Record total_rows. Expected (last recorded 2026-07-13): 41.
--    This file performs NO DML, so P-6 must equal this value. A difference at P-6
--    means external write activity (not this file) -- investigate before concluding,
--    since the body itself changes no data.
select count(*) as total_rows   -- baseline for the P-6 invariant
from public.machine_locations;


-- ============================================================
-- EXECUTION BODY
--   Run ONLY after the pre-checks (C-1..C-7) are re-confirmed with no STOP condition
--   hit. This BODY runs as a SINGLE transaction (BEGIN ... COMMIT): the REVOKE and the
--   DROP POLICY succeed together or not at all.
--   DROP POLICY is used WITHOUT "IF EXISTS" on purpose: if ml_read is unexpectedly
--   absent, the statement errors, the transaction aborts, and the REVOKE is rolled
--   back as well (nothing is half-applied).
--   EXACTLY these 2 operations -- nothing else. ml_write is NOT touched.
-- ============================================================

BEGIN;

REVOKE SELECT
ON TABLE public.machine_locations
FROM anon, authenticated;

DROP POLICY ml_read
ON public.machine_locations;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. anon / authenticated table grants after the revoke.
--    Expected: SELECT = false (both roles); INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false (both roles; unchanged from C-2).
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

-- P-1b. machine_locations SELECT ACL after the revoke.
--    Expected: 0 rows -- no PUBLIC / anon / authenticated SELECT ACL remains
--      (mirrors C-2b; the direct SELECT grant is gone).
select
  case
    when acl.grantee = 0 then 'PUBLIC'
    else r.rolname
  end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n
  on n.oid = c.relnamespace
cross join lateral aclexplode(
  coalesce(c.relacl, acldefault('r', c.relowner))
) as acl
left join pg_roles r
  on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machine_locations'
  and acl.privilege_type = 'SELECT'
  and (
    acl.grantee = 0
    or r.rolname in ('anon', 'authenticated')
  )
order by grantee;

-- P-2. machine_locations policies after the drop.
--    Expected: exactly 1 row -- ml_write, UNCHANGED from the C-3 snapshot
--      (PERMISSIVE / {public} / INSERT / qual null / with_check true);
--      ml_read = gone; policy_count = 1.
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations'
order by cmd, policyname;

select count(*) as policy_count   -- expect 1 (ml_write only)
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations';

-- P-3. machine_locations table attributes UNCHANGED.
--    Expected: rls_enabled = true, rls_forced = false, owner = postgres.
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'machine_locations';

-- P-4. read RPCs UNCHANGED and still executable by anon / authenticated.
--    Expected: same as C-4 / C-4b / C-4c / C-4d (2 functions, SECURITY DEFINER,
--      STABLE, owner postgres, fixed search_path, 4-column return type;
--      anon / authenticated EXECUTE = true; PUBLIC EXECUTE absent).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
order by p.proname;

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
  and t.argmode = 't'
order by p.proname, t.ord;

select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machine_current_locations_secure(text)',      'EXECUTE') as can_execute_current_rpc,
  has_function_privilege(v.grantee, 'public.list_machine_location_history_secure(text, uuid)', 'EXECUTE') as can_execute_history_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_machine_current_locations_secure',
                    'list_machine_location_history_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC; expect 0 rows
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- P-5. write RPC UNCHANGED from the C-5 baseline.
--    Expected: create_machine_location_secure(text, uuid, uuid, text) identical to
--      C-5 (SECURITY DEFINER = true, VOLATILE, owner postgres, fixed search_path,
--      result_type = TABLE(id uuid)); EXECUTE for anon / authenticated unchanged.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid)             as result_type,  -- expect TABLE(id uuid)
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
order by p.proname;

select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute_write_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- P-5c. write RPC PUBLIC EXECUTE still absent (UNCHANGED from C-5c).
--    Expected: 0 rows.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
  and acl.grantee = 0                 -- 0 = PUBLIC; expect 0 rows
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- P-6. machine_locations data UNCHANGED from the C-7 baseline (INVARIANT).
--    Expected: total_rows equals C-7 (last recorded 41). The body performs no DML, so
--      this must match; any difference is external write activity, not this file.
select count(*) as total_rows
from public.machine_locations;


-- ============================================================
-- SMOKE TEST (manual; performed by the user in the browser AFTER the body +
--   post-check; reload / re-login first so no cached data masks a failure)
--
--   Employee screen (index.html), machines tab:
--     - list + current locations render; move-history modal opens and shows history.
--     - Network: list_machine_current_locations_secure returns 200.
--     - Network: list_machine_location_history_secure returns 200 (on opening a move).
--     - Network: NO direct read of /rest/v1/machine_locations.
--     - Console: no errors (including 'list_machine_current_locations_secure failed:').
--     - Move recording (write path) -- OPTIONAL, only if a genuinely appropriate,
--       real business move can be recorded: it should still work
--       (create_machine_location_secure 200), confirming ml_write / the write RPC are
--       intact. Do NOT create test-only / throwaway move-history rows just to exercise
--       the write path. If no real move is recorded, rely on P-5 / P-5c above (write
--       RPC attributes, result type, and EXECUTE unchanged) to confirm the write path
--       is intact.
--
--   Direct read rejection check (optional; do NOT record any real token):
--     - From the browser Console in a logged-in app session (anon key context):
--         const r = await sb.from('machine_locations').select('id').limit(1);
--         console.log(r.error);
--       Expected: a permission-denied error object, data = null (direct read shut).
--     - Equivalently in the SQL Editor (roles only; no app token involved):
--         select has_table_privilege('anon',          'public.machine_locations', 'SELECT');
--         select has_table_privilege('authenticated', 'public.machine_locations', 'SELECT');
--       Expected: false / false (same as P-1).
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Restores the direct SELECT grant and re-creates ml_read exactly as recorded in the
--   C-3 pre-check (PERMISSIVE / FOR SELECT / TO public / USING (true)). ml_write is
--   never touched. Normally unnecessary because index.html is already on the read RPCs.
--   Re-confirm the current state (C-1..C-3) before using this.
-- ============================================================
-- BEGIN;
--
-- GRANT SELECT
-- ON TABLE public.machine_locations
-- TO anon, authenticated;
--
-- CREATE POLICY ml_read
-- ON public.machine_locations
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- COMMIT;
-- ============================================================
