-- ============================================================
-- Phase 4-F-2B-9-c: notices direct read revoke (final privilege cleanup)
--   Remove the residual direct SELECT grant on public.notices for
--   anon / authenticated, and drop the now-unnecessary notices_read_all policy,
--   after the front-end (index.html loadNotice) has been migrated to the notices
--   read RPC (list_notices_secure) and verified in production.
--   This is the THIRD and FINAL stage of the standard 3-stage read migration
--   (read RPC -> front-end move -> direct read shutdown) for public.notices,
--   matching phase4f-2b-7-subcontractors-direct-read-revoke.sql and
--   phase4f-2b-8-sites-site-assignments-direct-read-revoke.sql.
-- ============================================================
-- [STATUS] NOT EXECUTED (as of this file's creation)
--   - This file removes exactly TWO privileges (SELECT for anon / authenticated on
--     public.notices) and drops exactly ONE policy (notices_read_all). Nothing else
--     is touched.
--   - DB execution is done by the USER, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / guard / body / post-check / smoke are run by the user.
--   - The EXECUTION BODY is reviewed FIRST and then run exactly ONCE. As of this
--     file's creation it has NOT been run (STATUS above stays NOT EXECUTED until the
--     user records the execution result in a separate docs step).
--   - Intended run order: PRE-CHECK (C-1..C-8) -> EXECUTION BODY (single transaction:
--     read-only GUARD G-1..G-6 + 2 REVOKE + 1 DROP POLICY) -> POST-CHECK (P-1..P-9) ->
--     SMOKE TEST (employee + admin, read-only). ROLLBACK is reference-only.
--
-- [FRONT-END / PRECONDITIONS] (verified in the repo / production BEFORE this file;
--   SQL cannot check these -- recorded here as confirmed facts; re-stated in C-8)
--   - 2B-9-a: public.list_notices_secure(text) created in the real DB (read RPC),
--     recorded in PR #129 (docs/db-migrations.md).
--   - 2B-9-b: index.html loadNotice() migrated from the direct read to
--     list_notices_secure; PR #130 merged; Vercel Production deployed and verified
--     (list_notices_secure POST 200; /rest/v1/notices direct GET 0; notices render
--     normally; no RPC-origin Console errors).
--   - notices direct read (`.from('notices')` / `.from("notices")`) = 0 in the
--     front-end application code (index.html / admin-app.html / genka-app.html) as of
--     this file's creation. Repo confirmation: the only `from('notices')` hits are in
--     docs (docs/db-migrations.md, docs/sql comments), NOT in the app HTML.
--     - index.html loadNotice() -> sb.rpc('list_notices_secure', ...)  (index.html:979)
--     - admin-app.html          -> sb.rpc('list_notices_admin_secure', ...) (admin-app.html:1920)
--   - The read RPC (list_notices_secure) and the admin read RPC
--     (list_notices_admin_secure) are SECURITY DEFINER and do NOT depend on the
--     anon / authenticated direct SELECT grant; the revoke does not affect them.
--     (Re-stated in C-7.)
--
--   NOTE: This step (2B-9-c) is the LAST step of Phase 4-F-2B-9. Phase 4-F-2B-9 as a
--   whole is NOT yet complete: it becomes complete only AFTER this body is executed,
--   post-checked, smoke-tested, and recorded. Do NOT treat the mere existence of this
--   file as completion.
--
-- [PURPOSE]
--   - The notices read path is now fully migrated to the secure read RPC
--     (front-end PR #130, production verified):
--       index.html loadNotice() -> list_notices_secure
--   - Remove the direct SELECT grant held by anon / authenticated on public.notices
--     (no longer used by the app).
--   - Drop the notices_read_all policy, which becomes unnecessary once the direct
--     SELECT grant is removed (notices has no other, non-SELECT policy -- so notices
--     ends up with 0 policies, same shape as subcontractors after 2B-7).
--
-- [SCOPE] (EXACTLY three DB changes -- nothing else)
--   - REVOKE SELECT ON TABLE public.notices FROM anon.
--   - REVOKE SELECT ON TABLE public.notices FROM authenticated.
--   - DROP POLICY notices_read_all ON public.notices.
--
-- [NON-SCOPE] (intentionally NOT touched here -- this file is a privilege cleanup
--   ONLY; it changes NO RPC, NO data, NO write protection, NO table definition)
--   - notices data (no DML; counts / active breakdown must be unchanged -- see
--     C-6 / P-6). Last recorded baseline: total 4 / active 1 / inactive 3 / null 0.
--   - INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN table
--     privileges for anon / authenticated (already false; must stay false -- C-2 / P-1).
--   - RLS enabled state / FORCE RLS / owner / columns / constraints / indexes.
--   - the read RPC list_notices_secure(text) and its EXECUTE grants / ACL
--     (unchanged -- C-4 / C-4b / P-7). It is the path the app depends on after the
--     revoke; the GUARD asserts it exists (G-6).
--   - the five existing notices RPCs -- list_notices_admin_secure(text),
--     create_notice_secure(text, text, boolean),
--     update_notice_secure(text, uuid, text, boolean),
--     update_notice_attachment_secure(text, uuid, text, text, text, text),
--     delete_notice_attachment_secure(text, uuid) -- reused / unaffected, NOT modified
--     (C-5 / C-5b / P-8 / P-9). Their KNOWN PUBLIC EXECUTE is baseline, out of scope.
--   - postgres / service_role / any other role's privileges.
--   - front-end code / Storage (notice-attachments bucket) / other tables / other
--     policies / other routines.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
--   [KNOWN, INTENTIONALLY UNCHANGED] PUBLIC EXECUTE currently exists on the 5 existing
--   notices RPCs (created with GRANT ... TO anon, authenticated but NO
--   REVOKE ... FROM PUBLIC). Recorded as baseline in C-5b / P-9; OUT OF SCOPE here,
--   NOT modified, and NOT a stop condition. (This differs from list_notices_secure,
--   which correctly has NO PUBLIC EXECUTE.)
--
-- [RE-RUN SAFETY] (plain one-shot design; same pattern as 2B-8)
--   - The EXECUTION BODY is ONE transaction (BEGIN..COMMIT) whose first statement is
--     a read-only GUARD (DO block). The guard RAISEs if the DB is not in the exact
--     expected pre-state -- including the "already revoked / already dropped" case --
--     so a second run aborts the transaction BEFORE any change is attempted.
--   - DROP POLICY is used WITHOUT "IF EXISTS" on purpose: if notices_read_all is
--     unexpectedly absent (or its definition diverged), the guard has already stopped
--     the transaction; and even without the guard the bare DROP would error and roll
--     back both REVOKEs (nothing half-applied; divergence is surfaced, not hidden).
--   - Do NOT re-run the body after it has succeeded. Re-opening the direct read
--     requires the explicit ROLLBACK reference at the end (emergency only).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence. The GUARD re-asserts the machine-
--   checkable subset and aborts the transaction if violated.)
--   - C-1: notices missing, relkind <> 'r', RLS <> true, FORCE RLS <> false,
--          or owner <> postgres.
--   - C-2: anon or authenticated SELECT is already false (the revoke may already be
--          applied; STOP and reconcile), or any of the 7 write-class privileges is true.
--   - C-2b: a PUBLIC SELECT ACL exists on notices (a plain REVOKE FROM anon,
--          authenticated would NOT close a PUBLIC grant), or the direct
--          anon / authenticated SELECT ACL is missing while C-2 effective SELECT = true
--          (grant source unexpected -- reconcile before running the body).
--   - C-2c: any column-level (attribute) ACL exists on notices (would survive a
--          table-level REVOKE; must be 0 rows).
--   - C-3: notices_read_all is missing or its definition differs (PERMISSIVE /
--          roles {public} / cmd SELECT / qual true / with_check null); any ADDITIONAL
--          policy exists on notices; or total policy count <> 1.
--   - C-4: list_notices_secure is missing, not SECURITY DEFINER, not STABLE, owner not
--          postgres, search_path not fixed, signature or return type differs, EXECUTE
--          differs (anon / authenticated / postgres / service_role = true), or a PUBLIC
--          EXECUTE is present on it.
--   - C-5 / C-5b: any of the 5 existing notices RPCs is missing or differs from the
--          recorded baseline in a way OTHER than the KNOWN PUBLIC EXECUTE noted there.
--   - C-6: counts changed in an unexpected way (record as the P-6 invariant; if it
--          differs, investigate first -- this file performs NO DML; do NOT assert a cause).
--   - C-7: any front-end / repository precondition is NOT satisfied (e.g. a notices
--          direct read reappears in the front-end application code).
--   - The body would change any RPC / data / write protection / any object beyond the
--          three SCOPE operations -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Restores the two direct SELECT grants and re-creates notices_read_all exactly as
--   recorded in C-3 (PERMISSIVE / FOR SELECT / TO public / USING (true)). Limited to
--   exactly the three changes of this file. It RE-WEAKENS security (re-opens the
--   direct read), so use it ONLY for emergency recovery; normally unnecessary because
--   the employee screen is already on list_notices_secure. Requires a SEPARATE
--   explicit approval; must NOT be run in the same session right after the body.
--   NOT executed.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body. Any STOP condition -> stop.
-- ============================================================

-- C-1. notices table attributes.
--    Expected: 1 row, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres. STOP if the table is missing or anything differs.
select
  n.nspname                   as schema_name,
  c.relname                   as table_name,
  c.relkind                   as relkind,          -- expected 'r'
  c.relrowsecurity            as rls_enabled,      -- expected true
  c.relforcerowsecurity       as rls_forced,       -- expected false  (STOP if true)
  pg_get_userbyid(c.relowner) as owner             -- expected postgres
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

-- C-2. anon / authenticated table grants (all 8 privileges).
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false, for both roles.
--    STOP if SELECT is already false, or if any of the other 7 is true.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this project
--      runs PG 17.x). If this query errors on MAINTAIN on an older server, re-run it
--      without the can_maintain column -- do NOT skip the other columns.
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

-- C-2b. raw ACL + SELECT ACL (grant source), so the REVOKEs reliably close the reads.
--    Raw table ACL expected:
--      {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,
--       service_role=arwdDxtm/postgres}.
select
  c.relname as table_name,
  c.relacl  as raw_acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

--    aclexplode view -- expected: exactly one direct SELECT ACL for anon and one for
--      authenticated; is_grantable = false; NO PUBLIC SELECT ACL.
--    STOP if a PUBLIC SELECT ACL exists (a plain REVOKE FROM anon, authenticated would
--      NOT close a PUBLIC grant), or if the direct anon / authenticated SELECT ACL is
--      missing while C-2 effective SELECT = true (grant source unexpected).
--    NOTE: service_role keeps its SELECT (part of arwdDxtm) and is out of scope; this
--      query intentionally filters to PUBLIC / anon / authenticated only.
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'notices'
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by grantee;

-- C-2c. column-level (attribute) ACL on notices. Expected: 0 rows.
--    A column-level GRANT would survive a table-level REVOKE and keep a read path open.
--    STOP if any row is returned (reconcile before running the body).
select
  a.attname as column_name,
  a.attacl  as column_acl
from pg_attribute a
join pg_class c on c.oid = a.attrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attnum;

-- C-3. all policies on notices -- full definition (also the ROLLBACK source).
--    Expected: EXACTLY 1 row:
--      notices_read_all : PERMISSIVE, roles {public}, cmd SELECT, qual true,
--                         with_check null   <- DROPPED by the body
--    STOP if notices_read_all is missing or differs, if any ADDITIONAL policy exists,
--    or if policy_count <> 1.
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
order by cmd, policyname;

select count(*) as policy_count           -- expect 1 (notices_read_all only)
from pg_policies
where schemaname = 'public'
  and tablename = 'notices';

select count(*) as select_policy_count    -- expect 1
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
  and cmd = 'SELECT';

-- C-4. list_notices_secure -- the read RPC the app depends on (must KEEP working).
--    Expected: 1 row -- list_notices_secure(text), SECURITY DEFINER = true,
--      volatility = 's' (STABLE), owner = postgres, config contains
--      search_path=public, extensions, identity arguments "session_token_input text".
--    STOP if it is missing or any attribute differs.
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
  and p.proname = 'list_notices_secure';

-- C-4 (return types). read RPC TABLE OUT columns.
--    Expected: 1 content text, 2 attachment_url text, 3 attachment_type text,
--      4 attachment_name text. STOP if the return type differs.
select
  p.proname,
  row_number() over (
    partition by p.oid
    order by t.ord
  ) as return_ordinal,
  t.argname                    as out_column,
  format_type(t.argtype, null) as out_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
  with ordinality as t(argtype, argmode, argname, ord)
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by return_ordinal;

-- C-4b. read RPC EXECUTE privileges + full ACL + PUBLIC EXECUTE absence.
--    Expected: can_execute = true for anon / authenticated / postgres / service_role.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
order by v.grantee;

--    Expected ACL: exactly the 4 grantees above with EXECUTE, is_grantable = false,
--      NO PUBLIC row, explicit (non-NULL) ACL.
--    STOP if a PUBLIC row appears or the ACL differs from the baseline.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable,
  (p.proacl is not null) as has_explicit_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
order by grantee, acl.privilege_type;

-- C-5. existing notices RPC baseline (5) -- attributes. This file does NOT alter them
--    (baseline for the P-8 "unchanged" comparison).
--    Expected: 5 rows, SECURITY DEFINER = true, volatility 'v' (VOLATILE), owner
--      postgres, fixed search_path. KNOWN: PUBLIC EXECUTE present (recorded baseline
--      only, NOT a stop condition, NOT modified here).
--    STOP only if an attribute OTHER than the known PUBLIC EXECUTE differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
order by p.proname, p.oid::regprocedure::text;

-- C-5b. existing notices RPC EXECUTE ACL baseline (5). KNOWN PUBLIC EXECUTE present.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- C-6. notices data baseline (INVARIANT, not reference-only): counts.
--    Record the counts. Last recorded (2026-07-16): total 4 / active 1 / inactive 3 /
--      null_active 0. This file performs NO DML, so P-6 must equal C-6. If C-6 itself
--      differs from the last recorded values, distinguish a legitimate data update
--      (a notice created / edited since 2026-07-16) from an anomaly BEFORE proceeding;
--      the C-6 value measured here becomes the invariant for P-6 and the smoke test.
select
  count(*)                                  as total,       -- expect 4
  count(*) filter (where is_active = true)  as active,      -- expect 1
  count(*) filter (where is_active = false) as inactive,    -- expect 3
  count(*) filter (where is_active is null) as null_active  -- expect 0
from public.notices;

-- C-7. front-end / repository preconditions (NOT checkable from SQL; confirmed from the
--    repo / production BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html / genka-app.html.
--    Documentation string hits inside docs (docs/db-migrations.md, docs/sql comments)
--    are EXCLUDED from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - notices direct read (`.from('notices')` / `.from("notices")`) = 0 in the
--      front-end application code (repo-confirmed; only docs hits remain).
--    - index.html loadNotice() references list_notices_secure (index.html:979).
--    - admin-app.html references list_notices_admin_secure (admin-app.html:1920).
--    - PR #130 merged; Vercel Production deployed.
--    - Production verified (employee screen): list_notices_secure POST 200;
--      NO /rest/v1/notices direct GET; notices render; no RPC-origin Console errors.


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-7 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction as the
--   body: if any expectation fails, it RAISEs, the transaction aborts, and NOTHING is
--   changed. This is what makes the file safe as a plain one-shot: a second run fails
--   the guard (SELECT already revoked / policy already dropped) before any statement
--   that would modify state.
--   DB-CHANGING statements are EXACTLY three: 2 x REVOKE SELECT + 1 x DROP POLICY.
--   No RPC / data / write privilege / table definition is touched.
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
begin
  -- G-1. notices exists with expected attributes (relkind r, RLS on, not forced,
  --      owner postgres).
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'notices'
    and c.relkind = 'r'
    and c.relrowsecurity = true
    and c.relforcerowsecurity = false
    and pg_get_userbyid(c.relowner) = 'postgres';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-1): notices missing or attributes differ (expected relkind r / RLS on / FORCE off / owner postgres)';
  end if;

  -- G-2. anon / authenticated still HAVE SELECT. If not, the revoke has (partially)
  --      run already, or the state diverged -> STOP; do not re-run.
  if not (    has_table_privilege('anon',          'public.notices', 'SELECT')
          and has_table_privilege('authenticated', 'public.notices', 'SELECT')) then
    raise exception 'GUARD STOP (G-2): anon/authenticated SELECT is already (partially) revoked on notices -- body may have run before; reconcile, do NOT re-run';
  end if;

  -- G-3. write-class privileges all false for anon / authenticated (this file must
  --      not run on top of an unexpected write grant).
  perform 1
  from (values ('anon'), ('authenticated')) as r(role_name)
  cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                     ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(priv)
  where has_table_privilege(r.role_name, 'public.notices', p.priv);
  if found then
    raise exception 'GUARD STOP (G-3): unexpected write-class table privilege for anon/authenticated on notices';
  end if;

  -- G-4. NO PUBLIC SELECT ACL on notices (a plain REVOKE FROM anon, authenticated
  --      would not close a PUBLIC grant). Also asserts no column-level ACL survives.
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
  where n.nspname = 'public'
    and c.relname = 'notices'
    and acl.privilege_type = 'SELECT'
    and acl.grantee = 0;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-4): PUBLIC SELECT ACL present on notices (% rows) -- REVOKE FROM anon, authenticated would not close it', v_cnt;
  end if;

  select count(*) into v_cnt
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'notices'
    and a.attnum > 0
    and not a.attisdropped
    and a.attacl is not null;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-4): column-level ACL present on notices (% columns) -- would survive a table-level REVOKE; reconcile first', v_cnt;
  end if;

  -- G-5. notices_read_all exists with the EXACT expected definition and is the ONLY
  --      policy on notices (SELECT policy count = 1 AND total policy count = 1). This
  --      is what prevents an "accidental success" if the policy name / state diverged.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'notices';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-5): notices total policy count = % (expected exactly 1: notices_read_all)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'notices'
    and policyname = 'notices_read_all'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'SELECT'
    and qual       = 'true'
    and with_check is null;
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-5): notices_read_all is missing or its definition differs from PERMISSIVE/{public}/SELECT/USING true';
  end if;

  -- G-6. list_notices_secure exists (the app depends on it after the revoke).
  if to_regprocedure('public.list_notices_secure(text)') is null then
    raise exception 'GUARD STOP (G-6): read RPC public.list_notices_secure(text) is missing';
  end if;

  raise notice 'GUARD OK: state matches the expected baseline; proceeding to REVOKE/DROP';
end
$guard$;

-- BODY (exactly 3 DB changes; no IF EXISTS -- unexpected absence must fail the whole
-- transaction, including the REVOKEs already applied above it)

REVOKE SELECT
ON TABLE public.notices
FROM anon;

REVOKE SELECT
ON TABLE public.notices
FROM authenticated;

DROP POLICY notices_read_all
ON public.notices;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. anon / authenticated table grants after the revoke.
--    Expected: all 8 privileges = false for BOTH roles (SELECT now revoked; the other
--      7 already false and unchanged from C-2).
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

-- P-1b. raw ACL + SELECT ACL after the revoke.
--    Raw table ACL expected:
--      {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}
--      (anon / authenticated rows gone; nothing else changed).
select
  c.relname as table_name,
  c.relacl  as raw_acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

--    aclexplode view -- Expected: 0 rows (no PUBLIC / anon / authenticated SELECT ACL
--      remains). service_role's SELECT (part of arwdDxtm) is out of scope and
--      intentionally not listed.
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'notices'
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by grantee;

-- P-1c. column-level (attribute) ACL after the revoke. Expected: 0 rows (unchanged).
select
  a.attname as column_name,
  a.attacl  as column_acl
from pg_attribute a
join pg_class c on c.oid = a.attrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices'
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by a.attnum;

-- P-2. policies after the drop.
--    Expected: 0 rows and policy_count = 0 -- notices_read_all is gone; no policy
--      remains (notices had no non-SELECT policy). notices_read_all row count = 0.
select
  policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
order by cmd, policyname;

select count(*) as policy_count                 -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'notices';

select count(*) as notices_read_all_count       -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
  and policyname = 'notices_read_all';

select count(*) as select_policy_count          -- expect 0 (mirror C-3)
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
  and cmd = 'SELECT';

-- P-3. table attributes UNCHANGED (mirror C-1).
--    Expected: rls_enabled = true, rls_forced = false, owner = postgres.
select
  c.relname                   as table_name,
  c.relkind                   as relkind,
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

-- P-6. notices data UNCHANGED from the C-6 baseline (INVARIANT).
--    Expected: identical counts to C-6 (total 4 / active 1 / inactive 3 / null 0; the
--      body performs no DML). Any difference is external write activity, not this
--      file -- investigate, do NOT assert a cause.
select
  count(*)                                  as total,
  count(*) filter (where is_active = true)  as active,
  count(*) filter (where is_active = false) as inactive,
  count(*) filter (where is_active is null) as null_active
from public.notices;

-- P-7. list_notices_secure UNCHANGED (attributes + return type + EXECUTE / ACL +
--    PUBLIC EXECUTE absence) from C-4 / C-4b.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as is_security_definer,   -- expect true
  p.provolatile                             as volatility,            -- expect 's'
  pg_get_userbyid(p.proowner)               as owner,                 -- expect postgres
  p.proconfig                               as config,
  pg_get_function_identity_arguments(p.oid) as identity_arguments     -- expect session_token_input text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_notices_secure';

select
  p.proname,
  row_number() over (
    partition by p.oid
    order by t.ord
  ) as return_ordinal,
  t.argname                    as out_column,
  format_type(t.argtype, null) as out_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
  with ordinality as t(argtype, argmode, argname, ord)
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
  and t.argmode = 't'
order by return_ordinal;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable,
  (p.proacl is not null) as has_explicit_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
order by grantee, acl.privilege_type;

--    PUBLIC EXECUTE absence (machine check). Expected: 0 rows.
select count(*) as public_execute_count         -- expect 0
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE';

-- P-8. existing notices RPC baseline (5) attributes UNCHANGED (mirror C-5). KNOWN
--    PUBLIC EXECUTE remains as-is (NOT modified by this file).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
order by p.proname, p.oid::regprocedure::text;

-- P-9. existing notices RPC EXECUTE ACL UNCHANGED (mirror C-5b). KNOWN PUBLIC EXECUTE
--    on the 5 RPCs remains as-is.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;


-- ============================================================
-- SMOKE TEST (manual; performed by the USER AFTER the body + post-check.
--   Reload / re-login first so no cached data masks a failure. Do NOT record any real
--   session token. Do NOT run the create / update / attachment / delete notice RPCs --
--   the admin check is READ-ONLY, confirming the list only.)
-- ============================================================

-- (a) EMPLOYEE screen (index.html), employee session:
--     - Login succeeds.
--     - The active notice renders (count = C-6 active = 1).
--     - Network: list_notices_secure POST = 200; NO /rest/v1/notices direct GET.
--     - Console: no errors (incl. 'list_notices_secure failed:').

-- (b) ADMIN screen (admin-app.html), management session -- READ-ONLY:
--     - Admin login succeeds.
--     - The notices list renders (admin RPC returns all notices, not just active;
--       cross-check against C-6 total = 4 by eye -- do NOT run a mutating RPC to count).
--     - Network: list_notices_admin_secure = 200; NO /rest/v1/notices direct GET.
--     - Do NOT invoke create_notice_secure / update_notice_secure /
--       update_notice_attachment_secure / delete_notice_attachment_secure in this
--       smoke test (they mutate data). Only confirm the list is shown.

-- (b2) genka-app.html: intentionally NOT part of this smoke test -- genka-app.html does
--     NOT read public.notices (confirmed in the C-7 front-end precondition), so the
--     revoke has no path to affect it. Listed here only to record the deliberate omission.

-- (c) PERMISSION negative test -- direct SELECT must be rejected, RPC read must work.
--     Do NOT paste any real token.
--     - Roles-only check in the SQL Editor (no app token involved):
--         select has_table_privilege('anon',          'public.notices', 'SELECT');  -- expect false
--         select has_table_privilege('authenticated', 'public.notices', 'SELECT');  -- expect false
--     - From a logged-in employee app session (browser Console, anon key context):
--         // const r = await sb.from('notices').select('id').limit(1);
--         // console.log(r.error);   // expect a permission-denied error object, data = null
--     - Positive RPC read still works (replace <...> at run time; never save a token):
--         // const t = state.currentUser.session_token;
--         // console.log((await sb.rpc('list_notices_secure',{session_token_input:t})).data?.length);
--         --   expect = C-6 active count (1)
--     - RPC still rejects an invalid / expired session (unchanged by the revoke -- the
--       RPCs verify the session INLINE, independent of the table grant). Run in the SQL
--       Editor with a bogus token; expect SQLSTATE P0001 'Invalid or expired session',
--       no rows:
--         select * from public.list_notices_secure('smoke-invalid-token');
--         select * from public.list_notices_admin_secure('smoke-invalid-token');


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; requires SEPARATE explicit approval;
--   do NOT run in the same session immediately after the body)
--   Restores the two direct SELECT grants and re-creates notices_read_all exactly as
--   recorded in the C-3 pre-check (PERMISSIVE / FOR SELECT / TO public / USING (true)).
--   WARNING: this RE-WEAKENS security by RE-OPENING the anon / authenticated direct
--   read of public.notices (a broad, unauthenticated-shape read path). Use it ONLY for
--   emergency recovery. Normally unnecessary because index.html is already on
--   list_notices_secure and admin-app.html is on list_notices_admin_secure.
--   Re-confirm the current state (C-1..C-3) before using this. Runs as ONE transaction.
--   NOT executed.
-- ============================================================
-- BEGIN;
--
-- GRANT SELECT
-- ON TABLE public.notices
-- TO anon, authenticated;
--
-- CREATE POLICY notices_read_all
-- ON public.notices
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- COMMIT;
-- ============================================================
