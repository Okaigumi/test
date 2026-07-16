-- ============================================================
-- Phase 4-F-4-a: revoke PUBLIC EXECUTE on the 5 existing notices RPCs
--   (list_notices_admin_secure / create_notice_secure / update_notice_secure /
--    update_notice_attachment_secure / delete_notice_attachment_secure).
--
--   These 5 RPCs were created (notices-admin-rpc.sql / notice-attachments-rpc.sql)
--   with `GRANT EXECUTE ... TO anon, authenticated` but WITHOUT
--   `REVOKE EXECUTE ... FROM PUBLIC`, so the PostgreSQL default PUBLIC EXECUTE grant
--   remained. This was recorded as the KNOWN, INTENTIONALLY UNCHANGED baseline through
--   Phase 4-F-2B-9 (C-5b / P-9). No auth bypass exists -- each RPC verifies the admin
--   session INLINE (admin_sessions.token_hash match + expires_at > now()) and RAISEs
--   'Invalid or expired admin session' otherwise -- but PUBLIC EXECUTE is unnecessary
--   excess privilege. anon / authenticated keep their own explicit EXECUTE, so ONLY
--   PUBLIC is removed and the application is unaffected.
--
--   Same technique as phase4f-2b-6-machine-location-write-rpc-public-execute-revoke.sql
--   (EXECUTED 2026-07-13), extended to 5 functions with an in-transaction GUARD.
-- ============================================================
-- [STATUS] EXECUTED 2026-07-16
--   - This file removed exactly FIVE privileges: EXECUTE for PUBLIC on each of the 5
--     notices RPCs listed above. Nothing else was touched.
--   - DB execution was done by the USER, manually, in the Supabase SQL Editor.
--     Claude Code CLI performed NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / guard / body / post-check / smoke were run by the user.
--   - Run order was: PRE-CHECK (C-1..C-4, read-only, run individually) -> EXECUTION
--     BODY (single transaction: read-only GUARD G-0..G-3 + 5 REVOKE EXECUTE FROM PUBLIC)
--     -> POST-CHECK (P-1..P-5) -> SMOKE TEST (admin read-only + employee regression +
--     invalid-session negative). ROLLBACK not used.
--   - SCOPE was PUBLIC EXECUTE on these 5 RPCs ONLY. anon / authenticated / postgres /
--     service_role EXECUTE was KEPT. No other RPC's PUBLIC EXECUTE was touched.
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-16)
--     - The user ran the EXECUTION BODY manually ONCE (single transaction:
--       BEGIN .. read-only GUARD DO block (G-0..G-3) .. 5 x REVOKE EXECUTE FROM PUBLIC
--       .. COMMIT). Result: Success. No rows returned.
--     - The BODY was NOT re-run afterwards and must NOT be re-run (the guard fails
--       closed on a second run: G-3 sees PUBLIC already revoked and aborts).
--     - No DB connection / Supabase CLI / psql from Claude Code CLI. ROLLBACK not used.
--
--   [PRE-CHECK RESULT] (C-1..C-4 + C-1b / C-3b, 2026-07-16 -- all passed; GUARD G-0..G-3 OK)
--     - C-1: all 5 targets present; SECURITY DEFINER = true, VOLATILE ('v'), owner
--       postgres, search_path = public, extensions; identity args match each signature;
--       RETURNS TABLE = 9 columns (id / content / is_active / created_at /
--       attachment_url / attachment_path / attachment_type / attachment_name /
--       updated_at) for all 5.
--     - C-1b: 5 target names, each overloads = 1; no unexpected overload.
--     - C-2: 5 RPC x 4 roles = 20 rows; anon / authenticated / postgres / service_role
--       can_execute = true on every target.
--     - C-3: 5 RPC x 5 grantees = 25 rows; PUBLIC / anon / authenticated / postgres /
--       service_role each present with EXECUTE, is_grantable = false; no unexpected grantee.
--     - C-3b: per RPC execute_acl_count = 5; PUBLIC / anon / authenticated / postgres /
--       service_role each = 1; unexpected_cnt = 0; grantable_cnt = 0.
--     - C-4: out-of-scope list_notices_secure(text) has anon / authenticated / postgres /
--       service_role explicit EXECUTE and NO PUBLIC (not a target).
--
--   [POST-CHECK RESULT] (P-1..P-5 + P-2b / P-2c / P-3b, 2026-07-16 -- all passed)
--     - P-1: 5 RPC x 4 roles = 20 rows; anon / authenticated / postgres / service_role
--       can_execute = true (unchanged).
--     - P-2 / P-2b / P-2c: per RPC execute_acl_count = 4; public_cnt = 0 (PUBLIC removed);
--       anon / authenticated / postgres / service_role each = 1; unexpected_cnt = 0;
--       grantable_cnt = 0.
--     - P-3: attributes / identity args / 9-column return type unchanged from C-1.
--     - P-3b: 5 target names, each overloads = 1 (unchanged).
--     - P-4: out-of-scope list_notices_secure(text) ACL unchanged (anon / authenticated /
--       postgres / service_role EXECUTE kept; NO PUBLIC).
--     - P-5a: notices anon / authenticated all 8 table privileges false.
--     - P-5b: notices policy_count = 0. P-5c: relkind 'r', RLS true, FORCE RLS false,
--       owner postgres. P-5d: notices total 4 / active 1 / inactive 3 / null 0 (no DML).
--
--   [SMOKE TEST RESULT] (2026-07-16; no real session token recorded)
--     - NEGATIVE invalid session: list_notices_admin_secure('<invalid>') raised SQLSTATE
--       P0001 'Invalid or expired admin session'; no data change.
--     - ADMIN screen (admin-app.html, read-only): admin login OK; notices management
--       screen + list (4) render; list_notices_admin_secure POST 200; NO /rest/v1/notices
--       direct GET; create / update / delete NOT invoked.
--     - EMPLOYEE screen (index.html) regression: employee login OK; notice renders;
--       list_notices_secure POST 200; NO /rest/v1/notices direct GET; no Console errors.
--
--   [OUTCOME]
--     - PUBLIC EXECUTE on the 5 notices RPCs: revoked. anon / authenticated / postgres /
--       service_role EXECUTE: KEPT (unchanged). Function definitions / attributes /
--       return types: unchanged (no FUNCTION DDL in the body).
--     - notices table privileges / policies (0) / RLS / FORCE RLS / owner / data
--       (total 4 / active 1 / inactive 3 / 0): unchanged. list_notices_secure and other
--       objects: unchanged.
--     - Write smoke (a real create / update / delete) was NOT performed on purpose; the
--       write path is proven intact by P-1 / P-2c (per-role EXECUTE) + P-3 (definition /
--       attributes) + the negative smoke (session verification still enforced).
--     - The Phase 4-F-4-a real-DB work is DONE. Full closure is recorded once the record
--       PR is merged to main; until then it is NOT treated as fully closed. Phase 4-F as
--       a whole and other steps are NOT complete.
--     - ROLLBACK: NOT executed (kept as commented reference only).
--
-- [PURPOSE]
--   - Remove the redundant PUBLIC EXECUTE grant on the 5 notices admin/write RPCs. The
--     app (admin-app.html) calls them as anon / authenticated, both of which retain
--     their own explicit EXECUTE, so removing PUBLIC does not affect the application.
--
-- [TARGET FUNCTIONS] (exact signatures)
--   1. public.list_notices_admin_secure(text)
--   2. public.create_notice_secure(text, text, boolean)
--   3. public.update_notice_secure(text, uuid, text, boolean)
--   4. public.update_notice_attachment_secure(text, uuid, text, text, text, text)
--   5. public.delete_notice_attachment_secure(text, uuid)
--
-- [KNOWN BASELINE] (measured in Phase 4-F-2B-9 pre/post-check; RE-VERIFIED here before
--   the body -- see C-1..C-3b)
--   - All 5: SECURITY DEFINER = true, VOLATILE ('v'), owner = postgres,
--     search_path = public, extensions.
--   - All 5: RETURNS TABLE (9 columns) -- id uuid, content text, is_active boolean,
--     created_at timestamptz, attachment_url text, attachment_path text,
--     attachment_type text, attachment_name text, updated_at timestamptz.
--   - All 5: EXECUTE ACL = { PUBLIC, anon, authenticated, postgres, service_role },
--     each is_grantable = false. (PUBLIC is exactly what the body removes.)
--   - Frontend call sites (admin-app.html): list_notices_admin_secure (1920),
--     update_notice_secure (2046, 2098), create_notice_secure (2054),
--     update_notice_attachment_secure (2071), delete_notice_attachment_secure (2117).
--   - The only OTHER notices RPC, public.list_notices_secure(text) (employee read),
--     already has NO PUBLIC EXECUTE (Phase 4-F-2B-9-a) and is OUT OF SCOPE here.
--
-- [SCOPE] (EXACTLY five DB changes -- nothing else)
--   - REVOKE EXECUTE FROM PUBLIC on each of the 5 target functions.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - The function definitions / bodies (no CREATE, no CREATE OR REPLACE, no DROP,
--     no ALTER FUNCTION).
--   - EXECUTE for anon / authenticated / postgres / service_role on the 5 RPCs (KEPT).
--   - list_notices_secure(text) (employee read RPC) and any other RPC's ACL.
--   - notices table privileges (anon / authenticated have NO direct privilege on
--     public.notices -- SELECT was revoked in Phase 4-F-2B-9-c; all 8 stay false).
--   - notices RLS / policies (notices has 0 policies after 2B-9-c) / RLS FORCE / owner.
--   - notices data / columns / constraints / indexes.
--   - Storage (notice-attachments bucket / its INSERT policy).
--   - front-end code.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--   - the PUBLIC EXECUTE on any OTHER RPC (out of scope -- do NOT tidy them here).
--
-- [RE-RUN SAFETY] (plain one-shot design; same pattern as 2B-8 / 2B-9)
--   - The EXECUTION BODY is ONE transaction (BEGIN..COMMIT) whose first statement is a
--     read-only GUARD (DO block). The guard RAISEs if the DB is not in the exact
--     expected pre-state -- including the "PUBLIC already (partially) revoked" case --
--     so a second run aborts the transaction BEFORE any REVOKE is attempted.
--   - The body uses only REVOKE EXECUTE ... FROM PUBLIC (no GRANT / CREATE / ALTER /
--     DROP / DML). Do NOT re-run after success. Re-adding PUBLIC requires the explicit
--     ROLLBACK reference at the end (emergency only, separate approval).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence. The GUARD re-asserts the machine-
--   checkable subset and aborts the transaction if violated.)
--   - C-1: any of the 5 target functions is missing, its signature differs, it is not
--          SECURITY DEFINER, not VOLATILE, owner not postgres, search_path not fixed,
--          identity arguments differ, or return type differs from the 9-column TABLE.
--   - C-1b: an unexpected overload exists (proname count <> 1 for any target, or the
--          5 targets by name total <> 5).
--   - C-2: any of anon / authenticated / postgres / service_role EXECUTE is false for
--          any target (effective privilege). (PUBLIC is verified via the C-3 ACL.)
--   - C-3 / C-3b: for any target, PUBLIC has no explicit EXECUTE ACL row (already
--          revoked -> reconcile, do NOT re-run), the EXECUTE ACL grantee set is not
--          EXACTLY {PUBLIC, anon, authenticated, postgres, service_role},
--          execute_acl_count <> 5, an unexpected grantee holds EXECUTE, or any
--          is_grantable is not false.
--   - The body would change any RPC definition / any role other than PUBLIC / any
--          table / policy / data / any object beyond the 5 SCOPE REVOKEs -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Re-grants EXECUTE to PUBLIC on the 5 target functions. Emergency use only; normally
--   unnecessary because anon / authenticated keep their own EXECUTE. Re-adding PUBLIC
--   RE-WIDENS the grant (least-privilege regression), so it requires a SEPARATE explicit
--   approval and must NOT be run in the same session right after the body. Touches only
--   the 5 target functions' PUBLIC grant. NOT executed.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body. Any STOP condition -> stop.
-- ============================================================

-- C-1. attributes + identity arguments + return type for all 5 targets.
--    Expected: 5 rows -- each security_definer = true, volatility = 'v' (VOLATILE),
--      owner = postgres, config contains search_path=public, extensions; identity args
--      and result type as in [KNOWN BASELINE] (9-column TABLE).
--    STOP if any is missing, the signature differs, or any attribute differs.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as security_definer,   -- expect true
  p.provolatile                             as volatility,         -- expect 'v' (VOLATILE)
  pg_get_userbyid(p.proowner)               as owner,              -- expect postgres
  p.proconfig                               as config,             -- expect search_path=public, extensions
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_result(p.oid)             as result_type         -- expect TABLE(9 cols)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by p.proname, p.oid::regprocedure::text;

-- C-1b. overload check -- each target name resolves to EXACTLY 1 function, 5 total.
--    Expected: 5 rows, each overloads = 1.
--    STOP if any name has an unexpected overload, or the total is not 5.
select
  p.proname,
  count(*) as overloads,       -- expect 1 each
  string_agg(p.oid::regprocedure::text, ' | ' order by p.oid) as signatures
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
group by p.proname
order by p.proname;

-- C-2. effective EXECUTE for the real roles (4 roles x 5 functions = 20 rows).
--    Expected: can_execute = true for anon / authenticated / postgres / service_role
--      on every target.
--    STOP if any is false.
--    NOTE on PUBLIC: has_function_privilege() cannot take PUBLIC as an argument (there
--      is no 'public' role). PUBLIC's explicit EXECUTE is verified authoritatively in
--      C-3 / C-3b (the ACL, grantee OID 0 = PUBLIC).
select
  p.oid::regprocedure::text as function_signature,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by function_signature, v.grantee;

-- C-3. EXECUTE ACL (explicit grants; source of truth for PUBLIC) for all 5 targets.
--    Expected per function: 5 EXECUTE rows -- PUBLIC, anon, authenticated, postgres,
--      service_role -- each is_grantable = false. PUBLIC (grantee OID 0) MUST have an
--      explicit EXECUTE row (that is exactly what the body removes).
--    STOP if PUBLIC has no explicit EXECUTE row on any target, if any expected role's
--      EXECUTE ACL is missing, if any unexpected grantee has EXECUTE, or if any
--      is_grantable is not false. (C-3b verifies the set/count exactly.)
--    NOTE: coalesce(..., acldefault('f', proowner)) covers a NULL proacl; grantee OID 0
--      = PUBLIC, shown via CASE (never cast 0::regrole).
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and acl.privilege_type = 'EXECUTE'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by function_signature, grantee;

-- C-3b. EXECUTE ACL set completeness per function -- exact match to the expected 5.
--    Expected per function (5 rows): execute_acl_count = 5; public_cnt = 1;
--      anon_cnt = 1; auth_cnt = 1; postgres_cnt = 1; service_role_cnt = 1;
--      unexpected_cnt = 0; grantable_cnt = 0.
--    STOP if any row deviates (missing PUBLIC, missing role, unexpected grantee, or a
--      grantable EXECUTE).
select
  p.oid::regprocedure::text as function_signature,
  count(*)                                                        as execute_acl_count,   -- expect 5
  count(*) filter (where g.grantee = 'PUBLIC')                    as public_cnt,          -- expect 1
  count(*) filter (where g.grantee = 'anon')                     as anon_cnt,            -- expect 1
  count(*) filter (where g.grantee = 'authenticated')            as auth_cnt,            -- expect 1
  count(*) filter (where g.grantee = 'postgres')                 as postgres_cnt,        -- expect 1
  count(*) filter (where g.grantee = 'service_role')             as service_role_cnt,    -- expect 1
  count(*) filter (where g.grantee is null
                      or g.grantee not in ('PUBLIC','anon','authenticated','postgres','service_role'))
                                                                  as unexpected_cnt,      -- expect 0
  count(*) filter (where g.is_grantable)                         as grantable_cnt        -- expect 0
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral (
  select
    case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
    acl.is_grantable
  from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where acl.privilege_type = 'EXECUTE'
) g
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
group by p.oid
order by function_signature;

-- C-4. OTHER notices RPCs (context; NOT changed here).
--    Expected: list_notices_secure(text) -- the employee read RPC -- present with NO
--      PUBLIC EXECUTE (Phase 4-F-2B-9-a). This file does NOT touch it. Any other notice
--      RPC beyond the 5 targets + list_notices_secure should be investigated first.
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and p.proname like '%notice%'
  and p.proname not in ('list_notices_admin_secure', 'create_notice_secure',
                        'update_notice_secure', 'update_notice_attachment_secure',
                        'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by function_signature, grantee;


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-4 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction as the body:
--   if any expectation fails, it RAISEs, the transaction aborts, and NOTHING is changed.
--   A second run fails the guard (PUBLIC already revoked) before any REVOKE is executed.
--   DB-CHANGING statements are EXACTLY five: 5 x REVOKE EXECUTE FROM PUBLIC.
--   No GRANT / CREATE / ALTER / DROP FUNCTION / DML; no role other than PUBLIC is
--   revoked; no table / policy / data is touched.
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_sig       text;
  v_oid       oid;
  v_secdef    boolean;
  v_volatile  text;
  v_owner     text;
  v_config    text[];
  v_cnt       integer;
  v_public    integer;
  v_anon      integer;
  v_auth      integer;
  v_postgres  integer;
  v_service   integer;
  v_unexpect  integer;
  v_grantable integer;
  v_sigs text[] := array[
    'public.list_notices_admin_secure(text)',
    'public.create_notice_secure(text, text, boolean)',
    'public.update_notice_secure(text, uuid, text, boolean)',
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)',
    'public.delete_notice_attachment_secure(text, uuid)'
  ];
begin
  -- G-0. exactly 5 target functions by name; no unexpected overload.
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                      'update_notice_secure', 'update_notice_attachment_secure',
                      'delete_notice_attachment_secure');
  if v_cnt <> 5 then
    raise exception 'GUARD STOP (G-0): expected exactly 5 notices RPCs by name, found % (overload or missing)', v_cnt;
  end if;

  foreach v_sig in array v_sigs loop
    -- G-1. target exists with the exact signature.
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'GUARD STOP (G-1): target function % is missing (signature mismatch)', v_sig;
    end if;

    -- G-2. attributes: SECURITY DEFINER / VOLATILE / owner postgres / fixed search_path.
    select p.prosecdef, p.provolatile::text, pg_get_userbyid(p.proowner)::text, p.proconfig
      into v_secdef, v_volatile, v_owner, v_config
    from pg_proc p
    where p.oid = v_oid;

    if v_secdef is not true then
      raise exception 'GUARD STOP (G-2): % is not SECURITY DEFINER', v_sig;
    end if;
    if v_volatile <> 'v' then
      raise exception 'GUARD STOP (G-2): % volatility <> VOLATILE (v)', v_sig;
    end if;
    if v_owner <> 'postgres' then
      raise exception 'GUARD STOP (G-2): % owner <> postgres (%)', v_sig, v_owner;
    end if;
    if v_config is null or not ('search_path=public, extensions' = any (v_config)) then
      raise exception 'GUARD STOP (G-2): % search_path not fixed to public, extensions', v_sig;
    end if;

    -- G-3. EXECUTE ACL set is EXACTLY {PUBLIC, anon, authenticated, postgres,
    --      service_role}, each is_grantable = false. PUBLIC must be present (else the
    --      revoke already ran / diverged -> STOP); the 4 roles must be present (else a
    --      plain REVOKE FROM PUBLIC would leave the app without EXECUTE).
    select
      count(*),
      count(*) filter (where g.grantee = 'PUBLIC'),
      count(*) filter (where g.grantee = 'anon'),
      count(*) filter (where g.grantee = 'authenticated'),
      count(*) filter (where g.grantee = 'postgres'),
      count(*) filter (where g.grantee = 'service_role'),
      count(*) filter (where g.grantee is null
                          or g.grantee not in ('PUBLIC','anon','authenticated','postgres','service_role')),
      count(*) filter (where g.is_grantable)
      into v_cnt, v_public, v_anon, v_auth, v_postgres, v_service, v_unexpect, v_grantable
    from (
      select
        case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
        acl.is_grantable
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
      left join pg_roles r on r.oid = acl.grantee
      where p.oid = v_oid
        and acl.privilege_type = 'EXECUTE'
    ) g;

    if v_cnt <> 5 then
      raise exception 'GUARD STOP (G-3): % EXECUTE ACL count = % (expected 5: PUBLIC+anon+authenticated+postgres+service_role)', v_sig, v_cnt;
    end if;
    if v_public <> 1 then
      raise exception 'GUARD STOP (G-3): % has no explicit PUBLIC EXECUTE (already revoked / diverged) -- do NOT re-run', v_sig;
    end if;
    if v_anon <> 1 or v_auth <> 1 or v_postgres <> 1 or v_service <> 1 then
      raise exception 'GUARD STOP (G-3): % is missing an explicit EXECUTE for anon/authenticated/postgres/service_role', v_sig;
    end if;
    if v_unexpect <> 0 then
      raise exception 'GUARD STOP (G-3): % has an unexpected EXECUTE grantee', v_sig;
    end if;
    if v_grantable <> 0 then
      raise exception 'GUARD STOP (G-3): % has a grantable EXECUTE (is_grantable = true)', v_sig;
    end if;
  end loop;

  raise notice 'GUARD OK: all 5 notices RPCs match the expected baseline; proceeding to REVOKE PUBLIC EXECUTE';
end
$guard$;

-- BODY (exactly 5 DB changes: REVOKE EXECUTE FROM PUBLIC on each target. PUBLIC only.)

REVOKE EXECUTE
ON FUNCTION public.list_notices_admin_secure(text)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.create_notice_secure(text, text, boolean)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.update_notice_secure(text, uuid, text, boolean)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.update_notice_attachment_secure(text, uuid, text, text, text, text)
FROM PUBLIC;

REVOKE EXECUTE
ON FUNCTION public.delete_notice_attachment_secure(text, uuid)
FROM PUBLIC;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. effective EXECUTE for the real roles UNCHANGED (mirror C-2).
--    Expected: can_execute = true for anon / authenticated / postgres / service_role
--      on every target (PUBLIC's removal is verified via the ACL in P-2 / P-2b / P-2c).
select
  p.oid::regprocedure::text as function_signature,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by function_signature, v.grantee;

-- P-2. EXECUTE ACL after the revoke (all 5 targets).
--    Expected per function: 4 EXECUTE rows -- anon, authenticated, postgres,
--      service_role -- each is_grantable = false; NO PUBLIC row.
--    FAIL if PUBLIC or any unexpected grantee still holds EXECUTE, if any expected role
--      is missing, or if any is_grantable is not false.
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and acl.privilege_type = 'EXECUTE'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by function_signature, grantee;

-- P-2b. PUBLIC EXECUTE explicitly absent on all 5 targets. Expected: 0 rows.
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and acl.grantee = 0                 -- 0 = PUBLIC; expect 0 rows total
  and acl.privilege_type = 'EXECUTE'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by function_signature;

-- P-2c. EXECUTE ACL set completeness after the revoke (per function).
--    Expected per function (5 rows): execute_acl_count = 4; public_cnt = 0;
--      anon_cnt = 1; auth_cnt = 1; postgres_cnt = 1; service_role_cnt = 1;
--      unexpected_cnt = 0; grantable_cnt = 0.
select
  p.oid::regprocedure::text as function_signature,
  count(*)                                                        as execute_acl_count,   -- expect 4
  count(*) filter (where g.grantee = 'PUBLIC')                    as public_cnt,          -- expect 0
  count(*) filter (where g.grantee = 'anon')                     as anon_cnt,            -- expect 1
  count(*) filter (where g.grantee = 'authenticated')            as auth_cnt,            -- expect 1
  count(*) filter (where g.grantee = 'postgres')                 as postgres_cnt,        -- expect 1
  count(*) filter (where g.grantee = 'service_role')             as service_role_cnt,    -- expect 1
  count(*) filter (where g.grantee is null
                      or g.grantee not in ('PUBLIC','anon','authenticated','postgres','service_role'))
                                                                  as unexpected_cnt,      -- expect 0
  count(*) filter (where g.is_grantable)                         as grantable_cnt        -- expect 0
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral (
  select
    case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
    acl.is_grantable
  from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where acl.privilege_type = 'EXECUTE'
) g
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
group by p.oid
order by function_signature;

-- P-3. attributes + identity args + return type UNCHANGED (mirror C-1).
--    Expected: identical to C-1 for all 5 (only the PUBLIC EXECUTE grant changed; the
--      signature, SECURITY DEFINER, VOLATILE, owner, search_path, identity args and the
--      9-column return type are untouched -- this file has no FUNCTION DDL).
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as security_definer,
  p.provolatile                             as volatility,
  pg_get_userbyid(p.proowner)               as owner,
  p.proconfig                               as config,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_result(p.oid)             as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = any (array[
    'public.list_notices_admin_secure(text)'::regprocedure,
    'public.create_notice_secure(text, text, boolean)'::regprocedure,
    'public.update_notice_secure(text, uuid, text, boolean)'::regprocedure,
    'public.update_notice_attachment_secure(text, uuid, text, text, text, text)'::regprocedure,
    'public.delete_notice_attachment_secure(text, uuid)'::regprocedure
  ])
order by p.proname, p.oid::regprocedure::text;

-- P-3b. overload count UNCHANGED (mirror C-1b). This file has no FUNCTION DDL, so the
--    5 targets must still resolve to EXACTLY 1 function each. Unlike P-1..P-3 (which
--    pin the known OIDs via ::regprocedure), this NAME-based count would surface any
--    unexpected new overload appearing on a target name.
--    Expected: 5 rows, each overloads = 1.
select
  p.proname,
  count(*) as overloads       -- expect 1 each
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
group by p.proname
order by p.proname;

-- P-4. OTHER notices RPC UNCHANGED (mirror C-4). Expected: list_notices_secure(text)
--    still present with NO PUBLIC EXECUTE; no other notice RPC changed.
select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and p.proname like '%notice%'
  and p.proname not in ('list_notices_admin_secure', 'create_notice_secure',
                        'update_notice_secure', 'update_notice_attachment_secure',
                        'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by function_signature, grantee;

-- P-5. NON-SCOPE confirmation (nothing below was changed by this file).
--    P-5a. notices table privileges UNCHANGED: anon / authenticated have NO direct
--      privilege on public.notices -- SELECT was revoked in Phase 4-F-2B-9-c, so all 8
--      privileges (SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER /
--      MAINTAIN) are false for both roles. STOP-comparison target: all false.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.notices', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.notices', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.notices', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.notices', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.notices', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.notices', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.notices', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.notices', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

--    P-5b. notices policy count UNCHANGED. Expected: 0 (notices has had 0 policies
--      since Phase 4-F-2B-9-c).
select count(*) as policy_count       -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'notices';

--    P-5c. notices RLS / FORCE RLS / owner UNCHANGED. Expected: relkind 'r',
--      rls_enabled = true, rls_forced = false, owner = postgres.
select
  c.relkind                   as relkind,
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

--    P-5d. notices data UNCHANGED (this file performs no DML). Record the counts and
--      compare with the pre-check run (expected total 4 / active 1 / inactive 3 / 0 as
--      of 2026-07-16; ordinary data changes between runs are not caused by this file).
select
  count(*)                                  as total,
  count(*) filter (where is_active = true)  as active,
  count(*) filter (where is_active = false) as inactive,
  count(*) filter (where is_active is null) as null_active
from public.notices;


-- ============================================================
-- SMOKE TEST (manual; performed by the USER AFTER the body + post-check.
--   Reload / re-login first so nothing cached masks a failure. Do NOT record any real
--   session token. Do NOT run the create / update / attachment / delete notice RPCs
--   against real data -- the admin check is READ-ONLY.)
-- ============================================================

-- (a) ADMIN screen (admin-app.html), management session -- READ-ONLY:
--     - Admin login succeeds.
--     - The notices list renders.
--     - Network: list_notices_admin_secure POST = 200; NO /rest/v1/notices direct GET.
--     - Console: no errors.
--     - Do NOT invoke create_notice_secure / update_notice_secure /
--       update_notice_attachment_secure / delete_notice_attachment_secure here (they
--       mutate data). Their EXECUTE path is proven intact by P-1 / P-2 / P-2c
--       (anon / authenticated EXECUTE kept) + P-3 (definition/attributes unchanged).

-- (b) EMPLOYEE screen (index.html) -- regression (NOT a target of this file):
--     - Employee login succeeds; the active notice renders.
--     - Network: list_notices_secure POST = 200; NO /rest/v1/notices direct GET.
--     - Console: no errors. (list_notices_secure was not touched; this only confirms
--       no collateral impact.)

-- (c) INVALID-SESSION negative smoke (SQL Editor; no data change, no real token).
--     list_notices_admin_secure is a pure READ (no DML even on success) and checks the
--     admin session FIRST, so an invalid token is rejected with SQLSTATE P0001
--     'Invalid or expired admin session' and NOTHING is written. (The 4 write RPCs also
--     verify the session BEFORE any INSERT/UPDATE, so a bogus token never mutates data;
--     list_notices_admin_secure is used here as the safest -- read-only -- probe.)
--     Expected: the DO block reports "SMOKE OK"; a self-generated SMOKE FAIL is never
--     swallowed (no WHEN OTHERS is used).
DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_notices_admin_secure('smoke-invalid-token');
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM <> 'Invalid or expired admin session' THEN
        RAISE;   -- some other P0001; surface it
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_notices_admin_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_notices_admin_secure rejected an invalid admin session';
END $$;

--     write-RPC EXECUTE evidence (NON-mutating): the post-check proves the write RPCs
--     keep anon / authenticated EXECUTE and their SECURITY DEFINER session-verification
--     definition is unchanged (P-1 / P-2c / P-3). Do NOT call the write RPCs with a
--     valid token in this smoke (it would create/alter/delete a real notice). Any real
--     issue at the next genuine create/update/delete is the rollback trigger.


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; requires SEPARATE explicit approval;
--   do NOT run in the same session immediately after the body)
--   Re-grants EXECUTE to PUBLIC on the 5 target functions, restoring the pre-body ACL.
--   WARNING: this RE-WIDENS the grant (least-privilege regression -- PUBLIC EXECUTE
--   returns). Normally unnecessary because anon / authenticated keep their own EXECUTE,
--   so the app works without PUBLIC. Re-confirm the current ACL (C-3 / C-3b) before
--   using this. Touches ONLY the 5 targets' PUBLIC grant; no role/definition/table/
--   policy/data change. Runs as ONE transaction. NOT executed.
-- ============================================================
-- BEGIN;
--
-- GRANT EXECUTE ON FUNCTION public.list_notices_admin_secure(text)                                            TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_notice_secure(text, text, boolean)                                  TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_notice_secure(text, uuid, text, boolean)                            TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_notice_attachment_secure(text, uuid, text, text, text, text)        TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.delete_notice_attachment_secure(text, uuid)                                TO PUBLIC;
--
-- COMMIT;
-- ============================================================
