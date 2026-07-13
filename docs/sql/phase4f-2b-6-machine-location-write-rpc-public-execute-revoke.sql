-- ============================================================
-- Phase 4-F-2B-6 (side step): revoke PUBLIC EXECUTE on the machine_locations
--   write RPC public.create_machine_location_secure(text, uuid, uuid, text).
--
--   Discovered during the machine_locations direct-read-revoke pre-check: the write
--   RPC carries an explicit PUBLIC EXECUTE grant in addition to the per-role grants
--   (anon / authenticated / service_role / postgres). No auth bypass was found -- the
--   function verifies the employee session internally and derives moved_by from the
--   session -- but PUBLIC EXECUTE is unnecessary excess privilege. anon and
--   authenticated keep their own explicit EXECUTE, so only PUBLIC is removed.
-- ============================================================
-- [STATUS] EXECUTED 2026-07-13
--   - This file removes exactly ONE privilege: EXECUTE for PUBLIC on
--     public.create_machine_location_secure(text, uuid, uuid, text). Nothing else is
--     touched.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / body / post-check are run by the user.
--   - Run this file SECTION BY SECTION in this order:
--     PRE-CHECK (C-1..C-4) -> EXECUTION BODY (single transaction) -> POST-CHECK
--     (P-1..P-5) -> ROLLBACK only in an emergency.
--   - This is a SIDE STEP of Phase 4-F-2B-6. The machine_locations direct-read-revoke
--     BODY (docs/sql/phase4f-2b-6-machine-locations-direct-read-revoke.sql) has NOT
--     been run yet; return to that pre-check after this file is executed / verified.
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-13)
--     - The user ran the EXECUTION BODY manually:
--         BEGIN;
--         REVOKE EXECUTE ON FUNCTION
--           public.create_machine_location_secure(text, uuid, uuid, text) FROM PUBLIC;
--         COMMIT;
--       Result: Success. No rows returned.
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--
--   [PRE-CHECK RESULT] (C-1..C-4, Supabase SQL Editor, 2026-07-13 -- all passed)
--     - C-1: create_machine_location_secure(text, uuid, uuid, text) present;
--       SECURITY DEFINER = true, volatility = 'v' (VOLATILE), owner = postgres,
--       search_path = public, extensions, result type = TABLE(id uuid);
--       args = session_token_input text / machine_id_input uuid / site_id_input uuid /
--       memo_input text.
--     - C-2: effective EXECUTE -- anon / authenticated / postgres / service_role = true.
--     - C-3: EXECUTE ACL -- PUBLIC / anon / authenticated / postgres / service_role,
--       each is_grantable = false.
--     - C-3b: execute_acl_count = 5;
--       grantees = {PUBLIC, anon, authenticated, postgres, service_role};
--       grantable_count = 0.
--     - C-4: function definition confirmed to contain the security controls
--       (employee_sessions.token_hash match, expires_at > now(),
--        employees.is_active = true, RAISE 'Invalid or expired session',
--        moved_by from the verified session, INSERT into public.machine_locations).
--
--   [POST-CHECK RESULT] (P-1..P-5, Supabase SQL Editor, 2026-07-13 -- all passed)
--     - P-1: effective EXECUTE -- anon / authenticated / postgres / service_role = true.
--     - P-2: EXECUTE ACL -- NO PUBLIC row; anon / authenticated / postgres /
--       service_role remain, each is_grantable = false.
--     - P-2b: PUBLIC EXECUTE = 0 rows.
--     - P-2c: execute_acl_count = 4;
--       grantees = {anon, authenticated, postgres, service_role}; grantable_count = 0.
--     - P-3: function attributes unchanged from C-1.
--     - P-4: function definition unchanged from C-4.
--     - P-5 (non-scope, all unchanged): machine_locations data / table grants /
--       ml_read / ml_write / RLS / FORCE RLS / read RPC 2 / anon / authenticated /
--       postgres / service_role EXECUTE.
--
--   [OUTCOME]
--     - PUBLIC EXECUTE on the write RPC: revoked.
--     - anon / authenticated / postgres / service_role EXECUTE: KEPT (unchanged).
--     - Function attributes / definition: unchanged.
--     - table / policy / RLS / data: unchanged.
--     - Write smoke test (recording a real move): NOT performed on purpose -- no
--       throwaway move-history rows created; the write path is confirmed intact by
--       P-3 / P-4 (attributes / definition) and P-1 / P-2 (per-role EXECUTE).
--     - ROLLBACK: NOT executed (kept as commented reference only).
--     - The machine_locations direct-read-revoke BODY is still NOT run; return to that
--       pre-check after this record is merged.
--
-- [PURPOSE]
--   - Remove the redundant PUBLIC EXECUTE grant on the write RPC. The app calls the
--     RPC as anon / authenticated, both of which retain their own explicit EXECUTE, so
--     removing PUBLIC does not affect the application.
--
-- [SCOPE]
--   - EXECUTE privilege for PUBLIC on
--     public.create_machine_location_secure(text, uuid, uuid, text).
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - The function definition / body (no CREATE OR REPLACE, no DROP FUNCTION).
--   - EXECUTE for anon / authenticated / service_role / postgres (all kept).
--   - machine_locations data.
--   - machine_locations table grants (SELECT etc.).
--   - ml_read / ml_write policies.
--   - RLS / FORCE RLS / owner.
--   - read RPCs (list_machine_current_locations_secure /
--     list_machine_location_history_secure).
--   - the machine_locations direct-read-revoke BODY (separate file; not run here).
--   - any other table / function / policy / role.
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence)
--   - C-1: create_machine_location_secure(text, uuid, uuid, text) is missing, its
--          signature differs, it is not SECURITY DEFINER, not VOLATILE, owner not
--          postgres, search_path not fixed, or result type <> TABLE(id uuid).
--   - C-2: PUBLIC EXECUTE is already false (nothing to revoke -- reconcile first), or
--          any of anon / authenticated / service_role / postgres EXECUTE is false.
--          (PUBLIC is confirmed via the C-3 ACL; see the C-2 note.)
--   - C-3 / C-3b: PUBLIC has no explicit EXECUTE ACL entry; the EXECUTE ACL grantee
--          set is not EXACTLY {PUBLIC, anon, authenticated, postgres, service_role}
--          (any missing or any unexpected EXECUTE grantee); execute_acl_count <> 5; or
--          any is_grantable is not false. Any of these -> STOP.
--   - C-4: the recorded function definition is not as expected (see C-4).
--
-- [ROLLBACK] (see the commented section at the end)
--   Re-grants EXECUTE to PUBLIC. Emergency use only; normally unnecessary because
--   anon / authenticated keep their own EXECUTE.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. create_machine_location_secure attributes.
--    Expected: 1 row -- signature create_machine_location_secure(text, uuid, uuid,
--      text), security_definer = true, volatility = 'v' (VOLATILE), owner = postgres,
--      config contains search_path=public, extensions, result_type = TABLE(id uuid).
--    STOP if the function is missing, the signature differs, or any attribute
--    (incl. result type) differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,      -- expect true
  p.provolatile               as volatility,            -- expect 'v' (VOLATILE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid)             as result_type,  -- expect TABLE(id uuid)
  pg_get_function_identity_arguments(p.oid) as args           -- expect text, uuid, uuid, text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
order by p.proname;

-- C-2. effective EXECUTE for the real roles.
--    Expected: anon = true, authenticated = true, service_role = true, postgres = true.
--    STOP if any is false.
--    NOTE on PUBLIC: has_function_privilege() cannot take PUBLIC as an argument
--      (there is no 'public' role; passing it errors). PUBLIC's explicit EXECUTE is
--      therefore verified authoritatively in C-3 (the ACL), where grantee OID 0 =
--      PUBLIC. The four role checks below being true does NOT by itself distinguish a
--      PUBLIC grant from a per-role grant -- C-3 is the source of truth for PUBLIC.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute
from (values ('anon'), ('authenticated'), ('service_role'), ('postgres')) as v(grantee)
order by v.grantee;

-- C-3. create_machine_location_secure EXECUTE ACL (explicit grants; source of truth
--    for PUBLIC). Also the field this file changes.
--    Expected: 5 EXECUTE rows -- PUBLIC, anon, authenticated, service_role, postgres --
--      each is_grantable = false. In particular, PUBLIC (grantee OID 0) MUST have an
--      explicit EXECUTE row (that is exactly what the body removes).
--    STOP if PUBLIC has no explicit EXECUTE ACL, if any expected role's EXECUTE ACL is
--      missing, if any unexpected grantee has EXECUTE, or if any is_grantable is not
--      false. (C-3b below verifies the grantee set / count exactly.)
--    NOTE: coalesce(..., acldefault('f', proowner)) covers a NULL proacl (default
--      PUBLIC EXECUTE); grantee OID 0 = PUBLIC, shown via CASE (never cast 0::regrole).
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
  and acl.privilege_type = 'EXECUTE'
order by grantee;

-- C-3b. EXECUTE ACL set completeness -- exact match to the expected 5 grantees.
--    Confirms the whole grantee set (not just row count): guards against an unexpected
--    grantee also holding EXECUTE.
--    Expected: execute_acl_count = 5;
--      grantees = {PUBLIC, anon, authenticated, postgres, service_role}
--        (array_agg is sorted by grantee for a fixed, comparable order);
--      grantable_count = 0.
--    STOP if execute_acl_count <> 5, if the grantee set does not match exactly (any
--      missing or any unexpected EXECUTE grantee), or if grantable_count <> 0.
select
  count(*)                                as execute_acl_count,   -- expect 5
  array_agg(g.grantee order by g.grantee) as grantees,            -- expect {PUBLIC,anon,authenticated,postgres,service_role} (sorted)
  count(*) filter (where g.is_grantable)  as grantable_count      -- expect 0
from (
  select
    case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
    acl.is_grantable
  from pg_proc p
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
    and acl.privilege_type = 'EXECUTE'
) g;

-- C-4. function definition baseline (UNCHANGED by this file; re-checked in P-4).
--    Record pg_get_functiondef. Confirm the recorded definition still contains the
--    security controls this RPC relies on (this file does NOT alter the definition):
--      - session token hash match against employee_sessions.token_hash
--        (encode(digest(session_token_input, 'sha256'), 'hex')),
--      - es.expires_at > now(),
--      - employees.is_active = true,
--      - RAISE 'Invalid or expired session' on an invalid / expired session,
--      - moved_by is set from the verified employee_id (not from the client),
--      - INSERT target is public.machine_locations.
--    STOP if the definition is not as expected.
select pg_get_functiondef(
  'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
) as function_definition;


-- ============================================================
-- EXECUTION BODY
--   Run ONLY after the pre-checks (C-1..C-4) are re-confirmed with no STOP condition
--   hit. This BODY runs as a SINGLE transaction (BEGIN ... COMMIT) and performs
--   EXACTLY ONE operation: revoke EXECUTE from PUBLIC. It does NOT use DROP FUNCTION or
--   CREATE OR REPLACE FUNCTION, and does NOT touch anon / authenticated / service_role
--   / postgres EXECUTE.
-- ============================================================

BEGIN;

REVOKE EXECUTE
ON FUNCTION public.create_machine_location_secure(text, uuid, uuid, text)
FROM PUBLIC;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. effective EXECUTE for the real roles (unchanged; PUBLIC via P-2).
--    Expected: anon = true, authenticated = true, service_role = true, postgres = true.
--    (PUBLIC's removal is verified in P-2 by the ACL; has_function_privilege cannot
--     take PUBLIC -- see the C-2 note.)
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.create_machine_location_secure(text, uuid, uuid, text)', 'EXECUTE') as can_execute
from (values ('anon'), ('authenticated'), ('service_role'), ('postgres')) as v(grantee)
order by v.grantee;

-- P-2. create_machine_location_secure EXECUTE ACL after the revoke.
--    Expected: NO PUBLIC EXECUTE row (grantee OID 0 gone); anon / authenticated /
--      service_role / postgres EXECUTE rows remain, each is_grantable = false
--      (unchanged from C-3).
--    FAIL if PUBLIC or any unexpected grantee still holds EXECUTE, if any expected
--      role's EXECUTE ACL is missing, or if any is_grantable is not false.
--      (P-2c below verifies the grantee set / count = 4 exactly.)
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
  and acl.privilege_type = 'EXECUTE'
order by grantee;

-- P-2b. PUBLIC EXECUTE explicitly absent (expect 0 rows).
select
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
  and acl.grantee = 0                 -- 0 = PUBLIC; expect 0 rows
  and acl.privilege_type = 'EXECUTE'
order by grantee;

-- P-2c. EXECUTE ACL set completeness after the revoke -- exact match to 4 grantees.
--    Confirms PUBLIC is gone and no unexpected grantee appeared.
--    Expected: execute_acl_count = 4;
--      grantees = {anon, authenticated, postgres, service_role} (sorted);
--      grantable_count = 0; NO PUBLIC.
--    FAIL if execute_acl_count <> 4, if PUBLIC or any unexpected grantee remains, if
--      any expected role is missing, or if grantable_count <> 0.
select
  count(*)                                as execute_acl_count,   -- expect 4
  array_agg(g.grantee order by g.grantee) as grantees,            -- expect {anon,authenticated,postgres,service_role} (sorted)
  count(*) filter (where g.is_grantable)  as grantable_count      -- expect 0
from (
  select
    case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
    acl.is_grantable
  from pg_proc p
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
    and acl.privilege_type = 'EXECUTE'
) g;

-- P-3. create_machine_location_secure attributes UNCHANGED from C-1.
--    Expected: identical to C-1 (signature, security_definer = true, VOLATILE, owner
--      postgres, fixed search_path, result_type = TABLE(id uuid)).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid)             as result_type,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = 'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
order by p.proname;

-- P-4. function definition UNCHANGED from the C-4 baseline.
--    Expected: identical to C-4 (only the PUBLIC EXECUTE grant changed; the function
--      body / definition is untouched).
select pg_get_functiondef(
  'public.create_machine_location_secure(text, uuid, uuid, text)'::regprocedure
) as function_definition;

-- P-5. NON-SCOPE confirmation (nothing below was changed by this file):
--    - machine_locations data.
--    - machine_locations table grants (anon / authenticated SELECT etc.).
--    - ml_read / ml_write policies.
--    - RLS / FORCE RLS / owner.
--    - read RPCs (list_machine_current_locations_secure /
--      list_machine_location_history_secure).
--    - EXECUTE for anon / authenticated / service_role / postgres on the write RPC.
--    (These are outside this file's single REVOKE and are listed here as an explicit
--     reminder; no query is required to prove a no-op, but P-1 / P-2 above already
--     show the per-role EXECUTE grants are intact.)


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Re-grants EXECUTE to PUBLIC on the write RPC. Normally unnecessary because
--   anon / authenticated keep their own EXECUTE. Before using this, re-confirm the
--   reason and the current ACL (C-2 / C-3). Does NOT touch anon / authenticated /
--   service_role / postgres grants or the function definition.
-- ============================================================
-- BEGIN;
--
-- GRANT EXECUTE
-- ON FUNCTION public.create_machine_location_secure(text, uuid, uuid, text)
-- TO PUBLIC;
--
-- COMMIT;
-- ============================================================
