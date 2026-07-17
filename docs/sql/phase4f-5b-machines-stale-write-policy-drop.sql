-- ============================================================
-- Phase 4-F-5-b: machines stale/no-op write policy drop
--   (machines_update + machines_write)
--   Drop the two residual, no-op write policies on public.machines.
--   The anon / authenticated INSERT / UPDATE grants were revoked on 2026-06-19
--   (Phase 3-3 materials / machines direct write REVOKE), and the 2026-07-12
--   post-check of Phase 4-F-2B-5 re-measured all 8 table privileges as false
--   for both roles, so neither policy currently authorizes anything. They are
--   removed as defense-in-depth: if a write grant ever reappeared by mistake,
--   machines_write (WITH CHECK true) would silently allow every INSERT and
--   machines_update (USING true) would silently allow every UPDATE.
-- ============================================================
-- [STATUS] EXECUTED 2026-07-17
--   - The EXECUTION BODY was run exactly ONCE by the user (Supabase SQL
--     Editor, manual, 2026-07-17). DO NOT RE-RUN: a second run fails the
--     guard at G-2 (policies already dropped) by design (fail-closed).
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution /
--     NO Supabase CLI / NO psql.
--   - Run order (as designed): PRE-CHECK (C-1..C-8) -> EXECUTION GUARD + BODY
--     (single transaction) -> POST-CHECK (P-1..P-7) -> SMOKE TEST -> ROLLBACK
--     only in an emergency, with separate explicit approval.
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-17)
--     - The user ran the EXECUTION BODY manually, once, as a single
--       transaction (read-only GUARD DO block G-1..G-9 -> DROP POLICY
--       machines_update ON public.machines -> DROP POLICY machines_write
--       ON public.machines -> COMMIT).
--       Result: Success. No rows returned.
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--     - ROLLBACK: NOT executed (kept as commented reference only).
--
--   [POST-CHECK RESULT] (Supabase SQL Editor, 2026-07-17 -- reported items
--     only)
--     - P-1: machines policy_count = 0; machines_update_count = 0;
--       machines_write_count = 0; no unexpected policy.
--     - P-1b: public schema policy count = 27 (was 29 before the body;
--       exactly -2 = machines_update + machines_write only).
--     - P-3: anon / authenticated -- all 8 table privileges false
--       (16/16 items).
--     - P-4: table ACL entries for PUBLIC / anon / authenticated = 0;
--       column ACL entries for PUBLIC / anon / authenticated = 0.
--     - P-5: all 5 write RPCs unchanged -- create_machine_secure /
--       update_machine_secure / deactivate_machine_secure /
--       create_machine_admin_secure / update_machine_admin_secure; all
--       SECURITY DEFINER true, volatility 'v', owner postgres,
--       search_path=public, extensions, result type TABLE(id uuid);
--       management-session verification present in all 5; anon /
--       authenticated EXECUTE true for all 5 (10/10 items).
--     - P-5 (PUBLIC EXECUTE finding): PUBLIC EXECUTE = true on ALL 5 write
--       RPCs, unchanged by this step (this file performed no GRANT /
--       REVOKE; the state is pre-existing -- the Phase 3 definition files
--       never revoked PUBLIC). Recorded as a candidate for a SEPARATE later
--       step (same pattern as the 2B-6 side step that revoked PUBLIC on
--       create_machine_location_secure); NOT changed here per the approved
--       scope (record only).
--     - P-6: both read RPCs unchanged -- list_machines_secure(text) and
--       list_machines_admin_secure(text, boolean); both SECURITY DEFINER
--       true, STABLE, owner postgres.
--     - P-7: machines data unchanged (pre = post): total_rows 26,
--       active_rows 22, inactive_rows 4, null_active_rows 0,
--       earliest_created_at 2026-05-26 02:01:33.281736+00,
--       latest_created_at 2026-06-19 23:52:13.774825+00.
--
--   [SMOKE TEST RESULT] (2026-07-17; no real token value recorded)
--     - RPC negative: PASS -- invalid management session was rejected
--       without persisting a write.
--     - DB negative: PASS -- anon direct INSERT and anon direct UPDATE were
--       both rejected; transactions rolled back.
--     - Production read-only (browser): employee screen machines list
--       renders; admin screen machines list renders; list_machines_secure =
--       HTTP 200; list_machines_admin_secure = HTTP 200; NO direct REST
--       access to machines; no red console errors; NO write operation
--       performed.
--
--   [OUTCOME]
--     - machines_update / machines_write policies: DROPPED. machines policy
--       count: 0. public schema policy count: 29 -> 27.
--     - Table privileges / ACLs / write RPCs / read RPCs / data: unchanged.
--     - PUBLIC EXECUTE on the 5 write RPCs remains true (pre-existing;
--       untouched here) -- follow-up candidate for a separate step.
--     - Phase 4-F-5-b DB work is COMPLETE; the step closes when this
--       record's PR is merged to main. Phase 4-F as a whole is NOT
--       complete.
--
-- [PURPOSE]
--   - public.machines write access is already closed at the privilege layer:
--     anon / authenticated INSERT / UPDATE were revoked on 2026-06-19 (Phase
--     3-3) and all 8 privileges (SELECT / INSERT / UPDATE / DELETE / TRUNCATE /
--     REFERENCES / TRIGGER / MAINTAIN) were re-measured false for both roles on
--     2026-07-12 (Phase 4-F-2B-5 post-check).
--   - The application writes machines ONLY through 5 SECURITY DEFINER RPCs
--     (owner postgres; FORCE RLS false on the table, so the owner execution
--     path bypasses RLS and does NOT depend on these policies):
--       create_machine_secure / update_machine_secure /
--       deactivate_machine_secure / create_machine_admin_secure /
--       update_machine_admin_secure.
--   - Therefore machines_update (PERMISSIVE / {public} / UPDATE / USING true)
--     and machines_write (PERMISSIVE / {public} / INSERT / WITH CHECK true)
--     are stale no-op policies. Dropping them removes latent allow-all write
--     paths that would spring back to life if a write grant were ever re-added
--     by mistake.
--   - Same rationale and structure as Phase 4-F-5-a (ml_write drop; template:
--     docs/sql/phase4f-5a-machine-locations-stale-write-policy-drop.sql).
--
-- [SCOPE]
--   - public.machines policies machines_update and machines_write -- exactly
--     TWO policies. The ONLY DB-changing statements in this file are the two
--     DROP POLICY statements in the EXECUTION BODY.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - Table privileges (NO GRANT / NO REVOKE; anon / authenticated stay
--     all-false).
--   - RLS enabled state / FORCE RLS / table owner (unchanged).
--   - machines data (NO DML; the C-8 baseline must be unchanged in P-7).
--   - The 5 write RPCs and 2 read RPCs (definitions, attributes, EXECUTE ACLs
--     -- all unchanged).
--   - PUBLIC EXECUTE on the 5 write RPCs: the repo records contain NO
--     measurement for it (the Phase 3 definition files GRANT to anon /
--     authenticated but never REVOKE from PUBLIC, so the PostgreSQL default
--     PUBLIC EXECUTE may still be present). C-4d RECORDS the current state;
--     if PUBLIC EXECUTE is present, that is a FINDING for a separate,
--     later step (cf. the 2B-6 side step for machine_locations) -- this file
--     must NOT change it (per the approved policy: record only, do not fix).
--   - No CREATE / ALTER POLICY, no function DDL, no table DDL, no DML.
--   - front-end code, other tables, other policies, other roles' privileges.
--
-- [BASELINE] (real-DB measurements; re-verify ALL of it in PRE-CHECK below)
--   - Source: Phase 4-F-2B-5 pre/post-check (Supabase SQL Editor, 2026-07-12)
--     and Phase 4-F-5-a post-check P-1b (2026-07-16), recorded in
--     docs/db-migrations.md.
--   - machines: relkind 'r', RLS enabled true, FORCE RLS false, owner postgres.
--   - policy_count = 2; the only remaining policies are:
--       machines_update : PERMISSIVE / roles {public} / cmd UPDATE /
--                         qual true / with_check null.
--       machines_write  : PERMISSIVE / roles {public} / cmd INSERT /
--                         qual null / with_check true.
--     (machines_read_all was dropped by 2B-5 on 2026-07-12.)
--   - anon / authenticated: all 8 table privileges false.
--   - public schema total policy count = 29 (4-F-5-a P-1b, 2026-07-16).
--     Expected transition by this file: 29 -> 27.
--   - Write RPCs (5; all SECURITY DEFINER, VOLATILE, owner postgres,
--     search_path=public, extensions, result type TABLE(id uuid), session
--     verified FIRST via public._verify_management_session(session_token_input)
--     before any input validation or DML; GRANT EXECUTE to anon /
--     authenticated per the definition files):
--       create_machine_secure(text, text, text, text, date, date, integer)
--       update_machine_secure(text, uuid, text, text, text, date, date, integer)
--       deactivate_machine_secure(text, uuid)
--       create_machine_admin_secure(text, text, uuid, boolean, text, text,
--                                   date, date, integer)
--       update_machine_admin_secure(text, uuid, text, uuid, boolean, text,
--                                   text, date, date, integer)
--     Definition sources: docs/sql/materials-machines-secure-rpc.sql /
--     docs/sql/machines-admin-secure-rpc.sql. The session helper
--     public._verify_management_session(text) raises 'Invalid or expired
--     session' on failure (docs/sql/sites-site-assignments-secure-rpc.sql).
--   - Read RPCs (2; both SECURITY DEFINER, STABLE, owner postgres,
--     search_path=public, extensions; PUBLIC EXECUTE revoked at creation):
--       list_machines_secure(text)
--         -> TABLE(id uuid, name text, ownership text, lease_company text,
--                  lease_start date, lease_end date, lease_monthly integer)
--       list_machines_admin_secure(text, boolean)
--         -> TABLE(id uuid, name text, company_id uuid, ownership text,
--                  lease_company text, lease_start date, lease_end date,
--                  lease_monthly integer, is_active boolean)
--     Definition source: docs/sql/phase4f-2b-5-machines-read-rpc.sql.
--   - machines data reference values (2026-07-12; counts are NOT a fixed STOP
--     condition -- business rows may have changed): total 26, active 22,
--     inactive 4, null is_active 0.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo on 2026-07-17, main 1487b15;
--   SQL cannot check these -- recorded here as facts; see C-7)
--   - machines direct read / write via .from('machines') = 0 across the
--     front-end application code (index.html / admin-app.html /
--     genka-app.html).
--   - Write paths are ONLY the 5 RPCs:
--       index.html:1832  create_machine_secure
--       index.html:1842  deactivate_machine_secure
--       index.html:1881  update_machine_secure
--       admin-app.html:1586 update_machine_admin_secure
--       admin-app.html:1600 create_machine_admin_secure
--   - Read paths are ONLY the 2 read RPCs (list_machines_secure /
--     list_machines_admin_secure; 2B-5 production smoke 2026-07-12).
--   - No application or SQL code references the policy names
--     'machines_update' / 'machines_write' (docs/sql mentions are
--     baseline/records only).
--
-- [STOP CONDITIONS] (if any is hit during PRE-CHECK, do NOT run the body;
--   stop & report -- do NOT guess or "fix" divergence)
--   - C-1: machines missing, relkind <> 'r', RLS <> true, FORCE RLS <> false,
--          or owner <> postgres.
--   - C-2: ANY of the 8 privileges is true for anon or authenticated (an
--          unexpected live write grant means the policies are NOT no-ops --
--          this file must not run; a separate REVOKE design comes first).
--   - C-2b/C-2c/C-2d: any table ACL entry for PUBLIC / anon / authenticated,
--          any unexpected grantee, or any column-level ACL on the table.
--   - C-3: machines_update or machines_write missing (already dropped -> do
--          NOT re-run), duplicated, definition differing from the baseline,
--          any additional policy, or policy_count <> 2.
--   - C-3b: public schema policy count <> 29 (schema-level state has drifted
--          from the 2026-07-16 measurement -- reconcile first).
--   - C-4/C-4b/C-4c: any of the 5 write RPCs missing, overloaded, not
--          SECURITY DEFINER, not VOLATILE, owner not postgres, search_path not
--          fixed, identity arguments or result type differing, session
--          verification (_verify_management_session) not found in the body, or
--          anon / authenticated EXECUTE <> true.
--   - C-4d: RECORD the PUBLIC EXECUTE state (no repo baseline exists).
--          PUBLIC EXECUTE being present is NOT by itself a stop condition for
--          this drop (it is a separate finding; record it for a later step).
--          STOP only if the output contradicts C-4c (e.g. anon / authenticated
--          EXECUTE false) or shows grantees that make the recorded write-path
--          model wrong.
--   - C-5: either read RPC missing or differing (the app depends on them;
--          divergence from the recorded state must be reconciled first).
--   - C-6: any SECURITY INVOKER routine referencing machines, any view /
--          materialized view depending on it, or any user trigger on it.
--   - C-7: any front-end / repository precondition above is NOT satisfied.
--   - C-8: (data baseline) record the aggregates; they are the invariant vs
--          P-7. The absolute values are NOT a stop condition.
--
-- [ROLLBACK] (see the commented section at the end -- reference only)
--   Re-creates machines_update / machines_write exactly as measured in C-3.
--   Policy layer only; NO grant is restored. Requires separate explicit
--   approval. WARNING: rollback re-creates the latent allow-all write paths
--   this file removes.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. machines table attributes.
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
  and c.relname = 'machines';

-- C-2. anon / authenticated table grants on machines.
--    Expected: ALL 8 privileges false for BOTH roles (2B-5 post-check
--      baseline, 2026-07-12).
--    STOP if ANY privilege is true -- the policies would then NOT be no-ops.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this
--      project runs PG 17.x per the Phase 4-F-2A record).
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

-- C-2b. machines raw table ACL (relacl), ALL grantees.
--    Expected: entries for postgres (owner) and service_role ONLY.
--    STOP if PUBLIC (grantee 0), anon, authenticated, or any unexpected
--    grantee appears with ANY privilege.
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(
  coalesce(c.relacl, acldefault('r', c.relowner))
) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machines'
order by grantee, acl.privilege_type;

-- C-2c. information_schema.role_table_grants for machines.
--    Expected: 0 rows (the filter selects only PUBLIC / anon / authenticated
--      so any divergence is visible: STOP if any row appears).
select grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'machines'
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by grantee, privilege_type;

-- C-2d. column-level ACLs (attacl) on machines.
--    Expected: 0 rows (no column ACL exists at all on this table).
--    STOP if any row is returned (an unexpected column-level grant -- write or
--    read -- means the recorded baseline no longer holds).
select
  a.attname as column_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_attribute a
join pg_class c      on c.oid = a.attrelid
join pg_namespace n  on n.oid = c.relnamespace
cross join lateral aclexplode(a.attacl) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machines'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attname, grantee;

-- C-3. machines policies -- full definitions (also the ROLLBACK source).
--    Expected: exactly 2 rows, matching EXACTLY:
--      machines_write  : PERMISSIVE, roles {public}, cmd INSERT, qual null,
--                        with_check true.
--      machines_update : PERMISSIVE, roles {public}, cmd UPDATE, qual true,
--                        with_check null.
--    STOP if either policy is missing (already dropped -> do NOT run the
--    body), duplicated, or differing; if any additional policy exists; or if
--    policy_count <> 2.
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

select count(*) as policy_count   -- expect 2 (machines_update + machines_write)
from pg_policies
where schemaname = 'public'
  and tablename = 'machines';

-- C-3b. total policy count across schema public (whole-schema invariant).
--    Expected: 29 (Phase 4-F-5-a post-check P-1b, 2026-07-16). STOP and
--    reconcile if it differs (another change happened since that record).
--    P-1b after the body must equal EXACTLY this value - 2 (only the two
--    machines write policies disappear; no other table's policies are
--    touched). Expected transition: 29 -> 27.
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- C-4. write RPC baseline -- 5 functions (must be UNCHANGED in P-5).
--    Expected: EXACTLY 5 rows, one per function, each with
--      security_definer = true, volatility = 'v' (VOLATILE), owner = postgres,
--      config containing search_path=public, extensions,
--      result_type = TABLE(id uuid), and identity args:
--        create_machine_secure:
--          session_token_input text, name_input text, ownership_input text,
--          lease_company_input text, lease_start_input date,
--          lease_end_input date, lease_monthly_input integer
--        update_machine_secure:
--          session_token_input text, machine_id_input uuid, name_input text,
--          ownership_input text, lease_company_input text,
--          lease_start_input date, lease_end_input date,
--          lease_monthly_input integer
--        deactivate_machine_secure:
--          session_token_input text, machine_id_input uuid
--        create_machine_admin_secure:
--          session_token_input text, name_input text, company_id_input uuid,
--          is_active_input boolean, ownership_input text,
--          lease_company_input text, lease_start_input date,
--          lease_end_input date, lease_monthly_input integer
--        update_machine_admin_secure:
--          session_token_input text, machine_id_input uuid, name_input text,
--          company_id_input uuid, is_active_input boolean,
--          ownership_input text, lease_company_input text,
--          lease_start_input date, lease_end_input date,
--          lease_monthly_input integer
--    A 6th row would be an unexpected OVERLOAD -> STOP.
--    STOP if any function is missing or any attribute differs.
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
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;

-- C-4b. write RPC session verification is present in each function body.
--    Expected: 5 rows, has_mgmt_session_check = true for ALL.
--    (All 5 call public._verify_management_session(session_token_input) FIRST,
--     before any input validation or DML; the helper raises 'Invalid or
--     expired session' on failure. strpos is used instead of LIKE so the
--     underscores are matched literally.)
--    STOP if any row is false (the deployed function differs from the repo
--    definition).
select
  p.oid::regprocedure::text as function_signature,
  strpos(p.prosrc, '_verify_management_session') > 0 as has_mgmt_session_check
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;

-- C-4c. write RPC EXECUTE privileges (baseline; UNCHANGED in P-5).
--    Expected: 5 rows, anon_execute = true AND authenticated_execute = true
--      for ALL (per the GRANT statements in the definition files).
--    STOP if any is false.
select
  p.oid::regprocedure::text as function_signature,
  has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;

-- C-4d. write RPC PUBLIC EXECUTE state (RECORD ONLY -- no repo baseline).
--    The Phase 3 definition files (materials-machines-secure-rpc.sql /
--    machines-admin-secure-rpc.sql) GRANT EXECUTE to anon / authenticated but
--    contain NO "REVOKE ... FROM PUBLIC", so the PostgreSQL default PUBLIC
--    EXECUTE may still be present on these 5 functions (unlike the read RPCs,
--    which revoked PUBLIC at creation, and unlike
--    create_machine_location_secure, whose PUBLIC EXECUTE was revoked in the
--    2B-6 side step).
--    -> RECORD the output. If rows are returned (PUBLIC EXECUTE present),
--       that is a FINDING for a separate, later step -- per the approved
--       policy for this step it is recorded only and NOT changed here, and it
--       does NOT block this policy drop (function ACLs and table policies are
--       independent layers). The GUARD therefore does NOT assert a PUBLIC
--       EXECUTE value; P-5 re-runs this query and must return the IDENTICAL
--       result (this file must not change it).
--    STOP only if the output contradicts C-4c or the recorded write-path
--    model (see STOP CONDITIONS above).
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- C-5. read RPCs still exist (the app's read path; NOT touched by this file).
--    Expected: 2 rows --
--      list_machines_secure(text):
--        SECURITY DEFINER = true, volatility 's' (STABLE), owner postgres,
--        config search_path=public, extensions,
--        result_type = TABLE(id uuid, name text, ownership text,
--          lease_company text, lease_start date, lease_end date,
--          lease_monthly integer)
--      list_machines_admin_secure(text, boolean):
--        SECURITY DEFINER = true, volatility 's' (STABLE), owner postgres,
--        config search_path=public, extensions,
--        result_type = TABLE(id uuid, name text, company_id uuid,
--          ownership text, lease_company text, lease_start date,
--          lease_end date, lease_monthly integer, is_active boolean)
--    STOP if either is missing or differs (state diverged from the record).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid) as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machines_secure',
                    'list_machines_admin_secure')
order by p.proname;

-- C-6. dependency check: nothing besides the known SECURITY DEFINER RPCs may
--    depend on machines.
-- C-6a. SECURITY INVOKER routines whose source references machines.
--    Expected: 0 rows. STOP if any row is returned (an invoker-rights routine
--    could be affected by policy changes).
--    NOTE: the substring 'machines' does not occur in 'machine_locations', so
--    this filter does not produce machine_locations false positives.
select
  p.oid::regprocedure::text as function_signature,
  p.prosecdef               as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = false
  and p.prosrc ilike '%machines%'
order by function_signature;

-- C-6b. views / materialized views depending on machines.
--    Expected: 0 rows. STOP if any row is returned.
select distinct
  dep_n.nspname as view_schema,
  dep_c.relname as view_name,
  dep_c.relkind as relkind          -- 'v' = view, 'm' = materialized view
from pg_depend d
join pg_rewrite rw    on rw.oid = d.objid
join pg_class dep_c   on dep_c.oid = rw.ev_class
join pg_namespace dep_n on dep_n.oid = dep_c.relnamespace
join pg_class src_c   on src_c.oid = d.refobjid
join pg_namespace src_n on src_n.oid = src_c.relnamespace
where d.classid = 'pg_rewrite'::regclass
  and d.refclassid = 'pg_class'::regclass
  and src_n.nspname = 'public'
  and src_c.relname = 'machines'
  and dep_c.relname <> 'machines'
order by view_schema, view_name;

-- C-6c. user triggers on machines.
--    Expected: 0 rows. STOP if any row is returned.
select
  t.tgname as trigger_name,
  p.proname as trigger_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname = 'machines'
  and t.tgisinternal = false
order by t.tgname;

-- C-7. front-end / repository preconditions (NOT checkable from SQL; confirmed
--    from the repo BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html /
--    genka-app.html. Documentation string hits inside docs/sql are EXCLUDED
--    from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - machines direct read / write via .from('machines') = 0 in the
--      front-end application code (verified 2026-07-17, main 1487b15).
--    - The ONLY application write paths are the 5 write RPCs:
--      index.html:1832 create_machine_secure /
--      index.html:1842 deactivate_machine_secure /
--      index.html:1881 update_machine_secure /
--      admin-app.html:1586 update_machine_admin_secure /
--      admin-app.html:1600 create_machine_admin_secure.
--    - Reads go through list_machines_secure / list_machines_admin_secure
--      only (enforced by 2B-5 on 2026-07-12).
--    - No application or SQL code references the policy names
--      'machines_update' / 'machines_write' (docs/sql mentions are
--      baseline/records only).
--    - No view / materialized view / trigger creation on machines exists
--      anywhere in docs/sql.

-- C-8. machines data baseline (INVARIANT vs P-7).
--    Record all values. Reference values from 2026-07-12: total 26, active 22,
--    inactive 4, null_active 0 -- business rows may have changed since; ANY
--    current value is fine (the absolute numbers are NOT a stop condition).
--    The whole row only must be UNCHANGED by the body, which performs NO DML.
select
  count(*)                                  as total_rows,
  count(*) filter (where is_active = true)  as active_rows,
  count(*) filter (where is_active = false) as inactive_rows,
  count(*) filter (where is_active is null) as null_active_rows,
  min(created_at)                           as earliest_created_at,
  max(created_at)                           as latest_created_at
from public.machines;


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-8 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction as
--   the body: if any expectation fails, it RAISEs, the transaction aborts, and
--   NOTHING is changed (fail-closed). A second run fails the guard at G-2
--   (policies already dropped) before any statement that would modify state --
--   the body must NOT be re-run after success.
--   The ONLY DB-changing statements are the TWO DROP POLICY statements.
--   No GRANT / REVOKE, no CREATE / ALTER POLICY, no function DDL, no table
--   DDL, no DML.
--   DROP POLICY is used WITHOUT "IF EXISTS" on purpose: unexpected absence
--   must fail the whole transaction loudly instead of half-succeeding
--   silently (both drops commit together or neither does).
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
  rec   record;
begin
  -- G-1. table exists with expected attributes (relkind r, RLS on, NOT forced,
  --      owner postgres).
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'machines'
    and c.relkind = 'r'
    and c.relrowsecurity = true
    and c.relforcerowsecurity = false
    and pg_get_userbyid(c.relowner) = 'postgres';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-1): public.machines with relkind r / RLS on / FORCE off / owner postgres not found (count=%)', v_cnt;
  end if;

  -- G-2. machines_update and machines_write each exist exactly once (by name).
  --      0 rows means the body already ran (or the policy vanished) -> STOP,
  --      do NOT re-run; >1 is divergence.
  for rec in
    select t.pname
    from (values ('machines_update'), ('machines_write')) as t(pname)
  loop
    select count(*) into v_cnt
    from pg_policies
    where schemaname = 'public' and tablename = 'machines'
      and policyname = rec.pname;
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-2): % is MISSING -- body may have run before; reconcile, do NOT re-run', rec.pname;
    elsif v_cnt > 1 then
      raise exception 'GUARD STOP (G-2): % is DUPLICATED (% rows)', rec.pname, v_cnt;
    end if;
  end loop;

  -- G-3. both definitions match the baseline EXACTLY.
  --      machines_update: PERMISSIVE / {public} / UPDATE / qual true /
  --      with_check null.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machines'
    and policyname = 'machines_update'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'UPDATE'
    and qual       = 'true'
    and with_check is null;
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-3): machines_update DEFINITION DIFFERS from baseline PERMISSIVE/{public}/UPDATE/qual true/with_check null';
  end if;
  --      machines_write: PERMISSIVE / {public} / INSERT / qual null /
  --      with_check true.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machines'
    and policyname = 'machines_write'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'INSERT'
    and qual       is null
    and with_check = 'true';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-3): machines_write DEFINITION DIFFERS from baseline PERMISSIVE/{public}/INSERT/qual null/with_check true';
  end if;

  -- G-4. machines_update / machines_write are the ONLY policies on machines
  --      (no unexpected policy).
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machines';
  if v_cnt <> 2 then
    raise exception 'GUARD STOP (G-4): machines policy count = % (expected exactly 2: machines_update + machines_write)', v_cnt;
  end if;

  -- G-5. whole-schema invariant: public schema policy count = 29 (as measured
  --      2026-07-16, Phase 4-F-5-a P-1b). A different value means OTHER
  --      schema-level changes happened after this file was designed ->
  --      fail-closed STOP; reconcile (and update this file via a reviewed PR)
  --      before running. Do NOT loosen this check ad hoc.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public';
  if v_cnt <> 29 then
    raise exception 'GUARD STOP (G-5): public schema policy count = % (expected 29) -- schema state drifted from the designed baseline; reconcile before running', v_cnt;
  end if;

  -- G-6. anon / authenticated have NONE of the 8 table privileges. Any true
  --      privilege means the policies are NOT no-ops -> STOP (a REVOKE design
  --      would be needed first; that is NOT this file's scope).
  perform 1
  from (values ('anon'), ('authenticated')) as r(role_name)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                     ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(priv)
  where has_table_privilege(r.role_name, 'public.machines', p.priv);
  if found then
    raise exception 'GUARD STOP (G-6): anon/authenticated hold an unexpected table privilege on machines -- the policies are NOT no-ops; do NOT drop them in this state';
  end if;

  -- G-7. raw ACL: no table ACL entry of ANY kind for PUBLIC / anon /
  --      authenticated, and no column-level ACL at all.
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where n.nspname = 'public'
    and c.relname = 'machines'
    and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'));
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-7): unexpected table ACL entries for PUBLIC/anon/authenticated on machines (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_attribute a
  join pg_class c     on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'machines'
    and a.attnum > 0
    and not a.attisdropped
    and a.attacl is not null;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-7): unexpected column-level ACL on machines (% columns)', v_cnt;
  end if;

  -- G-8. the 5 write RPCs: exact signature, NO overload, SECURITY DEFINER,
  --      VOLATILE, owner postgres, fixed search_path, result type
  --      TABLE(id uuid), session verification present in the body
  --      (_verify_management_session, matched literally via strpos), and
  --      anon / authenticated EXECUTE = true.
  --      PUBLIC EXECUTE is deliberately NOT asserted here: the repo has no
  --      recorded baseline for it (see C-4d) -- it is recorded in PRE-CHECK,
  --      re-recorded in P-5, and must be handled (if present) in a separate
  --      step. This file must not change and does not depend on it.
  --      NOTE: the search_path comparison expects the recorded storage form
  --      'search_path=public, extensions'. If the guard stops here while C-4
  --      shows a correctly fixed search_path with only different spacing,
  --      STOP and report -- reconcile the baseline; do NOT loosen this check
  --      ad hoc.
  for rec in
    select t.fname, t.fsig, t.fargs
    from (values
      ('create_machine_secure',
       'public.create_machine_secure(text, text, text, text, date, date, integer)',
       'session_token_input text, name_input text, ownership_input text, lease_company_input text, lease_start_input date, lease_end_input date, lease_monthly_input integer'),
      ('update_machine_secure',
       'public.update_machine_secure(text, uuid, text, text, text, date, date, integer)',
       'session_token_input text, machine_id_input uuid, name_input text, ownership_input text, lease_company_input text, lease_start_input date, lease_end_input date, lease_monthly_input integer'),
      ('deactivate_machine_secure',
       'public.deactivate_machine_secure(text, uuid)',
       'session_token_input text, machine_id_input uuid'),
      ('create_machine_admin_secure',
       'public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer)',
       'session_token_input text, name_input text, company_id_input uuid, is_active_input boolean, ownership_input text, lease_company_input text, lease_start_input date, lease_end_input date, lease_monthly_input integer'),
      ('update_machine_admin_secure',
       'public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer)',
       'session_token_input text, machine_id_input uuid, name_input text, company_id_input uuid, is_active_input boolean, ownership_input text, lease_company_input text, lease_start_input date, lease_end_input date, lease_monthly_input integer')
    ) as t(fname, fsig, fargs)
  loop
    if to_regprocedure(rec.fsig) is null then
      raise exception 'GUARD STOP (G-8): % is missing', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-8): % has unexpected overloads (count=%, expected 1)', rec.fname, v_cnt;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname
      and p.prosecdef = true
      and p.provolatile = 'v'
      and pg_get_userbyid(p.proowner) = 'postgres'
      and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%'
      and pg_get_function_result(p.oid) = 'TABLE(id uuid)'
      and pg_get_function_identity_arguments(p.oid) = rec.fargs
      and strpos(p.prosrc, '_verify_management_session') > 0;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-8): % attributes/signature/session-check differ from the recorded baseline', rec.fname;
    end if;
    if not has_function_privilege('anon', to_regprocedure(rec.fsig), 'EXECUTE')
       or not has_function_privilege('authenticated', to_regprocedure(rec.fsig), 'EXECUTE') then
      raise exception 'GUARD STOP (G-8): anon/authenticated EXECUTE on % differs from the recorded baseline (expected true for both)', rec.fname;
    end if;
  end loop;

  -- G-9. both read RPCs still exist with the recorded attributes (the app
  --      depends on them; their absence signals divergence -- this file does
  --      not touch them).
  if    to_regprocedure('public.list_machines_secure(text)')                is null
     or to_regprocedure('public.list_machines_admin_secure(text, boolean)') is null then
    raise exception 'GUARD STOP (G-9): one or both machines read RPCs are missing';
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('list_machines_secure', 'list_machines_admin_secure')
    and p.prosecdef = true
    and p.provolatile = 's'
    and pg_get_userbyid(p.proowner) = 'postgres';
  if v_cnt <> 2 then
    raise exception 'GUARD STOP (G-9): machines read RPC attributes differ from the recorded baseline (matching count=%, expected 2)', v_cnt;
  end if;

  raise notice 'GUARD OK: state matches the expected baseline; proceeding to drop machines_update and machines_write';
end
$guard$;

-- BODY (EXACTLY TWO DB changes; no IF EXISTS -- unexpected absence must fail
-- the whole transaction; both drops commit together or neither does)

DROP POLICY machines_update ON public.machines;
DROP POLICY machines_write ON public.machines;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. machines policies after the drop.
--    Expected: 0 rows; policy_count = 0; machines_update_count = 0;
--      machines_write_count = 0 (both gone; nothing else existed).
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machines'
order by cmd, policyname;

select count(*) as policy_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'machines';

select
  count(*) filter (where policyname = 'machines_update') as machines_update_count,  -- expect 0
  count(*) filter (where policyname = 'machines_write')  as machines_write_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'machines';

-- P-1b. total policy count across schema public.
--    Expected: 27 -- EXACTLY the C-3b value (29) minus 2 (only the two
--      machines write policies disappeared; no other table's policies were
--      touched).
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- P-2. machines table attributes UNCHANGED.
--    Expected: relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres (same as C-1).
select
  c.relkind             as relkind,
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'machines';

-- P-3. anon / authenticated table grants UNCHANGED (all 8 privileges false;
--    this file performed NO GRANT / REVOKE).
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

-- P-4. raw table ACL / role_table_grants / column ACL UNCHANGED from
--    C-2b/C-2c/C-2d.
--    Expected: identical output to C-2b (postgres / service_role only);
--      0 rows for the C-2c filter; 0 rows for column ACLs.
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(
  coalesce(c.relacl, acldefault('r', c.relowner))
) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machines'
order by grantee, acl.privilege_type;

select grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'machines'
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by grantee, privilege_type;         -- expect 0 rows

select
  a.attname as column_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type
from pg_attribute a
join pg_class c      on c.oid = a.attrelid
join pg_namespace n  on n.oid = c.relnamespace
cross join lateral aclexplode(a.attacl) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'machines'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attname, grantee;              -- expect 0 rows

-- P-5. the 5 write RPCs UNCHANGED from the C-4 baseline.
--    Expected: 5 rows identical to C-4 (SECURITY DEFINER, VOLATILE, owner
--      postgres, fixed search_path, result_type TABLE(id uuid), same identity
--      args, no new overload); session check still present (C-4b);
--      anon / authenticated EXECUTE = true (C-4c); PUBLIC EXECUTE output
--      IDENTICAL to C-4d (whatever it was -- this file must not change it).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid)             as result_type,
  pg_get_function_identity_arguments(p.oid) as args,
  strpos(p.prosrc, '_verify_management_session') > 0 as has_mgmt_session_check,
  has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
order by p.proname;                       -- expect 5 rows, same as C-4/C-4b/C-4c

select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_machine_secure',
                    'update_machine_secure',
                    'deactivate_machine_secure',
                    'create_machine_admin_secure',
                    'update_machine_admin_secure')
  and acl.grantee = 0
  and acl.privilege_type = 'EXECUTE'
order by p.proname;                       -- expect IDENTICAL output to C-4d

-- P-6. read RPCs UNCHANGED (same as C-5).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid) as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_machines_secure',
                    'list_machines_admin_secure')
order by p.proname;                       -- expect 2 rows, same as C-5

-- P-7. machines data UNCHANGED from the C-8 baseline (INVARIANT).
--    Expected: every value equals C-8. The body performs no DML, so this must
--      match; any difference is external write activity, not this file.
select
  count(*)                                  as total_rows,
  count(*) filter (where is_active = true)  as active_rows,
  count(*) filter (where is_active = false) as inactive_rows,
  count(*) filter (where is_active is null) as null_active_rows,
  min(created_at)                           as earliest_created_at,
  max(created_at)                           as latest_created_at
from public.machines;


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   [DB negative -- direct INSERT / UPDATE stay impossible]
--     - Primary evidence: P-3 / P-4 (anon / authenticated INSERT / UPDATE =
--       false; no ACL entries). The privilege layer -- not the dropped
--       policies -- is what blocks direct writes, and it is proven unchanged.
--     - Optional live negative tests (safe by design -- each wrapped in a
--       transaction that is ALWAYS rolled back, so even an unexpected success
--       persists nothing; no real business values are used):
--         -- (a) anon direct INSERT
--         BEGIN;
--         SET LOCAL ROLE anon;
--         INSERT INTO public.machines (name) VALUES ('negative-smoke');
--         ROLLBACK;
--         -- (b) anon direct UPDATE
--         BEGIN;
--         SET LOCAL ROLE anon;
--         UPDATE public.machines SET is_active = is_active WHERE false;
--         ROLLBACK;
--       Expected: ERROR 42501 (permission denied for table machines) at the
--       INSERT / UPDATE statement; then run ROLLBACK to end the aborted
--       transaction. (The table ACL check fires at executor startup, BEFORE
--       any constraint or row evaluation -- the WHERE false in (b) does not
--       bypass it -- so no other error can precede 42501 while the privilege
--       is absent.)
--       If SET LOCAL ROLE anon fails in the SQL Editor session, skip this --
--       P-3 already proves the same fact via has_table_privilege.
--
--   [RPC negative -- invalid session is rejected; no data change]
--     - In the SQL Editor (uses a dummy literal, NOT a real token -- real
--       token values must never be recorded). deactivate_machine_secure is
--       chosen because its ONLY logic before the session check is nothing:
--       public._verify_management_session runs FIRST, before any input
--       validation or row lookup, so an invalid session can never reach the
--       UPDATE (and the random uuid matches no machine anyway):
--         select * from public.deactivate_machine_secure(
--           'invalid-token-for-negative-test',
--           gen_random_uuid());
--       Expected: ERROR 'Invalid or expired session' (raised by
--       _verify_management_session; see
--       docs/sql/sites-site-assignments-secure-rpc.sql). No row is changed.
--       Known risk: if the deployed function body had diverged (session check
--       no longer first), a different error could surface -- C-4b / G-8 guard
--       against that by verifying the session-check reference in prosrc
--       before the body.
--
--   [Production read-only check (browser; no writes)]
--     - Employee screen (index.html): login succeeds; machines tab renders
--       (machine list + settings list).
--     - Admin screen (admin-app.html) and/or genka screen (genka-app.html)
--       as needed: machines list renders (including inactive machines on the
--       admin screen).
--     - Network: list_machines_secure = HTTP 200; list_machines_admin_secure
--       = HTTP 200 (where the screen calls it); NO direct
--       /rest/v1/machines read or write.
--     - Console: no red errors.
--     - NO write operation (create / update / deactivate) is performed.
--
--   [Write positive -- NOT performed by default]
--     - Creating or updating a real machine just to test would create a
--       throwaway business row / change; do NOT do it. P-5 (write RPC
--       attributes / EXECUTE unchanged) plus the invalid-session negative
--       above stand in as the write-path evidence.
--     - The next genuine machine create / update (performed by an admin in
--       normal use) serves as the real positive check; if it failed, evaluate
--       ROLLBACK.
--     - If an explicit positive write test is ever wanted, it requires the
--       user's separate explicit approval first.
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; requires the user's separate
--   explicit approval; NEVER run in the same session/flow as the body)
--   Re-creates machines_update / machines_write EXACTLY as measured in the
--   C-3 pre-check:
--     machines_update: PERMISSIVE / FOR UPDATE / TO public / USING (true)
--     machines_write : PERMISSIVE / FOR INSERT / TO public / WITH CHECK (true)
--   Policy layer ONLY: NO table privilege is granted back, NO RPC / RLS /
--   owner change. Re-confirm the current state (C-1..C-3) before using this.
--   WARNING: restoring these policies re-creates the latent allow-all write
--   paths this file removed -- if any write grant later reappeared for anon /
--   authenticated, direct INSERT / UPDATE would be open again. Normally
--   unnecessary: the application write path (the 5 SECURITY DEFINER RPCs,
--   owner postgres, FORCE RLS false) does not depend on these policies.
-- ============================================================
-- BEGIN;
--
-- CREATE POLICY machines_update
-- ON public.machines
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY machines_write
-- ON public.machines
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- COMMIT;
-- ============================================================
