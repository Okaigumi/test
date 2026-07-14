-- ============================================================
-- Phase 4-F-2B-7: subcontractors direct read revoke (final privilege cleanup)
--   Remove the residual direct SELECT grant on public.subcontractors for
--   anon / authenticated, and drop the now-unnecessary sub_read policy, after the
--   front-end (index.html / genka-app.html) has been migrated to the subcontractors
--   read RPCs (list_subcontractors_secure / list_subcontractors_admin_secure) and
--   admin-app.html's dead direct read has been removed.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - This file removes exactly ONE privilege (SELECT for anon / authenticated on
--     public.subcontractors) and drops exactly ONE policy (sub_read). Nothing else is
--     touched.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / body / post-check are run by the user.
--   - Run this file SECTION BY SECTION in this order:
--     PRE-CHECK (C-1..C-8) -> EXECUTION BODY (single transaction) -> POST-CHECK
--     (P-1..P-11) -> SMOKE TEST (browser) -> ROLLBACK only in an emergency.
--
-- [PURPOSE]
--   - The subcontractors read path has been fully migrated to secure read RPCs:
--       index.html      loadSubcontractors -> list_subcontractors_secure
--       genka-app.html  startApp           -> list_subcontractors_admin_secure
--       admin-app.html  startApp           -> direct read + dead _subcontractors REMOVED
--     Front-end migration PR #120 merged; Production commit 025a173; Vercel Production
--     Ready; all three screens verified (see [FRONT-END PRECONDITIONS] / C-7).
--   - Remove the direct SELECT grant held by anon / authenticated on
--     public.subcontractors (no longer used by the app; the two read RPCs are
--     SECURITY DEFINER and do not depend on this grant).
--   - Drop the sub_read policy, which becomes unnecessary once the direct SELECT grant
--     is removed (subcontractors has no other, non-SELECT policy).
--
-- [PRECONDITIONS] (verified in the repo / production BEFORE this file; SQL cannot
--   check these -- recorded here as confirmed facts; re-confirmed in C-7)
--   - PR #120 merged; Production commit 025a173; Vercel Production = Ready.
--   - subcontractors direct read (`.from('subcontractors')` / `.from("subcontractors")`)
--     = 0 in the front-end application code (index.html / admin-app.html /
--     genka-app.html). Documentation string hits inside docs/sql (this file's comments
--     / search examples) are EXCLUDED.
--   - index.html uses list_subcontractors_secure; genka-app.html uses
--     list_subcontractors_admin_secure; admin-app.html no longer reads subcontractors.
--   - Production, all three screens verified: no Console errors;
--     list_subcontractors_secure = 200; list_subcontractors_admin_secure = 200;
--     NO /rest/v1/subcontractors direct GET.
--
-- [SCOPE]
--   - public.subcontractors SELECT privilege for anon / authenticated (REVOKE).
--   - public.subcontractors sub_read policy (DROP).
--
-- [NON-SCOPE] (intentionally NOT touched here -- this file is a privilege cleanup
--   ONLY; it changes NO RPC, NO data, and NO write protection)
--   - subcontractors data (no DML; row count / active breakdown must be unchanged --
--     see C-6 / P-6). total = 3, active = 3, inactive = 0.
--   - INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN privileges
--     for anon / authenticated (already false; must stay false -- see C-8 / P-7).
--   - RLS enabled state / FORCE RLS / owner (unchanged).
--   - read RPC definitions (list_subcontractors_secure / list_subcontractors_admin_secure)
--     and their EXECUTE grants / ACL (unchanged -- see C-4 / C-4b / P-4 / P-4b).
--   - export_projects_summary_secure (reads subcontractors internally as SECURITY
--     DEFINER; reused / unaffected, NOT modified -- see C-5 / C-5b / P-5 / P-5b).
--   - postgres / service_role / any other role's privileges.
--   - front-end code.
--   - other tables / other policies / other routines.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence)
--   - C-1: subcontractors is missing, relkind <> 'r', RLS <> true, FORCE RLS <> false,
--          or owner <> postgres.
--   - C-2: anon or authenticated SELECT is already false (state differs from the
--          assumption -> the revoke may already be applied; STOP and reconcile), or any
--          of INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN is
--          true.
--   - C-2b: a PUBLIC SELECT ACL exists on subcontractors (a plain REVOKE FROM anon,
--          authenticated would NOT close a PUBLIC grant), or the direct
--          anon / authenticated SELECT ACL is missing while C-2 effective SELECT = true.
--   - C-3: sub_read is missing, its definition differs (PERMISSIVE / roles {public} /
--          cmd SELECT / qual true / with_check null), any additional policy exists, or
--          policy_count <> 1.
--   - C-4: either read RPC is missing, not SECURITY DEFINER, not STABLE, owner not
--          postgres, search_path not fixed, signature differs, or return type differs.
--   - C-4b: either read RPC's anon / authenticated / postgres / service_role EXECUTE is
--          not true, a PUBLIC EXECUTE is present, or the explicit ACL differs from the
--          baseline.
--   - C-5: export_projects_summary_secure is missing or any attribute differs from the
--          baseline (SECURITY DEFINER = true, STABLE, owner postgres, fixed search_path,
--          identity arguments).
--   - C-5b: export_projects_summary_secure EXECUTE / ACL differs from the baseline
--          (anon / authenticated / postgres / service_role EXECUTE = true, no PUBLIC
--          EXECUTE, explicit ACL, is_grantable = false).
--   - C-6: subcontractors row count / active breakdown has changed in an unexpected way.
--          Record it as the P-6 invariant; if it differs, do NOT assert a cause --
--          investigate first (this file performs NO DML).
--   - C-7: any front-end / repository precondition is NOT satisfied (e.g. a
--          subcontractors direct read reappears in the front-end application code) ->
--          STOP; do NOT run the body.
--   - C-8: any of the 7 write-class table privileges (INSERT / UPDATE / DELETE /
--          TRUNCATE / REFERENCES / TRIGGER / MAINTAIN) is true for anon / authenticated.
--   - The body would change any RPC / data / write protection / any object beyond the
--          two SCOPE operations -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Restores the direct SELECT grant and re-creates sub_read exactly as recorded in
--   C-3 (PERMISSIVE / FOR SELECT / TO public / USING (true)). Emergency use only;
--   normally unnecessary because the front-end is already on the RPCs. It re-weakens
--   security (re-opens the direct read), so use it ONLY for emergency recovery.
--   NOT executed.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. subcontractors table attributes.
--    Expected: 1 row, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres.
--    STOP if the table is missing or anything differs.
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

-- C-2. anon / authenticated table grants on subcontractors.
--    Expected: SELECT = true (both roles); INSERT / UPDATE / DELETE / TRUNCATE /
--      REFERENCES / TRIGGER / MAINTAIN = false (both roles).
--    STOP if SELECT is already false, or if any of the other 7 privileges is true.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this project runs
--      PG 17.x). If this query errors on MAINTAIN on an older server, re-run it without
--      the can_maintain column -- treat that safely and do NOT skip the other columns.
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

-- C-2b. subcontractors SELECT ACL (grant source), so the REVOKE reliably closes it.
--    Expected: exactly one direct SELECT ACL for anon and one for authenticated;
--      is_grantable = false; NO PUBLIC SELECT ACL. (Baseline raw table ACL:
--      {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,
--       service_role=arwdDxtm/postgres}.)
--    STOP if a PUBLIC SELECT ACL exists (a plain REVOKE FROM anon, authenticated would
--      NOT close a PUBLIC grant), or if the direct anon / authenticated SELECT ACL is
--      missing while C-2 effective SELECT = true (grant source is unexpected --
--      reconcile before running the body).
--    NOTE: service_role keeps its SELECT (part of arwdDxtm) and is out of scope here;
--      this query intentionally filters to PUBLIC / anon / authenticated only.
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
  and c.relname = 'subcontractors'
  and acl.privilege_type = 'SELECT'
  and (
    acl.grantee = 0
    or r.rolname in ('anon', 'authenticated')
  )
order by grantee;

-- C-3. subcontractors policies -- full definition (also the ROLLBACK source).
--    Expected: exactly 1 row, matching EXACTLY:
--      sub_read : PERMISSIVE, roles {public}, cmd SELECT, qual true, with_check null.
--    STOP if sub_read is missing or differs, if any additional policy exists, or if
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
  and tablename = 'subcontractors'
order by cmd, policyname;

select count(*) as policy_count   -- expect 1 (sub_read only)
from pg_policies
where schemaname = 'public'
  and tablename = 'subcontractors';

-- C-4. subcontractors read RPCs (must KEEP working after the revoke).
--    Expected: 2 rows -- list_subcontractors_secure(text) and
--      list_subcontractors_admin_secure(text) -- each SECURITY DEFINER = true,
--      volatility = 's' (STABLE), owner = postgres, config contains
--      search_path=public, extensions, identity arguments "session_token_input text".
--    STOP if either is missing or any attribute differs.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as is_security_definer,   -- expect true
  p.provolatile                             as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner)               as owner,                 -- expect postgres
  p.proconfig                               as config,                -- expect search_path=public, extensions
  pg_get_function_identity_arguments(p.oid) as identity_arguments     -- expect session_token_input text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname;

-- C-4 (return types). read RPC TABLE OUT columns.
--    Expected for BOTH: 2 columns -- (1) id uuid, (2) name text.
--    STOP if the return type differs.
select
  p.proname,
  row_number() over (
    partition by p.oid
    order by t.ord
  ) as return_ordinal,
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

-- C-4b. read RPC EXECUTE privileges + full ACL + PUBLIC EXECUTE absence.
--    Expected (both functions): can_execute = true for anon / authenticated /
--      postgres / service_role.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname, v.grantee;

--    Expected ACL (both functions): exactly the 4 grantees above with EXECUTE,
--      is_grantable = false, NO PUBLIC row, explicit (non-NULL) ACL, i.e.
--      {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
--    STOP if a PUBLIC row appears or the ACL differs from the baseline.
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
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname, grantee, acl.privilege_type;

-- C-5. export_projects_summary_secure baseline (reads subcontractors internally as
--    SECURITY DEFINER; baseline for "did not break it" -- P-5). This file does NOT
--    alter it.
--    Expected: 1 row, security_definer = true, volatility = 's' (STABLE),
--      owner = postgres, config contains search_path=public, extensions.
--    STOP if it is missing or any attribute differs.
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,       -- expect true
  p.provolatile   as volatility,             -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,      -- expect postgres
  p.proconfig     as config,                 -- expect search_path=public, extensions
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure';

-- C-5b. export_projects_summary_secure EXECUTE + ACL baseline (for the P-5b
--    "unchanged" comparison). This file does NOT alter it.
--    Expected: can_execute = true for anon / authenticated / postgres / service_role.
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

--    Expected ACL: exactly those 4 grantees with EXECUTE, is_grantable = false,
--      NO PUBLIC row, explicit (non-NULL) ACL.
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

-- C-6. subcontractors data baseline (INVARIANT, not reference-only).
--    Record the counts. Expected (last recorded 2026-07-13): total = 3, active = 3,
--      inactive = 0, null_active = 0.
--    This file performs NO DML, so P-6 must equal these values. A difference at P-6
--    means external write activity (not this file) -- investigate before concluding;
--    do NOT assert a cause.
select
  count(*)                                    as total,       -- expect 3
  count(*) filter (where is_active = true)    as active,      -- expect 3
  count(*) filter (where is_active = false)   as inactive,    -- expect 0
  count(*) filter (where is_active is null)   as null_active  -- expect 0
from public.subcontractors;

-- C-7. front-end / repository preconditions (NOT checkable from SQL; confirmed from the
--    repo / production BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html / genka-app.html.
--    Documentation string hits inside docs/sql (this file's comments / search examples)
--    are EXCLUDED from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - subcontractors direct read (`.from('subcontractors')` / `.from("subcontractors")`)
--      = 0 in the front-end application code (repo-confirmed on Production commit 025a173).
--    - index.html loadSubcontractors references list_subcontractors_secure.
--    - genka-app.html startApp references list_subcontractors_admin_secure.
--    - admin-app.html no longer reads subcontractors (direct read + dead _subcontractors
--      removed).
--    - PR #120 merged; Production commit 025a173; Vercel Production = Ready.
--    - Production verified on all three screens: RPC 200
--      (list_subcontractors_secure / list_subcontractors_admin_secure); NO
--      /rest/v1/subcontractors direct GET; no Console errors.

-- C-8. write-class table privileges for anon / authenticated remain all false.
--    Expected: INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN =
--      false for BOTH roles (this is the write-protection invariant re-confirmed at
--      P-7; this file changes NO write privilege).
--    STOP if any of these is true.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.subcontractors', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.subcontractors', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.subcontractors', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.subcontractors', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.subcontractors', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;


-- ============================================================
-- EXECUTION BODY
--   Run ONLY after the pre-checks (C-1..C-8) are re-confirmed with no STOP condition
--   hit. This BODY runs as a SINGLE transaction (BEGIN ... COMMIT): the REVOKE and the
--   DROP POLICY succeed together or not at all.
--   DROP POLICY is used WITHOUT "IF EXISTS" on purpose: if sub_read is unexpectedly
--   absent, the statement errors, the transaction aborts, and the REVOKE is rolled back
--   as well (nothing is half-applied).
--   EXACTLY these 2 operations -- nothing else. No RPC / data / write privilege is
--   touched. This BODY is intended to be run ONCE.
-- ============================================================

BEGIN;

REVOKE SELECT
ON TABLE public.subcontractors
FROM anon, authenticated;

DROP POLICY sub_read
ON public.subcontractors;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. anon / authenticated table grants after the revoke.
--    Expected: all 8 privileges = false for BOTH roles (SELECT now revoked; the other
--      7 already false and unchanged from C-2 / C-8).
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

-- P-1b. subcontractors SELECT ACL after the revoke.
--    Expected: 0 rows -- no PUBLIC / anon / authenticated SELECT ACL remains (mirrors
--      C-2b; the direct SELECT grant is gone). service_role's SELECT is out of scope
--      and intentionally not listed here.
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
  and c.relname = 'subcontractors'
  and acl.privilege_type = 'SELECT'
  and (
    acl.grantee = 0
    or r.rolname in ('anon', 'authenticated')
  )
order by grantee;

-- P-2. subcontractors policies after the drop.
--    Expected: 0 rows and policy_count = 0 -- sub_read is gone; no policy remains
--      (subcontractors had no non-SELECT policy).
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'subcontractors'
order by cmd, policyname;

select count(*) as policy_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'subcontractors';

-- P-3. subcontractors table attributes UNCHANGED.
--    Expected: rls_enabled = true, rls_forced = false, owner = postgres.
select
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'subcontractors';

-- P-4. read RPCs UNCHANGED (signature + attributes) from C-4.
--    Expected: 2 rows, SECURITY DEFINER, STABLE, owner postgres, fixed search_path,
--      identity arguments "session_token_input text"; and TABLE columns (id uuid,
--      name text) for both.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as is_security_definer,
  p.provolatile                             as volatility,
  pg_get_userbyid(p.proowner)               as owner,
  p.proconfig                               as config,
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname;

select
  p.proname,
  row_number() over (
    partition by p.oid
    order by t.ord
  ) as return_ordinal,
  t.argname  as out_column,
  format_type(t.argtype, null) as out_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
  with ordinality as t(argtype, argmode, argname, ord)
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
  and t.argmode = 't'
order by p.proname, t.ord;

-- P-4b. read RPC EXECUTE / ACL / PUBLIC EXECUTE UNCHANGED from C-4b.
--    Expected: can_execute = true for anon / authenticated / postgres / service_role
--      (both functions); explicit ACL with those 4 grantees, is_grantable = false;
--      NO PUBLIC row.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname, v.grantee;

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
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_subcontractors_secure', 'list_subcontractors_admin_secure')
order by p.proname, grantee, acl.privilege_type;

-- P-5. export_projects_summary_secure UNCHANGED from the C-5 baseline.
--    Expected: identical to C-5 (SECURITY DEFINER = true, STABLE, owner postgres,
--      fixed search_path, identity arguments unchanged).
select
  p.proname       as function_name,
  p.prosecdef     as security_definer,
  p.provolatile   as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig     as config,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'export_projects_summary_secure';

-- P-5b. export_projects_summary_secure EXECUTE / ACL UNCHANGED from the C-5b baseline.
--    Expected: can_execute = true for anon / authenticated / postgres / service_role;
--      explicit ACL with those 4 grantees, is_grantable = false; NO PUBLIC row.
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

-- P-6. subcontractors data UNCHANGED from the C-6 baseline (INVARIANT).
--    Expected: total = 3, active = 3, inactive = 0, null_active = 0 (equals C-6). The
--      body performs no DML, so this must match; any difference is external write
--      activity, not this file -- investigate, do NOT assert a cause.
select
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.subcontractors;

-- P-7. write-class table privileges for anon / authenticated STILL all false
--    (unchanged from C-8; this file changed no write privilege).
--    Expected: INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN =
--      false for BOTH roles.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.subcontractors', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.subcontractors', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.subcontractors', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.subcontractors', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.subcontractors', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.subcontractors', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-8. read RPCs still return the 3 active subcontractors (positive check).
--    NOTE: requires VALID session tokens; run in the SMOKE TEST step. Do NOT paste any
--      real token into this file -- replace <...> at run time.
--    Expected: 3 rows each (id / name), ordered by name; matching public.subcontractors
--      where is_active = true (C-6 active = 3).
--
--   select id, name from public.list_subcontractors_secure('<valid employee session token>');
--   select count(*) from public.list_subcontractors_secure('<valid employee session token>');       -- expect 3
--   select id, name from public.list_subcontractors_admin_secure('<valid management session token>');
--   select count(*) from public.list_subcontractors_admin_secure('<valid management session token>'); -- expect 3
--
--   -- set-equality vs the table (expect 0 rows both ways), employee RPC:
--   with rpc as (
--     select id, name from public.list_subcontractors_secure('<valid employee session token>')
--   ),
--   src as (
--     select id, name from public.subcontractors where is_active = true
--   )
--   select 'rpc_only' as side, id, name from (select * from rpc except select * from src) d
--   union all
--   select 'src_only' as side, id, name from (select * from src except select * from rpc) d;

-- P-9. read RPCs reject an invalid / expired session (negative check).
--    NOTE: run in the SMOKE TEST step.
--    Expected: both raise 'Invalid or expired session' (surfaced as an HTTP 400 RPC
--      exception from PostgREST), returning NO rows.
--
--   select * from public.list_subcontractors_secure('not-a-real-token');
--   select * from public.list_subcontractors_admin_secure('not-a-real-token');

-- P-10. production screen smoke test (browser; performed by the user AFTER the body +
--    post-check; reload / re-login first so no cached data masks a failure).
--    Confirm on all three screens:
--    - index.html (employee session): subcontractor chips render (3); selection works;
--      daily-report subcontractor-name resolution works.
--        Network: list_subcontractors_secure = 200; NO /rest/v1/subcontractors GET.
--        Console: no errors (incl. 'list_subcontractors_secure failed:').
--    - genka-app.html (management session): forwarding cost calculation + subcontractor
--      name display work.
--        Network: list_subcontractors_admin_secure = 200; NO /rest/v1/subcontractors GET.
--        Console: no errors (incl. 'list_subcontractors_admin_secure failed:').
--    - admin-app.html (management session): initial load OK; main pages navigate.
--        Network: NO /rest/v1/subcontractors GET (admin-app no longer reads it).
--        Console: no errors.
--
--    Direct read rejection check (optional; do NOT record any real token):
--      -- From the browser Console in a logged-in app session (anon key context):
--         const r = await sb.from('subcontractors').select('id').limit(1);
--         console.log(r.error);
--         -- Expected: a permission-denied error object, data = null (direct read shut).
--      -- Equivalently in the SQL Editor (roles only; no app token involved):
--         select has_table_privilege('anon',          'public.subcontractors', 'SELECT');
--         select has_table_privilege('authenticated', 'public.subcontractors', 'SELECT');
--         -- Expected: false / false (same as P-1).

-- P-11. export smoke test (browser; performed by the user).
--    export_projects_summary_secure reads subcontractors internally as SECURITY
--    DEFINER; confirm it still works after the revoke (the SECURITY DEFINER function
--    owner keeps table access; the revoke only removed anon / authenticated direct
--    SELECT).
--    - genka-app.html / the projects-summary CSV export path: generate the projects
--      summary / CSV and confirm subcontractor-related figures still populate.
--        Network: export_projects_summary_secure = 200; NO /rest/v1/subcontractors GET.
--        Console: no errors.


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Restores the direct SELECT grant and re-creates sub_read exactly as recorded in the
--   C-3 pre-check (PERMISSIVE / FOR SELECT / TO public / USING (true)). This RE-WEAKENS
--   security by re-opening the anon / authenticated direct read, so use it ONLY for
--   emergency recovery. Normally unnecessary because index.html / genka-app.html are
--   already on the read RPCs and admin-app.html no longer reads the table.
--   Re-confirm the current state (C-1..C-3) before using this.
--   NOT executed.
-- ============================================================
-- BEGIN;
--
-- GRANT SELECT
-- ON TABLE public.subcontractors
-- TO anon, authenticated;
--
-- CREATE POLICY sub_read
-- ON public.subcontractors
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- COMMIT;
-- ============================================================
