-- ============================================================
-- Phase 4-F-5-a: machine_locations stale/no-op write policy drop (ml_write)
--   Drop the residual, no-op INSERT policy ml_write on public.machine_locations.
--   The anon / authenticated INSERT grant was revoked on 2026-05-31
--   (machine_locations secure RPC + REVOKE), and the 2026-07-13 post-check of
--   Phase 4-F-2B-6 re-measured all 8 table privileges as false for both roles,
--   so ml_write currently authorizes nothing. It is removed as defense-in-depth:
--   if a write grant ever reappeared by mistake, ml_write (WITH CHECK true)
--   would silently allow every INSERT.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file has NOT been run. Phase 4-F-5-a is NOT complete.
--     Phase 4-F as a whole is NOT complete.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution /
--     NO Supabase CLI / NO psql.
--   - The EXECUTION BODY is run exactly ONCE, only after review and only after
--     the PRE-CHECK (C-1..C-8) passes with no STOP condition hit.
--   - Run this file SECTION BY SECTION in this order:
--     PRE-CHECK (C-1..C-8) -> EXECUTION GUARD + BODY (single transaction) ->
--     POST-CHECK (P-1..P-7) -> SMOKE TEST -> ROLLBACK only in an emergency,
--     with separate explicit approval.
--
-- [PURPOSE]
--   - public.machine_locations write access is already closed at the privilege
--     layer: anon / authenticated INSERT / UPDATE were revoked 2026-05-31 and all
--     8 privileges (SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--     TRIGGER / MAINTAIN) were re-measured false on 2026-07-13 (2B-6 P-1).
--   - The application writes machine_locations ONLY through the SECURITY DEFINER
--     RPC create_machine_location_secure(text, uuid, uuid, text) (owner postgres;
--     FORCE RLS false on the table, so the owner execution path bypasses RLS and
--     does NOT depend on ml_write).
--   - Therefore ml_write (PERMISSIVE / {public} / INSERT / WITH CHECK true) is a
--     stale no-op policy. Dropping it removes a latent allow-all INSERT path that
--     would spring back to life if a write grant were ever re-added by mistake.
--   - Same rationale as Phase 4-F-3 (cc_select / sc_select stale policy drop).
--
-- [SCOPE]
--   - public.machine_locations policy ml_write -- exactly ONE policy.
--   - The ONLY DB-changing statement in this file is:
--       DROP POLICY ml_write ON public.machine_locations;
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - Table privileges (NO GRANT / NO REVOKE; anon / authenticated stay all-false).
--   - RLS enabled state / FORCE RLS / table owner (unchanged).
--   - machine_locations data (NO DML; row count must be unchanged -- C-8 / P-7).
--   - write RPC create_machine_location_secure(text, uuid, uuid, text)
--     (definition, attributes, EXECUTE ACL -- all unchanged).
--   - read RPCs list_machine_current_locations_secure(text) /
--     list_machine_location_history_secure(text, uuid) (unchanged).
--   - No CREATE / ALTER POLICY, no function DDL, no table DDL, no DML.
--   - front-end code, other tables, other policies, other roles' privileges.
--
-- [BASELINE] (real-DB measurements, Supabase SQL Editor, 2026-07-13 -- Phase
--   4-F-2B-6 post-check P-1..P-6; re-verify ALL of it in PRE-CHECK below)
--   - machine_locations: relkind 'r', RLS enabled true, FORCE RLS false,
--     owner postgres.
--   - policy_count = 1; the only remaining policy is ml_write:
--       PERMISSIVE / roles {public} / cmd INSERT / qual null / with_check true.
--     (ml_read was dropped by 2B-6 on 2026-07-13.)
--   - anon / authenticated: all 8 table privileges false.
--   - create_machine_location_secure(text, uuid, uuid, text): SECURITY DEFINER,
--     VOLATILE, owner postgres, search_path=public, extensions,
--     result type TABLE(id uuid); anon / authenticated EXECUTE = true;
--     PUBLIC EXECUTE = 0 rows.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo BEFORE this file; SQL cannot
--   check these -- recorded here as facts; see C-7)
--   - machine_locations direct write (.insert / .update / .delete / .upsert) = 0
--     in the front-end application code (index.html / admin-app.html /
--     genka-app.html). admin-app.html / genka-app.html do not reference
--     machine_locations at all.
--   - The only write path is index.html confirmMachineMove() ->
--     sb.rpc('create_machine_location_secure', {session_token_input,
--     machine_id_input, site_id_input, memo_input}) (index.html:2227).
--   - Read paths are the 2 read RPCs (index.html:2075 / index.html:2183).
--   - No view / materialized view / trigger creation on machine_locations exists
--     anywhere in docs/sql; no code references the policy name ml_write.
--
-- [STOP CONDITIONS] (if any is hit during PRE-CHECK, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence)
--   - C-1: machine_locations missing, relkind <> 'r', RLS <> true,
--          FORCE RLS <> false, or owner <> postgres.
--   - C-2: ANY of the 8 privileges is true for anon or authenticated (an
--          unexpected live write grant means ml_write is NOT a no-op -- this
--          file must not run; a separate REVOKE design would be needed first).
--   - C-2b/C-2c/C-2d: any table ACL entry for PUBLIC / anon / authenticated,
--          any unexpected grantee, or any column-level ACL on the table.
--   - C-3: ml_write missing (already dropped -> do NOT re-run), duplicated,
--          definition differing from the baseline, any additional policy,
--          or policy_count <> 1.
--   - C-4: create_machine_location_secure missing, overloaded (<> 1 function
--          with that name), not SECURITY DEFINER, not VOLATILE, owner not
--          postgres, search_path not fixed to public, extensions, identity
--          arguments or result type differing, session verification not found
--          in the function body, anon / authenticated EXECUTE <> true, or
--          PUBLIC EXECUTE present.
--   - C-5: either read RPC missing (the app depends on them; their absence
--          signals divergence from the recorded state).
--   - C-6: any SECURITY INVOKER routine referencing machine_locations, any
--          view / materialized view depending on it, or any user trigger on it.
--   - C-7: any front-end / repository precondition above is NOT satisfied.
--   - C-8: (data baseline) record the row count; it is the invariant vs P-7.
--
-- [ROLLBACK] (see the commented section at the end -- reference only)
--   Re-creates ml_write exactly as measured in C-3. Policy layer only; NO grant
--   is restored. Requires separate explicit approval. WARNING: rollback
--   re-creates the latent allow-all INSERT path this file removes.
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
--    Expected: ALL 8 privileges false for BOTH roles (2B-6 P-1 baseline).
--    STOP if ANY privilege is true -- ml_write would then NOT be a no-op.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this
--      project runs PG 17.x per the Phase 4-F-2A record).
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

-- C-2b. machine_locations raw table ACL (relacl), ALL grantees.
--    Expected: entries for postgres (owner) and service_role ONLY.
--    STOP if PUBLIC (grantee 0), anon, authenticated, or any unexpected grantee
--    appears with ANY privilege.
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
  and c.relname = 'machine_locations'
order by grantee, acl.privilege_type;

-- C-2c. information_schema.role_table_grants for machine_locations.
--    Expected: 0 rows for PUBLIC / anon / authenticated (grants exist only for
--      postgres / service_role, which this query filters IN so divergence is
--      visible: STOP if anon / authenticated / PUBLIC appears).
select grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'machine_locations'
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by grantee, privilege_type;

-- C-2d. column-level ACLs (attacl) on machine_locations.
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
  and c.relname = 'machine_locations'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attname, grantee;

-- C-3. machine_locations policies -- full definitions (also the ROLLBACK source).
--    Expected: exactly 1 row, matching EXACTLY:
--      ml_write : PERMISSIVE, roles {public}, cmd INSERT, qual null,
--                 with_check true.
--    STOP if ml_write is missing (already dropped -> do NOT run the body),
--    duplicated, or differing; if any additional policy exists; or if
--    policy_count <> 1.
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

select count(*) as policy_count   -- expect 1 (ml_write only)
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations';

-- C-3b. total policy count across schema public (whole-schema invariant).
--    Record the value; P-1b after the body must equal EXACTLY this value - 1
--    (only ml_write disappears; no other table's policies are touched).
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- C-4. write RPC baseline (must be UNCHANGED in P-5).
--    Expected: EXACTLY 1 row --
--      create_machine_location_secure(text, uuid, uuid, text),
--      security_definer = true, volatility = 'v' (VOLATILE), owner = postgres,
--      config contains search_path=public, extensions,
--      result_type = TABLE(id uuid),
--      args = session_token_input text, machine_id_input uuid,
--             site_id_input uuid, memo_input text.
--    A second row would be an unexpected OVERLOAD -> STOP.
--    STOP if missing or any attribute differs.
--    (Definition source: docs/sql/machine-location-secure-rpc.sql -- session is
--     verified FIRST against employee_sessions joined to employees.is_active,
--     before any argument validation; moved_by is resolved server-side.)
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
order by function_signature;

-- C-4b. write RPC session verification is present in the function body.
--    Expected: 1 row, has_session_check = true, has_session_error = true.
--    STOP if false (the deployed function would differ from the repo definition).
select
  p.oid::regprocedure::text as function_signature,
  p.prosrc like '%employee_sessions%'            as has_session_check,
  p.prosrc like '%Invalid or expired session%'   as has_session_error
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure';

-- C-4c. write RPC EXECUTE privileges (baseline; UNCHANGED in P-5).
--    Expected: anon = true, authenticated = true.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute_write_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;

-- C-4d. write RPC PUBLIC EXECUTE is absent (baseline; UNCHANGED in P-5).
--    Expected: 0 rows (PUBLIC EXECUTE was revoked in the 2B-6 side step).
--    STOP if any row is returned.
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

-- C-5. read RPCs still exist (the app's read path; NOT touched by this file).
--    Expected: 2 rows, SECURITY DEFINER = true, volatility 's' (STABLE),
--      owner postgres, search_path fixed.
--    STOP if either is missing or differs (state diverged from the record).
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

-- C-6. dependency check: nothing besides the 3 known SECURITY DEFINER RPCs may
--    depend on machine_locations.
-- C-6a. SECURITY INVOKER routines whose source references machine_locations.
--    Expected: 0 rows. STOP if any row is returned (an invoker-rights routine
--    could be affected by policy changes).
select
  p.oid::regprocedure::text as function_signature,
  p.prosecdef               as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = false
  and p.prosrc ilike '%machine_locations%'
order by function_signature;

-- C-6b. views / materialized views depending on machine_locations.
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
  and src_c.relname = 'machine_locations'
  and dep_c.relname <> 'machine_locations'
order by view_schema, view_name;

-- C-6c. user triggers on machine_locations.
--    Expected: 0 rows. STOP if any row is returned.
select
  t.tgname as trigger_name,
  p.proname as trigger_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname = 'machine_locations'
  and t.tgisinternal = false
order by t.tgname;

-- C-7. front-end / repository preconditions (NOT checkable from SQL; confirmed
--    from the repo BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html / genka-app.html.
--    Documentation string hits inside docs/sql are EXCLUDED from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - machine_locations direct write (insert / update / delete / upsert) = 0 in
--      the front-end application code.
--    - machine_locations direct read = 0 in the front-end application code
--      (already enforced by 2B-6; reads go through the 2 read RPCs).
--    - index.html confirmMachineMove() calls create_machine_location_secure
--      (index.html:2227) -- the ONLY application write path; unchanged.
--    - No application or SQL code references the policy name 'ml_write'
--      (docs/sql mentions are baseline/records only).
--    - No view / materialized view / trigger creation on machine_locations
--      exists anywhere in docs/sql.

-- C-8. machine_locations data baseline (INVARIANT vs P-7).
--    Record total_rows (last recorded 2026-07-13: 42; new business rows may have
--    been added since -- any current value is fine; it only must be UNCHANGED by
--    the body, which performs NO DML).
select count(*) as total_rows
from public.machine_locations;


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-8 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction as
--   the body: if any expectation fails, it RAISEs, the transaction aborts, and
--   NOTHING is changed (fail-closed). A second run fails the guard at G-2
--   (ml_write already dropped) before any statement that would modify state --
--   the body must NOT be re-run after success.
--   The ONLY DB-changing statement is ONE DROP POLICY. No GRANT / REVOKE,
--   no CREATE / ALTER POLICY, no function DDL, no table DDL, no DML.
--   DROP POLICY is used WITHOUT "IF EXISTS" on purpose: unexpected absence must
--   fail the transaction loudly instead of half-succeeding silently.
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
begin
  -- G-1. table exists with expected attributes (relkind r, RLS on, NOT forced,
  --      owner postgres).
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'machine_locations'
    and c.relkind = 'r'
    and c.relrowsecurity = true
    and c.relforcerowsecurity = false
    and pg_get_userbyid(c.relowner) = 'postgres';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-1): public.machine_locations with relkind r / RLS on / FORCE off / owner postgres not found (count=%)', v_cnt;
  end if;

  -- G-2. ml_write exists exactly once (by name). 0 rows means the body already
  --      ran (or the policy vanished) -> STOP, do NOT re-run; >1 is divergence.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machine_locations'
    and policyname = 'ml_write';
  if v_cnt = 0 then
    raise exception 'GUARD STOP (G-2): ml_write is MISSING -- body may have run before; reconcile, do NOT re-run';
  elsif v_cnt > 1 then
    raise exception 'GUARD STOP (G-2): ml_write is DUPLICATED (% rows)', v_cnt;
  end if;

  -- G-3. ml_write definition matches the baseline EXACTLY
  --      (PERMISSIVE / {public} / INSERT / qual null / with_check true).
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machine_locations'
    and policyname = 'ml_write'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'INSERT'
    and qual       is null
    and with_check = 'true';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-3): ml_write DEFINITION DIFFERS from baseline PERMISSIVE/{public}/INSERT/qual null/with_check true';
  end if;

  -- G-4. ml_write is the ONLY policy on machine_locations (no unexpected policy).
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'machine_locations';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-4): machine_locations policy count = % (expected exactly 1: ml_write)', v_cnt;
  end if;

  -- G-5. anon / authenticated have NONE of the 8 table privileges. Any true
  --      privilege means ml_write is NOT a no-op -> STOP (a REVOKE design would
  --      be needed first; that is NOT this file's scope).
  perform 1
  from (values ('anon'), ('authenticated')) as r(role_name)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                     ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(priv)
  where has_table_privilege(r.role_name, 'public.machine_locations', p.priv);
  if found then
    raise exception 'GUARD STOP (G-5): anon/authenticated hold an unexpected table privilege on machine_locations -- ml_write is NOT a no-op; do NOT drop it in this state';
  end if;

  -- G-6. raw ACL: no table ACL entry of ANY kind for PUBLIC / anon /
  --      authenticated, and no column-level ACL at all.
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where n.nspname = 'public'
    and c.relname = 'machine_locations'
    and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'));
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-6): unexpected table ACL entries for PUBLIC/anon/authenticated on machine_locations (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_attribute a
  join pg_class c     on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'machine_locations'
    and a.attnum > 0
    and not a.attisdropped
    and a.attacl is not null;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-6): unexpected column-level ACL on machine_locations (% columns)', v_cnt;
  end if;

  -- G-7. write RPC create_machine_location_secure: exact signature, NO overload,
  --      SECURITY DEFINER, VOLATILE, owner postgres, fixed search_path, result
  --      type TABLE(id uuid), session verification present in the body.
  --      NOTE: the search_path comparison below expects the recorded storage form
  --      'search_path=public, extensions' (as shown by C-4). If the guard stops
  --      here while the C-4 output shows a correctly fixed search_path with only
  --      different spacing, STOP and report -- reconcile the baseline; do NOT
  --      loosen this check ad hoc.
  if to_regprocedure('public.create_machine_location_secure(text, uuid, uuid, text)') is null then
    raise exception 'GUARD STOP (G-7): create_machine_location_secure(text, uuid, uuid, text) is missing';
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_machine_location_secure';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7): create_machine_location_secure has unexpected overloads (count=%, expected 1)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_machine_location_secure'
    and p.prosecdef = true
    and p.provolatile = 'v'
    and pg_get_userbyid(p.proowner) = 'postgres'
    and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%'
    and pg_get_function_result(p.oid) = 'TABLE(id uuid)'
    and pg_get_function_identity_arguments(p.oid)
        = 'session_token_input text, machine_id_input uuid, site_id_input uuid, memo_input text'
    and p.prosrc like '%employee_sessions%'
    and p.prosrc like '%Invalid or expired session%';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7): create_machine_location_secure attributes/signature/session-check differ from the recorded baseline';
  end if;

  -- G-8. both read RPCs still exist (the app depends on them; their absence
  --      signals divergence -- this file does not touch them).
  if    to_regprocedure('public.list_machine_current_locations_secure(text)')      is null
     or to_regprocedure('public.list_machine_location_history_secure(text, uuid)') is null then
    raise exception 'GUARD STOP (G-8): one or both machine_locations read RPCs are missing';
  end if;

  raise notice 'GUARD OK: state matches the expected baseline; proceeding to DROP POLICY ml_write';
end
$guard$;

-- BODY (EXACTLY ONE DB change; no IF EXISTS -- unexpected absence must fail the
-- whole transaction)

DROP POLICY ml_write
ON public.machine_locations;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. machine_locations policies after the drop.
--    Expected: 0 rows; policy_count = 0 (ml_write gone; nothing else existed).
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations'
order by cmd, policyname;

select count(*) as policy_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'machine_locations';

-- P-1b. total policy count across schema public.
--    Expected: EXACTLY the C-3b value minus 1 (only ml_write disappeared;
--      no other table's policies were touched).
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- P-2. machine_locations table attributes UNCHANGED.
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
  and c.relname = 'machine_locations';

-- P-3. anon / authenticated table grants UNCHANGED (all 8 privileges false;
--    this file performed NO GRANT / REVOKE).
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

-- P-4. raw table ACL / role_table_grants / column ACL UNCHANGED from C-2b/C-2c/C-2d.
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
  and c.relname = 'machine_locations'
order by grantee, acl.privilege_type;

select grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'machine_locations'
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
  and c.relname = 'machine_locations'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attname, grantee;              -- expect 0 rows

-- P-5. write RPC UNCHANGED from the C-4 baseline.
--    Expected: create_machine_location_secure(text, uuid, uuid, text) identical
--      to C-4 (SECURITY DEFINER, VOLATILE, owner postgres, fixed search_path,
--      result_type TABLE(id uuid), same identity args, exactly 1 function);
--      session check still present (C-4b); anon / authenticated EXECUTE = true
--      (C-4c); PUBLIC EXECUTE = 0 rows (C-4d).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid)             as result_type,
  pg_get_function_identity_arguments(p.oid) as args,
  p.prosrc like '%employee_sessions%'          as has_session_check
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
order by function_signature;              -- expect exactly 1 row, same as C-4

select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute_write_rpc
from (values ('anon'), ('authenticated')) as v(grantee)
order by v.grantee;                       -- expect true / true

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = 'create_machine_location_secure'
  and acl.grantee = 0
  and acl.privilege_type = 'EXECUTE'
order by p.proname;                       -- expect 0 rows

-- P-6. read RPCs UNCHANGED (same as C-5).
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
order by p.proname;                       -- expect 2 rows, same as C-5

-- P-7. machine_locations data UNCHANGED from the C-8 baseline (INVARIANT).
--    Expected: total_rows equals C-8. The body performs no DML, so this must
--      match; any difference is external write activity, not this file.
select count(*) as total_rows
from public.machine_locations;


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   [DB negative -- direct INSERT stays impossible]
--     - Primary evidence: P-3 / P-4 (anon / authenticated INSERT = false; no
--       ACL entries). The privilege layer -- not the dropped policy -- is what
--       blocks direct writes, and it is proven unchanged.
--     - Optional live negative test (safe by design -- wrapped in a transaction
--       that is ALWAYS rolled back, so even an unexpected success persists
--       nothing; the dummy uuid also matches no machine, so the RPC-layer FK
--       validation would reject it anyway):
--         BEGIN;
--         SET LOCAL ROLE anon;
--         INSERT INTO public.machine_locations (machine_id)
--         VALUES (gen_random_uuid());
--         ROLLBACK;
--       Expected: ERROR 42501 (permission denied for table machine_locations)
--       at the INSERT; then run ROLLBACK to end the aborted transaction.
--       (The table ACL check fires at executor startup, BEFORE any NOT NULL /
--       FK constraint evaluation, so no other error can precede 42501 while
--       the INSERT privilege is absent.)
--       If SET LOCAL ROLE anon fails in the SQL Editor session, skip this --
--       P-3 already proves the same fact via has_table_privilege.
--
--   [RPC negative -- invalid session is rejected; no data change]
--     - In the SQL Editor (uses a dummy literal, NOT a real token -- real token
--       values must never be recorded):
--         select * from public.create_machine_location_secure(
--           'invalid-token-for-negative-test',
--           gen_random_uuid(), null, null);
--       Expected: ERROR 'Invalid or expired session'.
--       The function verifies the session FIRST (before machine validation --
--       see docs/sql/machine-location-secure-rpc.sql), so no row is inserted
--       and the random machine uuid is never reached. Known risk: if the
--       deployed function body had diverged (session check no longer first),
--       a different error could surface -- C-4b guards against that by
--       verifying the session-check strings in prosrc before the body.
--
--   [Production read-only check (browser; no writes)]
--     - Employee screen (index.html): login succeeds; machines tab renders
--       (list + current location); move-history modal opens.
--     - Network: list_machine_current_locations_secure = 200;
--       list_machine_location_history_secure = 200 (on opening a move);
--       NO direct /rest/v1/machine_locations read or write.
--     - Console: no errors.
--
--   [Write positive -- NOT performed by default]
--     - Recording a real machine move just to test would create a throwaway
--       business row; do NOT do it. P-5 (write RPC attributes / EXECUTE
--       unchanged) plus the invalid-session negative above stand in as the
--       write-path evidence.
--     - The next genuine business move (recorded by an employee in normal use)
--       serves as the real positive check; if it failed, evaluate ROLLBACK.
--     - If an explicit positive write test is ever wanted, it requires the
--       user's separate explicit approval first.
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; requires the user's separate
--   explicit approval; NEVER run in the same session/flow as the body)
--   Re-creates ml_write EXACTLY as measured in the C-3 pre-check
--   (PERMISSIVE / FOR INSERT / TO public / WITH CHECK (true)).
--   Policy layer ONLY: NO table privilege is granted back, NO RPC / RLS /
--   owner change. Re-confirm the current state (C-1..C-3) before using this.
--   WARNING: restoring ml_write re-creates the latent allow-all INSERT path
--   this file removed -- if any write grant later reappears for anon /
--   authenticated, direct INSERT would be open again. Normally unnecessary:
--   the application write path (create_machine_location_secure, SECURITY
--   DEFINER, owner postgres, FORCE RLS false) does not depend on ml_write.
-- ============================================================
-- BEGIN;
--
-- CREATE POLICY ml_write
-- ON public.machine_locations
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- COMMIT;
-- ============================================================
