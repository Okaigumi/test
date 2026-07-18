-- ============================================================
-- Phase 4-F-6-b: session RPC PUBLIC EXECUTE revoke (4 functions)
--   Revoke the explicit PUBLIC EXECUTE grant from the 4 SECURITY DEFINER
--   session RPCs (login / logout). Phase 4-F-6-a already revoked PUBLIC on
--   the 32 write/admin RPCs; after 6-a, PUBLIC EXECUTE remained true on
--   EXACTLY these 4 session RPCs (confirmed by the 2026-07-18 surveys and the
--   6-b pre-design check). This step removes PUBLIC from them too, which
--   brings the public-schema SECURITY DEFINER PUBLIC-EXECUTE count to 0 and
--   completes the cross-cutting PUBLIC EXECUTE cleanup.
--   Same change class and structure as Phase 4-F-4-a (notices) and
--   Phase 4-F-6-a (write/admin RPCs).
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - The EXECUTION BODY must be run exactly ONCE by the user (Supabase SQL
--     Editor, manual). DO NOT RE-RUN after success: a second run fails the
--     guard at G-2/G-3 (PUBLIC already revoked on the targets) by design
--     (fail-closed).
--   - DB execution is done by the user, manually, in the Supabase SQL
--     Editor. Claude Code CLI performs NO DB connection / NO SQL execution /
--     NO Supabase CLI / NO psql.
--   - Run order: PRE-CHECK (C-1..C-5) -> EXECUTION GUARD + BODY (single
--     transaction) -> POST-CHECK (P-1..P-3) -> SMOKE TEST -> ROLLBACK only
--     in an emergency, with separate explicit approval.
--   - Recording the execution (STATUS -> EXECUTED, db-migrations.md append)
--     is a SEPARATE step / separate PR.
--
-- [WHY LOGIN / LOGOUT IS UNAFFECTED]
--   - The three front-ends (index.html / admin-app.html / genka-app.html)
--     each create a single Supabase client with the ANON publishable key and
--     NEVER call supabase.auth.signIn / setSession -- there is NO switch to
--     the authenticated PostgREST role. Every request (login and everything
--     after) runs as the anon role, passing the app's own session token as
--     an RPC argument. So the ANON explicit EXECUTE grant is the login/logout
--     lifeline.
--   - has_function_privilege('anon', ...) can be true EITHER via an explicit
--     anon ACL entry OR via a PUBLIC entry. The 2026-07-18 check confirmed
--     ALL 4 targets carry EXPLICIT anon and authenticated EXECUTE entries in
--     proacl (in addition to the explicit PUBLIC entry).
--   - REVOKE ... FROM PUBLIC removes ONLY the PUBLIC entry; the anon /
--     authenticated entries are untouched, so the effective EXECUTE for both
--     client roles is unchanged. The guard verifies the explicit entries per
--     function BEFORE the body (G-3) and the post-check proves them unchanged
--     after (P-2) -- both at the ACL level (aclexplode) and the effective
--     level (has_function_privilege). A dedicated login/logout smoke on all
--     3 screens is REQUIRED after the body.
--
-- [SCOPE] (exactly 4 functions; the ONLY DB-changing statements are the 4
--   REVOKE EXECUTE ... FROM PUBLIC statements in the body)
--     create_admin_session(uuid, text)     -- admin login  (admin-app / genka)
--     revoke_admin_session(text)           -- admin logout (admin-app / genka)
--     create_employee_session(uuid, text)  -- employee login  (index)
--     revoke_employee_session(text)        -- employee logout (index)
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - anon / authenticated EXECUTE grants (NO GRANT / NO REVOKE on them).
--   - Function definitions (no CREATE OR REPLACE / ALTER / DROP FUNCTION).
--   - Tables / views / policies / RLS / session data (no DDL besides the
--     REVOKEs, no DML). Login/logout at smoke time will insert/delete
--     session-token rows -- that is the apps' own behaviour, NOT this file.
--   - front-end code.
--   - The 32 write/admin RPCs already handled by Phase 4-F-6-a.
--
-- [BASELINE] (real-DB measurements, Supabase SQL Editor, 2026-07-18 -- the
--   6-b pre-design check (SQL A..D), all passed; re-verify ALL in PRE-CHECK)
--   - public schema SECURITY DEFINER functions: 78 total.
--   - PUBLIC EXECUTE effective true: 4 = EXACTLY these 4 session RPCs (set
--     match confirmed; SQL C-2 returned 0 rows). Expected transition by this
--     file: 4 -> 0.
--   - All 4 targets: plpgsql, owner postgres, SECURITY DEFINER, VOLATILE,
--     search_path=public, extensions, overload = 1, proacl NOT NULL,
--     explicit PUBLIC / anon / authenticated EXECUTE all present, effective
--     PUBLIC / anon / authenticated EXECUTE all true.
--   - Per-function result types (from the repo definitions, confirmed
--     against the DB in SQL A):
--       create_admin_session(uuid, text)
--         -> TABLE(id uuid, name text, is_active boolean, session_token text)
--       revoke_admin_session(text) -> void
--       create_employee_session(uuid, text)
--         -> TABLE(id uuid, name text, role text, is_active boolean,
--                  company_id uuid, can_genka boolean, can_admin boolean,
--                  session_token text)
--       revoke_employee_session(text) -> void
--   - Implementation (SQL D): create_* verify PIN against genka_admins /
--     employees FIRST (return empty set on mismatch -- NO exception, NO side
--     effect), then delete existing+expired sessions and INSERT a new
--     token-hash row (gen_random_bytes + digest); revoke_* DELETE by
--     token_hash only (no-op on unknown token). No unexpected table or
--     cross-session references.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo on 2026-07-18, main
--   5942c3b; SQL cannot check these -- recorded here as facts; see C-5)
--   - Single anon-key client per screen; NO supabase.auth.signIn /
--     setSession anywhere -- the app is anon-only end to end.
--   - The 4 targets are called ONLY here:
--       index.html:909   create_employee_session (login, before auth)
--       index.html:921   revoke_employee_session (logout; try/catch, error
--                        ignored, then sessionStorage clear + reload)
--       admin-app.html:306 create_admin_session (login)
--       admin-app.html:319 revoke_admin_session (logout; try/catch)
--       genka-app.html:504 create_admin_session (login; genka uses admin
--                        sessions)
--       genka-app.html:521 revoke_admin_session (logout; try/catch)
--   - No other application or SQL code path depends on PUBLIC EXECUTE for
--     these functions.
--
-- [STOP CONDITIONS] (if any is hit during PRE-CHECK, do NOT run the body;
--   stop & report -- do NOT guess or "fix" divergence)
--   - C-1: SECURITY DEFINER total <> 78 or PUBLIC-true total <> 4.
--   - C-2/C-2b: any target missing, overloaded, attribute/result-type
--     mismatch, proacl NULL, explicit PUBLIC absent (already revoked -> do
--     NOT re-run), explicit anon or authenticated absent (revoking PUBLIC
--     would break login/logout -> a separate GRANT design would come first),
--     or any effective EXECUTE false.
--   - C-3: the PUBLIC-true set differs from the 4 targets (any row returned).
--   - C-4: any of the 4 functions diverging from the repo implementation
--     (session table / token generation / references).
--   - C-5: any front-end precondition above is NOT satisfied.
--
-- [ROLLBACK] (see the commented section at the end -- reference only)
--   GRANT EXECUTE ... TO PUBLIC x 4. NORMALLY FORBIDDEN: use only if a
--   production login/logout failure is confirmed to be caused by this step
--   AND the user gives separate explicit approval. anon / authenticated
--   grants are not touched in either direction.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. whole-schema baseline.
--    Expected: security_definer_total = 78, public_execute_true_total = 4.
--    STOP if either differs (schema state drifted since the 2026-07-18
--    checks; reconcile first).
select
  count(*) as security_definer_total,
  count(*) filter (where exists (
    select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where a.grantee = 0 and a.privilege_type = 'EXECUTE'
  )) as public_execute_true_total
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = true;

-- C-2. the 4 targets in detail.
--    Expected: 4 rows; each actual_signature non-NULL, language plpgsql,
--      owner postgres, security_definer true, volatility 'v', config
--      containing search_path=public, extensions, result_type equal to
--      expected_result, overload_count 1, proacl_is_null false, all three
--      explicit_* true, all three effective_* true.
--    STOP on any divergence (see STOP CONDITIONS).
with targets(fsig, fresult) as (values
  ('public.create_admin_session(uuid, text)', 'TABLE(id uuid, name text, is_active boolean, session_token text)'),
  ('public.revoke_admin_session(text)', 'void'),
  ('public.create_employee_session(uuid, text)', 'TABLE(id uuid, name text, role text, is_active boolean, company_id uuid, can_genka boolean, can_admin boolean, session_token text)'),
  ('public.revoke_employee_session(text)', 'void')
)
select
  t.fsig                        as expected_signature,
  t.fresult                     as expected_result,
  p.oid::regprocedure::text     as actual_signature,      -- NULL = missing target
  pg_get_function_identity_arguments(p.oid) as args,
  pg_get_function_result(p.oid) as result_type,           -- expect = expected_result
  l.lanname                     as language,              -- expect plpgsql
  pg_get_userbyid(p.proowner)   as owner,                 -- expect postgres
  p.prosecdef                   as security_definer,      -- expect true
  p.provolatile                 as volatility,            -- expect 'v'
  p.proconfig                   as config,                -- expect search_path=public, extensions
  (select count(*) from pg_proc p2
     join pg_namespace n2 on n2.oid = p2.pronamespace
    where n2.nspname = 'public' and p2.proname = p.proname) as overload_count,  -- expect 1
  (p.proacl is null)            as proacl_is_null,        -- expect false
  exists (select 1 from aclexplode(p.proacl) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE')  as explicit_public_execute,   -- expect true
  exists (select 1 from aclexplode(p.proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'anon' and a.privilege_type = 'EXECUTE') as explicit_anon_execute, -- expect true
  exists (select 1 from aclexplode(p.proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE') as explicit_authenticated_execute, -- expect true
  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE') as effective_public_execute,   -- expect true
  has_function_privilege('anon',          p.oid, 'EXECUTE') as effective_anon_execute,          -- expect true
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as effective_authenticated_execute  -- expect true
from targets t
left join pg_proc p on p.oid = to_regprocedure(t.fsig)
left join pg_language l on l.oid = p.prolang
order by t.fsig;

-- C-2b. aggregate over the same 4 targets (single row).
--    Expected: 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0.
with targets(fsig) as (values
  ('public.create_admin_session(uuid, text)'),
  ('public.revoke_admin_session(text)'),
  ('public.create_employee_session(uuid, text)'),
  ('public.revoke_employee_session(text)')
),
resolved as (
  select t.fsig, p.oid, p.proname, p.proacl, p.proowner, p.proconfig
  from targets t
  left join pg_proc p on p.oid = to_regprocedure(t.fsig)
)
select
  count(*) as target_function_count,                                                              -- 4
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))                                 as explicit_public_execute_count,        -- 4
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'anon' and a.privilege_type = 'EXECUTE'))                            as explicit_anon_execute_count,          -- 4
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE'))                   as explicit_authenticated_execute_count, -- 4
  count(*) filter (where oid is not null and exists (
           select 1 from aclexplode(coalesce(proacl, acldefault('f', proowner))) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))                                 as effective_public_execute_count,       -- 4
  count(*) filter (where oid is not null and has_function_privilege('anon', oid, 'EXECUTE'))      as effective_anon_execute_count,         -- 4
  count(*) filter (where oid is not null and has_function_privilege('authenticated', oid, 'EXECUTE')) as effective_authenticated_execute_count, -- 4
  count(*) filter (where oid is null)                                                             as missing_target_count,                 -- 0
  count(*) filter (where oid is not null and (select count(*) from pg_proc p2
           join pg_namespace n2 on n2.oid = p2.pronamespace
           where n2.nspname = 'public' and p2.proname = resolved.proname) <> 1)                   as unexpected_overload_count,            -- 0
  count(*) filter (where oid is not null and pg_get_userbyid(proowner) <> 'postgres')             as non_postgres_owner_count,             -- 0
  count(*) filter (where oid is not null and (proconfig is null
           or array_to_string(proconfig, ',') not like '%search_path=%'))                         as unfixed_search_path_count             -- 0
from resolved;

-- C-3. set equality: the whole-schema PUBLIC-true set (4) equals EXACTLY the
--    4 session RPCs. Expected: 0 rows.
--    STOP if any row is returned (an unexpected PUBLIC-true function, or a
--    listed function missing / already-PUBLIC-false).
with expected(fsig) as (values
  ('public.create_admin_session(uuid, text)'),
  ('public.revoke_admin_session(text)'),
  ('public.create_employee_session(uuid, text)'),
  ('public.revoke_employee_session(text)')
),
expected_oids as (select fsig, to_regprocedure(fsig)::oid as oid from expected),
db_true as (
  select p.oid, p.oid::regprocedure::text as actual_sig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef = true
    and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where a.grantee = 0 and a.privilege_type = 'EXECUTE'))
select 'db_only (unexpected PUBLIC-true fn)' as side, actual_sig as signature
from db_true where oid not in (select oid from expected_oids where oid is not null)
union all
select 'list_only (missing or PUBLIC-false)', fsig
from expected_oids e
where e.oid is null or e.oid not in (select oid from db_true);

-- C-4. implementation check on the 4 functions (prosrc).
--    Expected (per SQL D): create_* use gen_random_bytes + digest + INSERT +
--      DELETE against their own session/credential tables; revoke_* use
--      digest + DELETE only (no gen_random_bytes / no INSERT); no
--      cross-session references.
--        create_admin_session:     admin_sessions t, genka_admins t,
--          employee_sessions f, employees f, INSERT t, DELETE t, gen f... -> gen t
--        create_employee_session:  employee_sessions t, employees t,
--          admin_sessions f, genka_admins f, INSERT t, DELETE t, gen t
--        revoke_admin_session:     admin_sessions t, employee_sessions f,
--          INSERT f, DELETE t, gen f
--        revoke_employee_session:  employee_sessions t, admin_sessions f,
--          INSERT f, DELETE t, gen f
--    STOP if any function references an unexpected table or the wrong
--    session table.
select
  p.oid::regprocedure::text as function_signature,
  strpos(p.prosrc, 'gen_random_bytes') > 0  as uses_gen_random_bytes,
  strpos(p.prosrc, 'digest')           > 0  as uses_digest,
  strpos(p.prosrc, 'admin_sessions')   > 0  as refs_admin_sessions,
  strpos(p.prosrc, 'employee_sessions')> 0  as refs_employee_sessions,
  strpos(p.prosrc, 'genka_admins')     > 0  as refs_genka_admins,
  strpos(p.prosrc, 'employees')        > 0  as refs_employees,
  strpos(p.prosrc, 'INSERT')           > 0  as has_insert,
  strpos(p.prosrc, 'DELETE')           > 0  as has_delete
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_admin_session', 'revoke_admin_session',
                    'create_employee_session', 'revoke_employee_session')
order by p.proname;

-- C-5. front-end / repository preconditions (NOT checkable from SQL;
--    confirmed from the repo, main 5942c3b -- recorded here as facts).
--    If ANY is NOT true, STOP and do NOT run the body:
--    - The 3 screens use a single anon-key client each; NO
--      supabase.auth.signIn / setSession anywhere (anon-only end to end),
--      so the anon explicit EXECUTE grant carries login and logout.
--    - The 4 targets are called only at index.html:909 / :921,
--      admin-app.html:306 / :319, genka-app.html:504 / :521 (login/logout).
--    - No application or SQL code grants PUBLIC EXECUTE at runtime, and no
--      other path depends on PUBLIC EXECUTE for these 4 functions.


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-5 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction
--   as the body: if any expectation fails, it RAISEs, the transaction
--   aborts, and NOTHING is changed (fail-closed). A second run fails the
--   guard at G-2/G-3 (PUBLIC already revoked on a target) before any
--   statement that would modify state -- the body must NOT be re-run after
--   success.
--   The ONLY DB-changing statements are the 4 REVOKE EXECUTE ... FROM PUBLIC
--   statements. No GRANT, no CREATE / ALTER / DROP FUNCTION, no table / view
--   / policy DDL, no DML.
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
  rec   record;
begin
  -- G-1. whole-schema baseline: SECURITY DEFINER total = 78.
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef = true;
  if v_cnt <> 78 then
    raise exception 'GUARD STOP (G-1): public schema SECURITY DEFINER total = % (expected 78) -- schema drifted from the designed baseline; reconcile before running', v_cnt;
  end if;

  -- G-2. whole-schema baseline: PUBLIC EXECUTE effective true = 4.
  --      Combined with G-3 (which proves the 4 targets are PUBLIC-true), a
  --      total of exactly 4 means those 4 ARE the whole PUBLIC-true set --
  --      no unexpected member can exist, and none of the targets can already
  --      be PUBLIC-false.
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef = true
    and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_cnt <> 4 then
    raise exception 'GUARD STOP (G-2): PUBLIC EXECUTE true total = % (expected 4) -- schema drifted (or this body already ran); reconcile, do NOT re-run blindly', v_cnt;
  end if;

  -- G-3. each of the 4 targets matches the measured baseline EXACTLY.
  --      An absent explicit PUBLIC entry means the body already ran (or
  --      someone revoked it) -> STOP, do NOT re-run.
  --      An absent explicit anon / authenticated entry means the REVOKE
  --      would cut off login/logout -> STOP (separate GRANT design first).
  for rec in
    select t.fname, t.fsig, t.fresult
    from (values
      ('create_admin_session', 'public.create_admin_session(uuid, text)', 'TABLE(id uuid, name text, is_active boolean, session_token text)'),
      ('revoke_admin_session', 'public.revoke_admin_session(text)', 'void'),
      ('create_employee_session', 'public.create_employee_session(uuid, text)', 'TABLE(id uuid, name text, role text, is_active boolean, company_id uuid, can_genka boolean, can_admin boolean, session_token text)'),
      ('revoke_employee_session', 'public.revoke_employee_session(text)', 'void')
    ) as t(fname, fsig, fresult)
  loop
    if to_regprocedure(rec.fsig) is null then
      raise exception 'GUARD STOP (G-3): target % is missing', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = rec.fname;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-3): % has unexpected overloads (count=%, expected 1)', rec.fname, v_cnt;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language  l on l.oid = p.prolang
    where n.nspname = 'public'
      and p.oid = to_regprocedure(rec.fsig)
      and l.lanname = 'plpgsql'
      and p.prosecdef = true
      and p.provolatile = 'v'
      and pg_get_userbyid(p.proowner) = 'postgres'
      and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%'
      and pg_get_function_result(p.oid) = rec.fresult
      and p.proacl is not null;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-3): % attributes/result type/proacl differ from the measured baseline', rec.fname;
    end if;
    select count(*) into v_cnt
    from pg_proc p, aclexplode(p.proacl) a
    where p.oid = to_regprocedure(rec.fsig)
      and a.grantee = 0 and a.privilege_type = 'EXECUTE';
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-3): % has NO explicit PUBLIC EXECUTE -- body may have run before; reconcile, do NOT re-run', rec.fname;
    end if;
    select count(*) into v_cnt
    from pg_proc p, aclexplode(p.proacl) a
    join pg_roles r on r.oid = a.grantee
    where p.oid = to_regprocedure(rec.fsig)
      and r.rolname = 'anon' and a.privilege_type = 'EXECUTE';
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-3): % lacks the EXPLICIT anon EXECUTE entry -- revoking PUBLIC would cut off login/logout; STOP (a GRANT design must come first)', rec.fname;
    end if;
    select count(*) into v_cnt
    from pg_proc p, aclexplode(p.proacl) a
    join pg_roles r on r.oid = a.grantee
    where p.oid = to_regprocedure(rec.fsig)
      and r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE';
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-3): % lacks the EXPLICIT authenticated EXECUTE entry -- revoking PUBLIC would cut off the app; STOP', rec.fname;
    end if;
    if not has_function_privilege('anon', to_regprocedure(rec.fsig), 'EXECUTE')
       or not has_function_privilege('authenticated', to_regprocedure(rec.fsig), 'EXECUTE') then
      raise exception 'GUARD STOP (G-3): effective anon/authenticated EXECUTE on % is not true -- diverged from the measured baseline', rec.fname;
    end if;
  end loop;

  raise notice 'GUARD OK: the 4 session RPCs are the whole PUBLIC-true set and match the measured baseline; proceeding to 4 x REVOKE EXECUTE FROM PUBLIC';
end
$guard$;

-- BODY (EXACTLY 4 DB changes: REVOKE EXECUTE ... FROM PUBLIC only.
-- anon / authenticated grants are NOT touched.)

REVOKE EXECUTE ON FUNCTION public.create_admin_session(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_admin_session(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_employee_session(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_employee_session(text) FROM PUBLIC;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. whole-schema totals after the body.
--    Expected: security_definer_total = 78 (unchanged),
--      public_execute_true_total = 0 (was 4; exactly -4). This is the final
--      state of the PUBLIC EXECUTE cleanup: no SECURITY DEFINER function in
--      public retains PUBLIC EXECUTE.
select
  count(*) as security_definer_total,
  count(*) filter (where exists (
    select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where a.grantee = 0 and a.privilege_type = 'EXECUTE'
  )) as public_execute_true_total
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = true;

-- P-1b. no SECURITY DEFINER function in public retains PUBLIC EXECUTE.
--    Expected: 0 rows.
select p.oid::regprocedure::text as still_public_true
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef = true
  and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where a.grantee = 0 and a.privilege_type = 'EXECUTE')
order by 1;

-- P-2. the 4 targets after the body -- re-run the C-2 query UNCHANGED
--    (same 4-row VALUES list; copy it from C-2).
--    Expected differences vs C-2: explicit_public_execute = false and
--      effective_public_execute = false for ALL 4.
--    Expected UNCHANGED vs C-2: everything else -- language / owner /
--      security_definer / volatility / config / result_type /
--      overload_count 1 / proacl_is_null false /
--      explicit_anon_execute true / explicit_authenticated_execute true /
--      effective_anon_execute true / effective_authenticated_execute true.

-- P-3. aggregate -- re-run the C-2b query UNCHANGED.
--    Expected: 4, 0, 4, 4, 0, 4, 4, 0, 0, 0, 0
--    (public counts drop to 0; anon / authenticated counts stay 4).


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--   POSITIVE login/logout smoke is REQUIRED for this step (unlike 6-a),
--   because these are the login/logout critical-path RPCs. Login/logout
--   write session-token rows (INSERT on login, DELETE on logout / re-login)
--   -- that is inherent to testing login and is ephemeral (8h expiry); it
--   does NOT modify employees / genka_admins / PIN or any business data.
--
--   [Employee screen (index.html)]
--     - logout (if logged in) -> employee login succeeds
--       (create_employee_session = HTTP 200; the app shows the app after the
--       non-empty result) -> main lists render -> logout succeeds
--       (revoke_employee_session = HTTP 200) -> re-login succeeds.
--   [Admin screen (admin-app.html)]
--     - logout -> admin login succeeds (create_admin_session = HTTP 200) ->
--       main screens render -> logout succeeds (revoke_admin_session =
--       HTTP 200).
--   [Genka screen (genka-app.html)]
--     - admin login succeeds (create_admin_session = HTTP 200) -> main
--       screens render -> logout succeeds (revoke_admin_session = HTTP 200).
--   [Common]
--     - Network: create_*_session = HTTP 200; revoke_*_session = HTTP 200
--       (RETURNS void normal response); NO unexpected 401 / 403.
--     - Console: no app-origin red errors.
--
--   [Negative smoke -- existing behaviour, no side effects]
--     - Wrong PIN at login: create_*_session returns an EMPTY result (NOT an
--       exception -- PIN is checked first and the function RETURNs before any
--       DELETE/INSERT, so there is NO side effect), and the screen shows its
--       login error. There is NO account-lock mechanism in the code.
--     - Logout / revoke with an unknown or already-expired token: a no-op
--       (0-row DELETE, no error); the front-end also wraps revoke in
--       try/catch and ignores errors.
--     - Do NOT change any account, PIN, or business data.
-- ============================================================


-- ============================================================
-- EMERGENCY ROLLBACK (reference only -- NOT executed; NORMALLY FORBIDDEN.
--   Use ONLY if a production login/logout failure is confirmed to be caused
--   by this step AND the user gives separate explicit approval. This
--   restores the explicit PUBLIC EXECUTE entries on the 4 session RPCs
--   exactly as measured in C-2; it does NOT touch the anon / authenticated
--   grants in either direction.
--   WARNING: it re-opens EXECUTE to every present and future role.)
-- ============================================================
-- BEGIN;
-- GRANT EXECUTE ON FUNCTION public.create_admin_session(uuid, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.revoke_admin_session(text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_employee_session(uuid, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.revoke_employee_session(text) TO PUBLIC;
-- COMMIT;
-- ============================================================
