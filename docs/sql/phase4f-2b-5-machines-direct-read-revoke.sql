-- ============================================================
-- Phase 4-F-2B-5: machines direct read revoke
--   Remove the residual direct SELECT grant on public.machines for
--   anon / authenticated, and drop the now-unnecessary machines_read_all
--   policy, after the front-end has been migrated to the machines read RPCs
--   (list_machines_secure / list_machines_admin_secure).
-- ============================================================
-- [STATUS] EXECUTED (2026-07-12)
--   - This file removes exactly ONE privilege (SELECT for anon / authenticated on
--     public.machines) and drops exactly ONE policy (machines_read_all). Nothing
--     else is touched.
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--   - Run this file SECTION BY SECTION, one statement at a time, in this order:
--     PRE-CHECK (C-1..C-7) -> EXECUTION BODY (2 statements) -> POST-CHECK
--     (P-1..P-6) -> SMOKE TEST (browser) -> ROLLBACK only in an emergency.
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-12)
--     - The user ran the EXECUTION BODY manually, ONE statement at a time.
--       * Statement 1:
--           REVOKE SELECT ON TABLE public.machines FROM anon, authenticated;
--         Result: Success. No rows returned.
--       * Statement 2:
--           DROP POLICY machines_read_all ON public.machines;
--         Result: Success. No rows returned.
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--
--   [PRE-CHECK RESULT] (C-1..C-7, Supabase SQL Editor, 2026-07-12 -- all passed)
--     - C-1: public.machines exists, relkind = 'r', RLS = true, FORCE RLS = false,
--       owner = postgres.
--     - C-2: anon / authenticated SELECT = true; both roles INSERT / UPDATE /
--       DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN = false.
--     - C-3: exactly 3 policies, matching the expected definitions:
--       * machines_read_all : PERMISSIVE, {public}, SELECT, qual true,
--         with_check null.
--       * machines_update   : PERMISSIVE, {public}, UPDATE, qual true,
--         with_check null.
--       * machines_write    : PERMISSIVE, {public}, INSERT, qual null,
--         with_check true.
--     - C-4: list_machines_secure(text) and list_machines_admin_secure(text,
--       boolean) both exist; SECURITY DEFINER = true, STABLE, owner = postgres,
--       search_path = public, extensions.
--     - C-4b: anon / authenticated EXECUTE = true on both read RPCs.
--     - C-4c: PUBLIC EXECUTE = none on both read RPCs.
--     - C-5: all 5 write RPCs present; SECURITY DEFINER = true, VOLATILE,
--       owner = postgres, search_path = public, extensions.
--     - C-6 (REFERENCE ONLY; not a pass / fail criterion): total = 26,
--       active = 22, inactive = 4, null_active = 0.
--     - C-7: `.from('machines')` = 0 hits repo-wide; front-end migration PR #108
--       merged (merge commit 80ba140); Preview and production verified on all
--       three screens.
--
--   [POST-CHECK RESULT] (P-1..P-6, Supabase SQL Editor, 2026-07-12 -- all passed)
--     - P-1: anon / authenticated SELECT / INSERT / UPDATE / DELETE / TRUNCATE /
--       REFERENCES / TRIGGER / MAINTAIN = false (all eight, both roles).
--     - P-2: machines_read_all = gone; machines_update and machines_write remain
--       unchanged; policy_count = 2.
--     - P-3: relkind = 'r', RLS = true, FORCE RLS = false, owner = postgres
--       (unchanged).
--     - P-4: both read RPCs unchanged; anon / authenticated EXECUTE = true;
--       PUBLIC EXECUTE = none.
--     - P-5: all 5 write RPCs unchanged from the C-5 baseline.
--     - P-6 (REFERENCE ONLY; not a pass / fail criterion): total = 26,
--       active = 22, inactive = 4, null_active = 0.
--
--   [SMOKE TEST RESULT] (production browser, after the body + post-check,
--     2026-07-12; no real session token value is recorded here)
--     - Employee screen (index.html): machines list, current locations, move, and
--       settings all working; list_machines_secure Status 200; NO machines direct
--       read in Network; no Console errors.
--     - Admin screen (admin-app.html): full list shows all 26 rows incl. 4
--       inactive; edit and add modals working; list_machines_admin_secure
--       Status 200; NO machines direct read in Network; no Console errors.
--     - Genka screen (genka-app.html): cost summary and machine lease cost figures
--       correct; list_machines_admin_secure Status 200; NO machines direct read in
--       Network; no Console errors.
--
--   [FINAL STATE]
--     - anon / authenticated SELECT on public.machines: revoked.
--     - machines_read_all policy: dropped.
--     - machines_update / machines_write policies: KEPT (unchanged; separate
--       stale-policy decision).
--     - read RPC 2 (list_machines_secure / list_machines_admin_secure): working.
--     - write RPC 5: working, unchanged.
--     - RLS / FORCE RLS / owner: unchanged.
--     - machines reads are now unified through the secure read RPCs.
--     - machine_locations: NOT in scope (unchanged).
--     - ROLLBACK: NOT executed (kept as commented reference only).
--
-- [PURPOSE]
--   - All three front-ends have been migrated to the machines read RPCs
--     (front-end migration PR #108); `.from('machines')` is 0 hits repo-wide.
--   - Remove the direct SELECT grant held by anon / authenticated on
--     public.machines (no longer used by the app).
--   - Drop the machines_read_all policy, which becomes unnecessary once the
--     direct SELECT grant is removed.
--
-- [SCOPE]
--   - public.machines SELECT privilege for anon / authenticated.
--   - public.machines machines_read_all policy.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - machines data.
--   - INSERT / UPDATE / DELETE privileges (already false for anon / authenticated).
--   - machines_update policy (left as-is; separate stale-policy decision).
--   - machines_write policy (left as-is; separate stale-policy decision).
--   - RLS enabled state / FORCE RLS.
--   - read RPC definitions (list_machines_secure / list_machines_admin_secure).
--   - write RPC definitions (create_machine_secure / update_machine_secure /
--     deactivate_machine_secure / create_machine_admin_secure /
--     update_machine_admin_secure).
--   - machine_locations (its direct reads are a separate backlog item).
--   - front-end code.
--   - other tables / other policies.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo / production BEFORE this file;
--   SQL cannot check these -- recorded here as assumptions)
--   - `.from('machines')` is 0 hits across the whole repository
--     (index.html / admin-app.html / genka-app.html all migrated).
--   - Front-end migration PR #108 is merged; merge commit 80ba140.
--   - Preview and production verified on all three screens (employee machines tab,
--     admin machines list / edit modal, genka cost summary) using the read RPCs.
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report)
--   - C-1: machines is missing, relkind <> 'r', RLS <> true, FORCE RLS <> false,
--          or owner <> postgres.
--   - C-2: anon or authenticated SELECT is already false (state differs from the
--          assumption -- reconcile first; do NOT guess), or any of
--          INSERT / UPDATE / DELETE is true.
--   - C-3: machines_read_all does not exist, or its definition differs from the
--          recorded one (PERMISSIVE / roles {public} / SELECT / qual true /
--          with_check null), or machines_update / machines_write are missing or
--          differ from their recorded definitions, or any additional policy exists.
--   - C-4: either read RPC is missing, not SECURITY DEFINER, not STABLE, owner not
--          postgres, search_path not fixed, anon / authenticated EXECUTE not true,
--          or PUBLIC EXECUTE present.
--   - C-5: any of the 5 write RPCs is missing or its attributes differ from the
--          recorded baseline.
--   - NOTE: C-6 row counts are REFERENCE ONLY. A row-count change alone is NOT a
--          stop condition.
--
-- [ROLLBACK] (see the commented section at the end)
--   Restores the direct SELECT grant and re-creates machines_read_all exactly as
--   recorded in C-3 (PERMISSIVE / FOR SELECT / TO public / USING (true)).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. machines table attributes.
--    Expected: 1 row, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres.
--    STOP if anything differs.
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

-- C-2. anon / authenticated table grants on machines.
--    Expected: SELECT = true (both roles); INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false (both roles).
--    STOP if SELECT is already false, or if any of INSERT / UPDATE / DELETE is true.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this project
--      runs PG 17.x per the Phase 4-F-2A record). If this query errors on MAINTAIN
--      on an older server, re-run it without the can_maintain column -- treat that
--      safely and do NOT skip the other columns.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machines', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.machines', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.machines', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.machines', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.machines', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.machines', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.machines', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.machines', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- C-3. machines policies -- full definitions (also the ROLLBACK source).
--    Expected: exactly 3 rows, matching EXACTLY:
--      1) machines_read_all : PERMISSIVE, roles {public}, cmd SELECT,
--         qual true, with_check null.
--      2) machines_update   : PERMISSIVE, roles {public}, cmd UPDATE,
--         qual true, with_check null.
--      3) machines_write    : PERMISSIVE, roles {public}, cmd INSERT,
--         qual null, with_check true.
--    STOP if machines_read_all is missing, if any definition differs, or if any
--    additional policy exists.
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
  and tablename = 'machines'
order by cmd, policyname;

-- C-4. machines read RPCs (must KEEP working after the revoke).
--    Expected: 2 rows -- list_machines_secure(session_token_input text) and
--      list_machines_admin_secure(session_token_input text, include_inactive_input
--      boolean) -- each SECURITY DEFINER = true, volatility = 's' (STABLE),
--      owner = postgres, config contains search_path=public, extensions.
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
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
order by p.proname;

-- C-4b. read RPC EXECUTE privileges.
--    Expected: anon = true / true, authenticated = true / true.
--    STOP if any is false.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machines_secure(text)',                'EXECUTE') as can_execute_employee_rpc,
  has_function_privilege(v.grantee, 'public.list_machines_admin_secure(text, boolean)', 'EXECUTE') as can_execute_admin_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- C-4c. read RPC PUBLIC EXECUTE is absent.
--    Expected: 0 rows. STOP if any row is returned.
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

-- C-5. machines write RPCs baseline (same attribute check as
--    phase4f-2b-5-machines-read-rpc.sql C-9 / P-6; must be UNCHANGED in P-5).
--    Expected: 5 rows, each security_definer = true, owner = postgres,
--      config contains search_path=public, extensions.
--    STOP if any is missing or differs from the recorded baseline.
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

-- C-6. machines row counts (REFERENCE ONLY -- NOT a stop condition).
--    Last recorded (2026-07-11): total = 26, active = 22, inactive = 4,
--      null_active = 0. Row counts naturally change with normal operation;
--    a difference here does NOT block the revoke.
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.machines;

-- C-7. front-end preconditions (NOT checkable from SQL; confirm from the repo /
--    production records BEFORE running the body):
--    - `.from('machines')` = 0 hits repo-wide (all three front-ends migrated).
--    - Front-end migration PR #108 merged; merge commit 80ba140.
--    - Preview and production verified on all three screens with the read RPCs.


-- ============================================================
-- EXECUTION BODY
--   Run ONLY after the pre-checks (C-1..C-7) are re-confirmed with no STOP
--   condition hit. Run ONE statement at a time in the Supabase SQL Editor.
--   EXACTLY these 2 statements -- nothing else.
-- ============================================================

REVOKE SELECT
ON TABLE public.machines
FROM anon, authenticated;

DROP POLICY machines_read_all
ON public.machines;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. anon / authenticated table grants after the revoke.
--    Expected: SELECT = false (both roles); INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false (both roles; unchanged from C-2).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.machines', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.machines', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.machines', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.machines', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.machines', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.machines', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.machines', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.machines', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-2. machines policies after the drop.
--    Expected: exactly 2 rows -- machines_update and machines_write, both
--      UNCHANGED from the C-3 snapshot; machines_read_all = gone; total = 2.
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machines'
order by cmd, policyname;

select count(*) as policy_count   -- expect 2
from pg_policies
where schemaname = 'public'
  and tablename = 'machines';

-- P-3. machines table attributes UNCHANGED.
--    Expected: rls_enabled = true, rls_forced = false, owner = postgres.
select
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'machines';

-- P-4. read RPCs UNCHANGED and still executable by anon / authenticated.
--    Expected: same as C-4 / C-4b / C-4c (2 functions, SECURITY DEFINER, STABLE,
--      owner postgres, fixed search_path; anon / authenticated EXECUTE = true;
--      PUBLIC EXECUTE absent).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
order by p.proname;

select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_machines_secure(text)',                'EXECUTE') as can_execute_employee_rpc,
  has_function_privilege(v.grantee, 'public.list_machines_admin_secure(text, boolean)', 'EXECUTE') as can_execute_admin_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

select
  p.proname,
  acl.grantee::regrole::text as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
  and acl.grantee = 0    -- 0 = PUBLIC; expect 0 rows
order by p.proname, acl.privilege_type;

-- P-5. write RPCs UNCHANGED from the C-5 baseline.
--    Expected: 5 rows, identical to C-5.
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

-- P-6. machines row counts (REFERENCE ONLY -- NOT a pass / fail criterion).
--    Compare informally with C-6; a difference alone is NOT a failure.
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.machines;


-- ============================================================
-- SMOKE TEST (manual; performed by the user in the browser AFTER the body +
--   post-check; reload / re-login first so no cached data masks a failure)
--
--   Employee screen (index.html):
--     - machines tab: list, current locations, move, and settings modal all work.
--     - Network: list_machines_secure returns 200.
--     - Network: NO direct read of /rest/v1/machines.
--     - Console: no errors (including 'list_machines_secure failed:').
--
--   Admin screen (admin-app.html):
--     - machines page: full list incl. inactive rows (badge), edit modal opens
--       with correct values, "add machine" modal opens.
--     - Network: list_machines_admin_secure returns 200.
--     - Network: NO direct read of /rest/v1/machines.
--     - Console: no errors (including 'list_machines_admin_secure failed:').
--
--   Genka screen (genka-app.html):
--     - cost summary and machine lease cost figures unchanged / correct.
--     - Network: list_machines_admin_secure returns 200.
--     - Network: NO direct read of /rest/v1/machines.
--     - Console: no errors.
--
--   Direct read rejection check (optional; do NOT record any real token):
--     - From the browser Console in a logged-in app session (anon key context),
--       run e.g.:
--         const r = await sb.from('machines').select('id').limit(1);
--         console.log(r.error);
--       Expected: a permission-denied error object (e.g. "permission denied for
--       table machines"), data = null. This confirms the direct read path is shut.
--     - Equivalently in the SQL Editor (roles only; no app token involved):
--         select has_table_privilege('anon',          'public.machines', 'SELECT');
--         select has_table_privilege('authenticated', 'public.machines', 'SELECT');
--       Expected: false / false (same as P-1).
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Restores the direct SELECT grant and re-creates machines_read_all exactly as
--   recorded in the C-3 pre-check (PERMISSIVE / FOR SELECT / TO public /
--   USING (true)).
-- ============================================================
-- GRANT SELECT
-- ON TABLE public.machines
-- TO anon, authenticated;
--
-- CREATE POLICY machines_read_all
-- ON public.machines
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
-- ============================================================
