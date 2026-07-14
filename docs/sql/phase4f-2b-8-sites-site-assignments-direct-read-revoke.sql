-- ============================================================
-- Phase 4-F-2B-8: sites / site_assignments direct read revoke (final privilege cleanup)
--   Remove the residual direct SELECT grants on public.sites and
--   public.site_assignments for anon / authenticated, and drop the now-unnecessary
--   sites_read_all / sa_read policies, after the front-end (index.html /
--   admin-app.html / genka-app.html) has been migrated to the five sites /
--   site_assignments read RPCs (list_sites_secure / list_site_assignments_secure /
--   list_sites_admin_secure / get_site_admin_secure /
--   list_site_assignments_admin_secure).
--   The two tables are handled TOGETHER in ONE transaction on purpose: the former
--   admin-app.html pageSites embedded JOIN (sites -> site_assignments) means a
--   partial revoke of either table alone was never a valid intermediate state.
-- ============================================================
-- [STATUS] EXECUTED 2026-07-14
--   - This file removes exactly TWO privileges (SELECT for anon / authenticated on
--     public.sites and public.site_assignments) and drops exactly TWO policies
--     (sites_read_all / sa_read). Nothing else was touched.
--   - DB execution was done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performed NO DB connection / NO SQL execution / NO Supabase
--     CLI / NO psql. All pre-check / guard / body / post-check / smoke were run by
--     the user.
--   - Run order was: PRE-CHECK (C-1..C-9) -> EXECUTION BODY (single transaction:
--     read-only GUARD G-1..G-9 + 2 REVOKE + 2 DROP POLICY) -> post-execution
--     verification (the actually re-verified items are listed in [POST-CHECK
--     RESULT]) -- all of the above in the Supabase SQL Editor -> negative /
--     positive RPC smoke and production path checks (production Browser DevTools
--     Console). ROLLBACK not used.
--   - This step came AFTER the front-end migration (PR #125 merged, production
--     commit e12ffca) and AFTER the production browser smoke passed on all three
--     screens (see [FRONT-END PRECONDITIONS] / C-9).
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-14)
--     - The user ran the EXECUTION BODY manually ONCE (single transaction,
--       BEGIN .. GUARD DO block .. 2 x REVOKE SELECT .. 2 x DROP POLICY .. COMMIT).
--       Result: Success. No rows returned. The BODY was NOT re-run afterwards and
--       must NOT be re-run (the guard fails closed on a second run).
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--
--   [PRE-CHECK / GUARD RESULT] (C-1..C-9 + G-1..G-9, 2026-07-14 -- all passed)
--     - C-1: both tables relkind 'r', RLS true, FORCE RLS false, owner postgres.
--     - C-2 / C-2b: anon / authenticated SELECT = true, other 7 privileges false
--       (both tables); ACL anon + authenticated SELECT only, is_grantable = false,
--       NO PUBLIC SELECT ACL.
--     - C-3: exactly 6 policies (3 per table); read = sites_read_all / sa_read only;
--       the 4 kept write policies matched the real-DB baseline
--       (anon_can_insert_sites PERMISSIVE/{anon}/INSERT/qual null/with_check true;
--        anon_can_update_sites PERMISSIVE/{anon}/UPDATE/qual true/with_check true;
--        sa_write PERMISSIVE/{public}/INSERT/qual null/with_check true;
--        sa_update PERMISSIVE/{public}/UPDATE/qual true/with_check null).
--     - C-4 / C-4b: all 5 read RPCs present with designed signatures / return types;
--       SECURITY DEFINER, STABLE, owner postgres, fixed search_path; EXECUTE for
--       anon / authenticated / postgres / service_role; no PUBLIC EXECUTE.
--     - C-5 / C-6 / C-7: write RPCs (5), sites-internal read RPCs (4) and
--       _verify_management_session matched the recorded baseline (KNOWN PUBLIC
--       EXECUTE left as-is).
--     - C-8: sites total 20 / active 10 / inactive 10 / null 0; site_assignments
--       total 30 / active 12 / inactive 18 / null 0. NOTE: site_assignments grew
--       from the read-rpc-step record (29/11/18) by one active assignment -- a
--       legitimate data update between the steps, adopted as the invariant for
--       P-5 and the smoke expectations per this file's baseline rule. Integrity:
--       all 5 checks = 0.
--     - C-9: front-end preconditions confirmed (direct read 0 on all three screens,
--       PR #125 / e12ffca, production smoke passed).
--     - GUARD G-1..G-9: all passed inside the body transaction (GUARD OK).
--
--   [POST-CHECK RESULT] (Supabase SQL Editor, 2026-07-14. The items below are the
--     ones ACTUALLY re-verified after the body; no blanket "all P-* passed" claim
--     is made beyond them.)
--     - anon / authenticated table privileges: all 8 false on BOTH tables (SELECT
--       now revoked).
--     - raw table ACL: {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}
--       (both tables); no anon / authenticated / PUBLIC SELECT ACL.
--     - policies on the two TARGET tables: sites_read_all / sa_read = 0 rows; the
--       4 kept write policies remain (sites 2 / site_assignments 2) with
--       definitions matching the C-3 baseline. Policies OUTSIDE the two target
--       tables were NOT re-queried after the body; the body's only policy DDL was
--       the two DROPs above, so no other policy was subject to change by scope.
--     - RLS true / FORCE RLS false / owner postgres (both tables).
--     - columns: sites 10 cols / site_assignments 5 cols, names / types unchanged.
--     - constraints: unchanged, all convalidated = true.
--     - indexes: the 4 index names / definitions were re-checked via pg_indexes
--       (sites_pkey, idx_sites_category_id, site_assignments_pkey,
--       site_assignments_site_id_employee_id_key) and match the pre-execution
--       baseline. indisvalid / indisready were NOT re-queried after the body.
--     - counts: equal C-8 (sites 20/10/10/0; site_assignments 30/12/18/0);
--       integrity all 5 checks = 0 (the body made no data change).
--     - read RPCs (5): attributes (SECURITY DEFINER / STABLE / owner postgres /
--       fixed search_path) and EXECUTE ACL re-verified, unchanged, no PUBLIC
--       EXECUTE. Return types were verified in the PRE-CHECK baseline (C-4) and
--       were NOT re-queried after the body; the body contains no FUNCTION DDL, so
--       they were not subject to change.
--     - write RPCs (5), sites-internal read RPCs (4) and _verify_management_session:
--       attributes + EXECUTE ACL re-verified, unchanged (KNOWN PUBLIC EXECUTE
--       as-is).
--
--   [SMOKE TEST RESULT] (2026-07-14; no real session token recorded)
--     - NEGATIVE direct read (anon-key REST context): sites direct GET -> 401 /
--       42501 (permission denied); site_assignments direct GET -> 401 / 42501;
--       embedded JOIN (sites -> site_assignments) -> 401 / 42501.
--     - POSITIVE RPC (valid sessions): list_sites_secure = 10 rows;
--       list_site_assignments_secure = 12 rows; list_sites_admin_secure = 10 rows
--       with sum(active_assignment_count) = 12; get_site_admin_secure = 1 row for
--       an existing id; list_site_assignments_admin_secure = 4 rows for a site
--       whose expected active assignment count is 4 (match; all values equal the
--       C-8 invariant).
--     - PRODUCTION path check (all three screens): employee / admin / genka screens
--       use the secure read RPCs only; /rest/v1/sites and /rest/v1/site_assignments
--       direct GET = 0.
--
--   [OUTCOME]
--     - anon / authenticated SELECT on public.sites / public.site_assignments:
--       revoked (both tables, same transaction).
--     - sites_read_all / sa_read policies: dropped. Kept write policies (4):
--       unchanged.
--     - read RPC 5 / write RPC 5 / sites-internal read RPC 4 /
--       _verify_management_session: kept; attributes + EXECUTE ACL re-verified
--       unchanged (read RPC return types: pre-check baseline only, no FUNCTION DDL
--       in the body).
--     - RLS / FORCE RLS / owner / columns / constraints: unchanged; the 4 index
--       names / definitions match the pre-execution baseline.
--       data: unchanged by the body (site_assignments baseline growth to 30/12
--       predates the body -- see C-8 note).
--     - sites / site_assignments reads are now unified through the secure read
--       RPCs; Phase 4-F-2B-8 sites / site_assignments read protection
--       (read RPC -> front-end migration -> direct read shutdown) is COMPLETE.
--     - ROLLBACK: NOT executed (kept as commented reference only).
--
-- [PURPOSE]
--   - The sites / site_assignments read paths have been fully migrated to secure
--     read RPCs (front-end PR #125, merge commit e12ffca, production smoke passed
--     2026-07-14):
--       index.html      loadSites            -> list_sites_secure
--       index.html      loadSiteAssignments  -> list_site_assignments_secure
--       admin-app.html  startApp / pageSites -> list_sites_admin_secure
--       admin-app.html  openSiteModal        -> get_site_admin_secure
--                                             + list_site_assignments_admin_secure
--       genka-app.html  startApp             -> list_sites_admin_secure
--   - Remove the direct SELECT grants held by anon / authenticated on public.sites
--     and public.site_assignments (no longer used by the app; the five read RPCs are
--     SECURITY DEFINER and do not depend on these grants).
--   - Drop the sites_read_all / sa_read policies, which become unnecessary once the
--     direct SELECT grants are removed. The write policies (anon_can_insert_sites /
--     anon_can_update_sites / sa_write / sa_update) are KEPT unchanged.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo / production BEFORE this file;
--   SQL cannot check these -- recorded here as confirmed facts; re-stated in C-9)
--   - PR #125 merged (Merge commit e12ffca); Vercel Production deployed.
--   - sites / site_assignments direct read (`.from('sites')` / `.from("sites")` /
--     `.from('site_assignments')` / `.from("site_assignments")`) = 0 in the
--     front-end application code (index.html / admin-app.html / genka-app.html),
--     including the former admin-app.html pageSites embedded JOIN
--     (site_assignments(...) inside a sites select). Documentation string hits
--     inside docs/sql (this file's comments / search examples) are EXCLUDED.
--   - Production browser smoke passed on all three screens (2026-07-14):
--       employee (index.html): list_sites_secure = 200,
--         list_site_assignments_secure = 200; NO /rest/v1/sites or
--         /rest/v1/site_assignments direct GET; no app Console errors.
--       admin (admin-app.html): list_sites_admin_secure / get_site_admin_secure /
--         list_site_assignments_admin_secure = 200; NO direct GET; no app Console
--         errors; site list / assignment counts / edit modal / assignment checkboxes
--         match previous values.
--       cost (genka-app.html): list_sites_admin_secure = 200; site select / period /
--         address / cost display normal; NO direct GET; no app Console errors.
--   - The five read RPCs exist in production
--     (phase4f-2b-8-sites-site-assignments-read-rpc.sql EXECUTED 2026-07-14).
--
-- [SCOPE] (EXACTLY four DB changes -- nothing else)
--   - REVOKE SELECT ON public.sites            FROM anon, authenticated.
--   - REVOKE SELECT ON public.site_assignments FROM anon, authenticated.
--   - DROP POLICY sites_read_all ON public.sites.
--   - DROP POLICY sa_read        ON public.site_assignments.
--
-- [NON-SCOPE] (intentionally NOT touched here -- this file is a privilege cleanup
--   ONLY; it changes NO RPC, NO data, NO write protection, NO table definition)
--   - sites / site_assignments data (no DML; counts / active breakdown / integrity
--     must be unchanged -- see C-8 / P-5). Last recorded baseline: sites total 20 /
--     active 10 / inactive 10; site_assignments total 29 / active 11 / inactive 18.
--   - write policies: anon_can_insert_sites / anon_can_update_sites (sites),
--     sa_write / sa_update (site_assignments) -- KEPT, unchanged (C-3 / P-2).
--   - INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN table
--     privileges for anon / authenticated (already false; must stay false).
--   - RLS enabled state / FORCE RLS / owner / columns / constraints / indexes.
--   - the five read RPCs (list_sites_secure / list_site_assignments_secure /
--     list_sites_admin_secure / get_site_admin_secure /
--     list_site_assignments_admin_secure) and their EXECUTE grants / ACL
--     (unchanged -- C-4 / P-6).
--   - the five existing write RPCs (create_site_secure / update_site_secure /
--     deactivate_site_secure / set_site_assignment_secure /
--     replace_site_assignments_secure) -- reused / unaffected, NOT modified
--     (C-5 / P-7). Their KNOWN PUBLIC EXECUTE is baseline, out of scope here.
--   - the four sites-internal read RPCs (export_projects_summary_secure /
--     create_invoice_secure / update_invoice_secure /
--     create_machine_location_secure) -- they read sites as SECURITY DEFINER and are
--     unaffected by this revoke; NOT modified (C-6 / P-8). KNOWN PUBLIC EXECUTE on
--     create_invoice_secure / update_invoice_secure is baseline, out of scope here.
--   - public._verify_management_session(text) (reused as-is; NOT modified --
--     C-7 / P-8).
--   - postgres / service_role / any other role's privileges.
--   - front-end code.
--   - other tables / other policies / other routines.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
-- [RE-RUN SAFETY] (plain one-shot design)
--   - The EXECUTION BODY is ONE transaction (BEGIN..COMMIT) whose first statement is
--     a read-only GUARD (DO block). The guard RAISEs if the DB is not in the exact
--     expected pre-state -- including the "already revoked / already dropped" case --
--     so a second run aborts the transaction BEFORE any change is attempted.
--   - DROP POLICY is used WITHOUT "IF EXISTS" on purpose: if sites_read_all or
--     sa_read is unexpectedly absent, the statement errors, the transaction aborts,
--     and both REVOKEs are rolled back as well (nothing is half-applied; state
--     divergence is surfaced, not hidden).
--   - Do NOT re-run the body after it has succeeded. Re-opening the direct read
--     requires the explicit ROLLBACK reference at the end (emergency only).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop &
--   report -- do NOT guess or "fix" divergence. The GUARD re-asserts the machine-
--   checkable subset and aborts the transaction if violated.)
--   - C-1: sites or site_assignments missing, relkind <> 'r', RLS <> true,
--          FORCE RLS <> false, or owner <> postgres.
--   - C-2: anon or authenticated SELECT is already false on either table (the revoke
--          may already be applied; STOP and reconcile), or any of the 7 write-class
--          privileges is true.
--   - C-2b: a PUBLIC SELECT ACL exists on either table (a plain REVOKE FROM anon,
--          authenticated would NOT close a PUBLIC grant), or the direct
--          anon / authenticated SELECT ACL is missing while C-2 effective SELECT =
--          true (grant source unexpected).
--   - C-3: sites_read_all or sa_read is missing or its definition differs
--          (PERMISSIVE / roles {public} / cmd SELECT / qual true / with_check null);
--          any additional SELECT policy exists on either table; any of the four
--          write policies (anon_can_insert_sites / anon_can_update_sites / sa_write /
--          sa_update) is missing; or total policy counts differ (sites 3 /
--          site_assignments 3).
--   - C-4: any of the five read RPCs is missing, not SECURITY DEFINER, not STABLE,
--          owner not postgres, search_path not fixed, signature or return type
--          differs, EXECUTE differs (anon / authenticated / postgres / service_role
--          = true), or a PUBLIC EXECUTE is present on any of them.
--   - C-5 / C-6 / C-7: a write RPC, a sites-internal read RPC, or
--          _verify_management_session is missing or differs from the recorded
--          baseline in a way OTHER than the KNOWN PUBLIC EXECUTE noted there.
--   - C-8: any integrity check is non-zero, or counts changed in an unexpected way
--          (record as the P-5 invariant; if it differs, investigate first -- this
--          file performs NO DML; do NOT assert a cause).
--   - C-9: any front-end / repository precondition is NOT satisfied (e.g. a sites or
--          site_assignments direct read reappears in the front-end application code).
--   - The body would change any RPC / data / write protection / any object beyond
--          the four SCOPE operations -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Restores the two direct SELECT grants and re-creates sites_read_all / sa_read
--   exactly as recorded in C-3 (PERMISSIVE / FOR SELECT / TO public / USING (true)).
--   Limited to exactly the four changes of this file. It RE-WEAKENS security
--   (re-opens the direct reads), so use it ONLY for emergency recovery; normally
--   unnecessary because all three screens are already on the read RPCs.
--   NOT executed.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body. Any STOP condition -> stop.
-- ============================================================

-- C-1. sites / site_assignments table attributes.
--    Expected: 2 rows, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres (both). STOP if a table is missing or anything differs.
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
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- C-2. anon / authenticated table grants (both tables, all 8 privileges).
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false, for both roles on both tables.
--    STOP if SELECT is already false anywhere, or if any of the other 7 is true.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this project
--      runs PG 17.x). If this query errors on MAINTAIN on an older server, re-run it
--      without the can_maintain column -- do NOT skip the other columns.
select
  v.tbl,
  v.role_name,
  has_table_privilege(v.role_name, v.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, v.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, v.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, v.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, v.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, v.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, v.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, v.tbl, 'MAINTAIN')   as can_maintain
from (
  select tbl, role_name
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
) as v(tbl, role_name)
order by v.tbl, v.role_name;

-- C-2b. raw ACL + SELECT ACL (grant source), so the REVOKEs reliably close the reads.
--    Raw table ACL expected (both tables):
--      {postgres=arwdDxtm/postgres,anon=r/postgres,authenticated=r/postgres,
--       service_role=arwdDxtm/postgres}.
select
  c.relname as table_name,
  c.relacl  as raw_acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

--    aclexplode view -- expected per table: exactly one direct SELECT ACL for anon
--      and one for authenticated; is_grantable = false; NO PUBLIC SELECT ACL.
--    STOP if a PUBLIC SELECT ACL exists (a plain REVOKE FROM anon, authenticated
--      would NOT close a PUBLIC grant), or if the direct anon / authenticated SELECT
--      ACL is missing while C-2 effective SELECT = true (grant source unexpected --
--      reconcile before running the body).
--    NOTE: service_role keeps its SELECT (part of arwdDxtm) and is out of scope;
--      this query intentionally filters to PUBLIC / anon / authenticated only.
select
  c.relname as table_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by c.relname, grantee;

-- C-3. all policies on both tables -- full definition (also the ROLLBACK source).
--    Expected: EXACTLY 6 rows (3 per table):
--      sites:
--        sites_read_all        : PERMISSIVE, roles {public}, cmd SELECT,
--                                qual true, with_check null   <- DROPPED by the body
--        anon_can_insert_sites : cmd INSERT                    <- KEPT
--        anon_can_update_sites : cmd UPDATE                    <- KEPT
--      site_assignments:
--        sa_read               : PERMISSIVE, roles {public}, cmd SELECT,
--                                qual true, with_check null   <- DROPPED by the body
--        sa_write              : cmd INSERT                    <- KEPT
--        sa_update             : cmd UPDATE                    <- KEPT
--    STOP if sites_read_all / sa_read is missing or differs, if any ADDITIONAL
--    SELECT policy exists, if any of the four write policies is missing, or if the
--    per-table policy counts differ from 3 / 3.
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

select tablename, count(*) as policy_count      -- expect sites = 3, site_assignments = 3
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
group by tablename
order by tablename;

select tablename, count(*) as select_policy_count  -- expect 1 per table
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
  and cmd = 'SELECT'
group by tablename
order by tablename;

-- C-4. the five read RPCs (must KEEP working after the revoke).
--    Expected: 5 rows -- list_sites_secure(text) / list_site_assignments_secure(text)
--      / list_sites_admin_secure(text) / get_site_admin_secure(text, uuid) /
--      list_site_assignments_admin_secure(text, uuid) -- each SECURITY DEFINER =
--      true, volatility = 's' (STABLE), owner = postgres, config contains
--      search_path=public, extensions.
--    STOP if any is missing or any attribute differs.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as is_security_definer,   -- expect true
  p.provolatile                             as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner)               as owner,                 -- expect postgres
  p.proconfig                               as config,                -- expect search_path=public, extensions
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;

-- C-4 (return types). read RPC TABLE OUT columns.
--    Expected:
--      list_sites_secure: 1 id uuid, 2 name text, 3 company_id uuid, 4 location text,
--        5 start_date date, 6 end_date date.
--      list_site_assignments_secure: 1 site_id uuid, 2 employee_id uuid.
--      list_sites_admin_secure: 1 id uuid, 2 name text, 3 company_id uuid,
--        4 location text, 5 start_date date, 6 end_date date,
--        7 active_assignment_count bigint.
--      get_site_admin_secure: 1 id uuid, 2 name text, 3 company_id uuid,
--        4 location text, 5 start_date date, 6 end_date date.
--      list_site_assignments_admin_secure: 1 employee_id uuid.
--    STOP if any return type differs.
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
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by p.proname, return_ordinal;

-- C-4b. read RPC effective EXECUTE + explicit ACL + PUBLIC EXECUTE absence.
--    Expected (all five): can_execute = true for anon / authenticated / postgres /
--      service_role.
select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname, v.grantee;

--    Expected ACL (all five): exactly the 4 grantees above with EXECUTE,
--      is_grantable = false, NO PUBLIC row, explicit (non-NULL) ACL.
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
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname, grantee, acl.privilege_type;

-- C-5. existing write RPC baseline (5) -- attributes + EXECUTE ACL. This file does
--    NOT alter them (baseline for the P-7 "unchanged" comparison).
--    Expected: SECURITY DEFINER = true, volatility 'v', owner postgres, fixed
--      search_path. KNOWN: PUBLIC EXECUTE present (recorded baseline only, NOT a
--      stop condition, NOT modified here).
--    STOP only if an attribute other than the known PUBLIC EXECUTE differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- C-6. sites-internal read RPC baseline (4) -- attributes + EXECUTE ACL. These read
--    sites internally as SECURITY DEFINER and are unaffected by the revoke; this
--    file does NOT alter them (baseline for the P-8 "unchanged" comparison).
--    Expected: SECURITY DEFINER = true, owner postgres, fixed search_path. KNOWN:
--      create_invoice_secure / update_invoice_secure have PUBLIC EXECUTE (recorded
--      baseline only, NOT a stop condition, NOT modified here).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- C-7. _verify_management_session(text) attributes + EXECUTE ACL (reused by the
--    three admin read RPCs; NOT modified here).
--    Expected: 1 row, security_definer = true, volatility 'v', owner postgres,
--      config contains search_path=public, extensions, identity args
--      "session_token_input text", result TABLE(actor_type text, actor_id uuid).
--      ACL: EXECUTE for postgres / service_role only; NO PUBLIC / anon /
--      authenticated EXECUTE. STOP if attributes differ.
select
  p.oid::regprocedure::text                 as function_signature,
  p.prosecdef                               as security_definer,   -- expect true
  p.provolatile                             as volatility,         -- expect 'v'
  pg_get_userbyid(p.proowner)               as owner,              -- expect postgres
  p.proconfig                               as config,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_function_result(p.oid)             as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = '_verify_management_session'
order by grantee;

-- C-8. data baseline (INVARIANT, not reference-only): counts + integrity.
--    Record the counts. Last recorded (2026-07-14, read-rpc step): sites total 20 /
--      active 10 / inactive 10 / null 0; site_assignments total 29 / active 11 /
--      inactive 18 / null 0.
--    This file performs NO DML, so P-5 must equal C-8. If C-8 itself differs from
--    the last recorded values, distinguish legitimate data updates (site edits /
--    assignments since 2026-07-14) from an anomaly BEFORE proceeding; the C-8 value
--    measured here becomes the invariant for P-5 and the smoke-test row counts.
select 'sites' as table_name,
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.sites
union all
select 'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments;

--    Integrity (5 checks). Expected: every count = 0. STOP if any is non-zero.
select
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where s.id is null)                                                   as orphan_site_id,
  (select count(*) from public.site_assignments sa
     left join public.employees e on e.id = sa.employee_id
     where e.id is null)                                                   as orphan_employee_id,
  (select count(*) from (
     select site_id, employee_id
     from public.site_assignments
     group by site_id, employee_id
     having count(*) > 1) d)                                               as duplicate_assignment_groups,
  (select count(*) from public.site_assignments sa
     join public.sites s on s.id = sa.site_id
     where sa.is_active = true and s.is_active = false)                    as active_asg_on_inactive_site,
  (select count(*) from public.site_assignments sa
     join public.employees e on e.id = sa.employee_id
     where sa.is_active = true and e.is_active = false)                    as active_asg_on_inactive_employee;

-- C-9. front-end / repository preconditions (NOT checkable from SQL; confirmed from
--    the repo / production BEFORE running the body -- recorded here as facts).
--    "front-end application code" = index.html / admin-app.html / genka-app.html.
--    Documentation string hits inside docs/sql (this file's comments / search
--    examples) are EXCLUDED from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - sites / site_assignments direct read (`.from('sites')` / `.from("sites")` /
--      `.from('site_assignments')` / `.from("site_assignments")`) = 0 in the
--      front-end application code, including the former admin-app.html pageSites
--      embedded JOIN (repo-confirmed on merge commit e12ffca, 2026-07-14).
--    - index.html uses list_sites_secure / list_site_assignments_secure;
--      admin-app.html uses list_sites_admin_secure / get_site_admin_secure /
--      list_site_assignments_admin_secure; genka-app.html uses
--      list_sites_admin_secure.
--    - PR #125 merged (e12ffca); Vercel Production deployed.
--    - Production verified on all three screens (2026-07-14): the five read RPCs
--      return 200 on their screens; NO /rest/v1/sites or /rest/v1/site_assignments
--      direct GET; no app Console errors.


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-9 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction as the
--   body: if any expectation fails, it RAISEs, the transaction aborts, and NOTHING
--   is changed. This is what makes the file safe as a plain one-shot: a second run
--   fails the guard (SELECT already revoked / policy already dropped) before any
--   statement that would modify state.
--   DB-CHANGING statements are EXACTLY four: 2 x REVOKE SELECT + 2 x DROP POLICY.
--   No RPC / data / write privilege / table definition is touched.
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
begin
  -- G-1. both tables exist with expected attributes (relkind r, RLS on, not forced,
  --      owner postgres).
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('sites', 'site_assignments')
    and c.relkind = 'r'
    and c.relrowsecurity = true
    and c.relforcerowsecurity = false
    and pg_get_userbyid(c.relowner) = 'postgres';
  if v_cnt <> 2 then
    raise exception 'GUARD STOP (G-1): expected 2 tables (sites, site_assignments) with relkind r / RLS on / FORCE off / owner postgres, found %', v_cnt;
  end if;

  -- G-2. anon / authenticated still HAVE SELECT on both tables. If not, the revoke
  --      has (partially) run already, or the state diverged -> STOP; do not re-run.
  if not (    has_table_privilege('anon',          'public.sites',            'SELECT')
          and has_table_privilege('authenticated', 'public.sites',            'SELECT')
          and has_table_privilege('anon',          'public.site_assignments', 'SELECT')
          and has_table_privilege('authenticated', 'public.site_assignments', 'SELECT')) then
    raise exception 'GUARD STOP (G-2): anon/authenticated SELECT is already (partially) revoked on sites/site_assignments -- body may have run before; reconcile, do NOT re-run';
  end if;

  -- G-3. write-class privileges all false for anon / authenticated on both tables
  --      (this file must not run on top of an unexpected write grant).
  perform 1
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
  cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'),
                     ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(priv)
  where has_table_privilege(r.role_name, t.tbl, p.priv);
  if found then
    raise exception 'GUARD STOP (G-3): unexpected write-class table privilege for anon/authenticated on sites/site_assignments';
  end if;

  -- G-4. NO PUBLIC SELECT ACL on either table (a plain REVOKE FROM anon,
  --      authenticated would not close a PUBLIC grant).
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
  where n.nspname = 'public'
    and c.relname in ('sites', 'site_assignments')
    and acl.privilege_type = 'SELECT'
    and acl.grantee = 0;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-4): PUBLIC SELECT ACL present on sites/site_assignments (% rows) -- REVOKE FROM anon, authenticated would not close it', v_cnt;
  end if;

  -- G-5. sites_read_all exists with the EXACT expected definition and is the ONLY
  --      SELECT policy on sites.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites' and cmd = 'SELECT';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-5): sites SELECT policy count = % (expected exactly 1: sites_read_all)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites'
    and policyname = 'sites_read_all'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'SELECT'
    and qual       = 'true'
    and with_check is null;
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-5): sites_read_all is missing or its definition differs from PERMISSIVE/{public}/SELECT/USING true';
  end if;

  -- G-6. sa_read exists with the EXACT expected definition and is the ONLY SELECT
  --      policy on site_assignments.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments' and cmd = 'SELECT';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-6): site_assignments SELECT policy count = % (expected exactly 1: sa_read)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments'
    and policyname = 'sa_read'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'SELECT'
    and qual       = 'true'
    and with_check is null;
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-6): sa_read is missing or its definition differs from PERMISSIVE/{public}/SELECT/USING true';
  end if;

  -- G-7. the four KEPT write policies exist with EXACTLY the expected definitions
  --      (real-DB pg_policies baseline, measured 2026-07-14):
  --        sites.anon_can_insert_sites            : PERMISSIVE / {anon}   / INSERT /
  --                                                 qual null / with_check true
  --        sites.anon_can_update_sites            : PERMISSIVE / {anon}   / UPDATE /
  --                                                 qual true / with_check true
  --        site_assignments.sa_write              : PERMISSIVE / {public} / INSERT /
  --                                                 qual null / with_check true
  --        site_assignments.sa_update             : PERMISSIVE / {public} / UPDATE /
  --                                                 qual true / with_check null
  --      Two-step check per policy (same pattern as G-5/G-6): name count first
  --      (missing vs duplicated), then full-definition count (mismatch). Distinct
  --      error messages per failure mode.

  -- G-7a. sites.anon_can_insert_sites
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites'
    and policyname = 'anon_can_insert_sites';
  if v_cnt = 0 then
    raise exception 'GUARD STOP (G-7a): kept write policy sites.anon_can_insert_sites is MISSING';
  elsif v_cnt > 1 then
    raise exception 'GUARD STOP (G-7a): kept write policy sites.anon_can_insert_sites is DUPLICATED (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites'
    and policyname = 'anon_can_insert_sites'
    and permissive = 'PERMISSIVE'
    and roles      = '{anon}'::name[]
    and cmd        = 'INSERT'
    and qual       is null
    and with_check = 'true';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7a): sites.anon_can_insert_sites DEFINITION DIFFERS from baseline PERMISSIVE/{anon}/INSERT/qual null/with_check true';
  end if;

  -- G-7b. sites.anon_can_update_sites
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites'
    and policyname = 'anon_can_update_sites';
  if v_cnt = 0 then
    raise exception 'GUARD STOP (G-7b): kept write policy sites.anon_can_update_sites is MISSING';
  elsif v_cnt > 1 then
    raise exception 'GUARD STOP (G-7b): kept write policy sites.anon_can_update_sites is DUPLICATED (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'sites'
    and policyname = 'anon_can_update_sites'
    and permissive = 'PERMISSIVE'
    and roles      = '{anon}'::name[]
    and cmd        = 'UPDATE'
    and qual       = 'true'
    and with_check = 'true';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7b): sites.anon_can_update_sites DEFINITION DIFFERS from baseline PERMISSIVE/{anon}/UPDATE/qual true/with_check true';
  end if;

  -- G-7c. site_assignments.sa_write
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments'
    and policyname = 'sa_write';
  if v_cnt = 0 then
    raise exception 'GUARD STOP (G-7c): kept write policy site_assignments.sa_write is MISSING';
  elsif v_cnt > 1 then
    raise exception 'GUARD STOP (G-7c): kept write policy site_assignments.sa_write is DUPLICATED (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments'
    and policyname = 'sa_write'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'INSERT'
    and qual       is null
    and with_check = 'true';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7c): site_assignments.sa_write DEFINITION DIFFERS from baseline PERMISSIVE/{public}/INSERT/qual null/with_check true';
  end if;

  -- G-7d. site_assignments.sa_update
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments'
    and policyname = 'sa_update';
  if v_cnt = 0 then
    raise exception 'GUARD STOP (G-7d): kept write policy site_assignments.sa_update is MISSING';
  elsif v_cnt > 1 then
    raise exception 'GUARD STOP (G-7d): kept write policy site_assignments.sa_update is DUPLICATED (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename = 'site_assignments'
    and policyname = 'sa_update'
    and permissive = 'PERMISSIVE'
    and roles      = '{public}'::name[]
    and cmd        = 'UPDATE'
    and qual       = 'true'
    and with_check is null;
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-7d): site_assignments.sa_update DEFINITION DIFFERS from baseline PERMISSIVE/{public}/UPDATE/qual true/with_check null';
  end if;

  -- G-8. total policy counts are exactly 3 + 3 (no unexpected extra policy that this
  --      file would silently leave behind or that signals divergence).
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public' and tablename in ('sites', 'site_assignments');
  if v_cnt <> 6 then
    raise exception 'GUARD STOP (G-8): total policy count on sites+site_assignments = % (expected 6)', v_cnt;
  end if;

  -- G-9. all five read RPCs exist (the app depends on them after the revoke).
  if    to_regprocedure('public.list_sites_secure(text)')                        is null
     or to_regprocedure('public.list_site_assignments_secure(text)')             is null
     or to_regprocedure('public.list_sites_admin_secure(text)')                  is null
     or to_regprocedure('public.get_site_admin_secure(text, uuid)')              is null
     or to_regprocedure('public.list_site_assignments_admin_secure(text, uuid)') is null then
    raise exception 'GUARD STOP (G-9): one or more of the 5 sites/site_assignments read RPCs is missing';
  end if;

  raise notice 'GUARD OK: state matches the expected baseline; proceeding to REVOKE/DROP';
end
$guard$;

-- BODY (exactly 4 DB changes; no IF EXISTS -- unexpected absence must fail the
-- whole transaction, including the REVOKEs already applied above it)

REVOKE SELECT
ON TABLE public.sites
FROM anon, authenticated;

REVOKE SELECT
ON TABLE public.site_assignments
FROM anon, authenticated;

DROP POLICY sites_read_all
ON public.sites;

DROP POLICY sa_read
ON public.site_assignments;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. anon / authenticated table grants after the revoke.
--    Expected: all 8 privileges = false for BOTH roles on BOTH tables (SELECT now
--      revoked; the other 7 already false and unchanged from C-2).
select
  v.tbl,
  v.role_name,
  has_table_privilege(v.role_name, v.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, v.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, v.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, v.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, v.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, v.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, v.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, v.tbl, 'MAINTAIN')   as can_maintain
from (
  select tbl, role_name
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
) as v(tbl, role_name)
order by v.tbl, v.role_name;

-- P-1b. raw ACL + SELECT ACL after the revoke.
--    Raw table ACL expected (both tables):
--      {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}
--      (anon / authenticated rows gone; nothing else changed).
select
  c.relname as table_name,
  c.relacl  as raw_acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

--    aclexplode view -- Expected: 0 rows (no PUBLIC / anon / authenticated SELECT
--      ACL remains on either table). service_role's SELECT (part of arwdDxtm) is out
--      of scope and intentionally not listed.
select
  c.relname as table_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and acl.privilege_type = 'SELECT'
  and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'))
order by c.relname, grantee;

-- P-2. policies after the drop.
--    Expected: EXACTLY 4 rows -- the kept write policies, unchanged from C-3:
--      sites: anon_can_insert_sites (INSERT), anon_can_update_sites (UPDATE);
--      site_assignments: sa_write (INSERT), sa_update (UPDATE).
--      sites_read_all / sa_read = 0 rows; SELECT policy count = 0 on both tables.
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

select count(*) as dropped_read_policy_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
  and policyname in ('sites_read_all', 'sa_read');

select tablename, count(*) as policy_count      -- expect sites = 2, site_assignments = 2
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
group by tablename
order by tablename;

-- P-3. table attributes UNCHANGED (mirror C-1).
--    Expected: rls_enabled = true, rls_forced = false, owner = postgres (both).
select
  c.relname                   as table_name,
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- P-4. columns / constraints / indexes UNCHANGED (this file touches no table
--    definition; compare with the recorded baseline of the read-rpc step).
--    Expected columns: sites 10 (id/name/is_active/created_at/start_date/end_date/
--      location/company_id/category_id/contract_amount);
--      site_assignments 5 (id/site_id/employee_id/is_active/assigned_at).
select
  c.relname                            as table_name,
  a.attname                            as column_name,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and a.attnum > 0
  and not a.attisdropped
order by c.relname, a.attnum;

--    Expected constraints: PKs, FKs (sites->companies/site_categories;
--      site_assignments->sites/employees), UNIQUE(site_id, employee_id); all
--      convalidated = true.
select
  rel.relname                     as table_name,
  con.conname                     as constraint_name,
  con.contype                     as type,
  con.convalidated                as validated,     -- expected true
  pg_get_constraintdef(con.oid)   as definition
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname in ('sites', 'site_assignments')
order by rel.relname, con.contype, con.conname;

--    Expected indexes: all indisvalid = true, indisready = true.
select
  rel.relname    as table_name,
  idx.relname    as index_name,
  i.indisvalid   as is_valid,    -- expected true
  i.indisready   as is_ready,    -- expected true
  i.indisunique  as is_unique,
  i.indisprimary as is_primary
from pg_index i
join pg_class rel on rel.oid = i.indrelid
join pg_class idx on idx.oid = i.indexrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname in ('sites', 'site_assignments')
order by rel.relname, idx.relname;

-- P-5. data UNCHANGED from the C-8 baseline (INVARIANT).
--    Expected: identical counts to C-8 (the body performs no DML). Any difference
--      is external write activity, not this file -- investigate, do NOT assert a
--      cause. Integrity checks must all still be 0.
select 'sites' as table_name,
  count(*)                                    as total,
  count(*) filter (where is_active = true)    as active,
  count(*) filter (where is_active = false)   as inactive,
  count(*) filter (where is_active is null)   as null_active
from public.sites
union all
select 'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments;

select
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where s.id is null)                                                   as orphan_site_id,
  (select count(*) from public.site_assignments sa
     left join public.employees e on e.id = sa.employee_id
     where e.id is null)                                                   as orphan_employee_id,
  (select count(*) from (
     select site_id, employee_id
     from public.site_assignments
     group by site_id, employee_id
     having count(*) > 1) d)                                               as duplicate_assignment_groups,
  (select count(*) from public.site_assignments sa
     join public.sites s on s.id = sa.site_id
     where sa.is_active = true and s.is_active = false)                    as active_asg_on_inactive_site,
  (select count(*) from public.site_assignments sa
     join public.employees e on e.id = sa.employee_id
     where sa.is_active = true and e.is_active = false)                    as active_asg_on_inactive_employee;

-- P-6. the five read RPCs UNCHANGED (mirror C-4 / C-4b): attributes, return types,
--    effective EXECUTE, explicit ACL, no PUBLIC EXECUTE.
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
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;

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
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
  and t.argmode = 't'
order by p.proname, return_ordinal;

select
  p.proname,
  v.grantee,
  has_function_privilege(v.grantee, p.oid, 'EXECUTE') as can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (values ('anon'), ('authenticated'), ('postgres'), ('service_role')) as v(grantee)
where n.nspname = 'public'
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname, v.grantee;

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
  and p.proname in ('list_sites_secure', 'list_site_assignments_secure',
                    'list_sites_admin_secure', 'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname, grantee, acl.privilege_type;

-- P-7. the five write RPCs UNCHANGED (mirror C-5). KNOWN PUBLIC EXECUTE remains
--    as-is (NOT modified by this file).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_site_secure', 'update_site_secure', 'deactivate_site_secure',
                    'set_site_assignment_secure', 'replace_site_assignments_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- P-8. sites-internal read RPCs (4) + _verify_management_session UNCHANGED (mirror
--    C-6 / C-7). KNOWN PUBLIC EXECUTE on create_invoice_secure /
--    update_invoice_secure remains as-is.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure',
                    '_verify_management_session')
order by p.proname, p.oid::regprocedure::text;

select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure', 'create_invoice_secure',
                    'update_invoice_secure', 'create_machine_location_secure',
                    '_verify_management_session')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- P-9. no policy / grant outside the two target tables changed. Sanity list of ALL
--    public-schema policies -- compare against the pre-execution inventory; only
--    sites_read_all / sa_read may have disappeared.
select
  tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- P-10 / P-11: see the SMOKE TEST sections below (browser + SQL Editor; performed
--    by the user AFTER the body + post-check).


-- ============================================================
-- NEGATIVE DIRECT-READ SMOKE (performed by the user AFTER the body + post-check)
--   Confirms that anon / authenticated REST direct reads on sites /
--   site_assignments are now rejected.
--   IMPORTANT: do NOT confuse role contexts --
--     - The Supabase SQL Editor runs as postgres (table owner): SELECT there still
--       works and proves NOTHING about the revoke.
--     - service_role also keeps SELECT (part of arwdDxtm) by design.
--     - Only the anon / authenticated (browser REST / anon key) path must fail.
--
--   (a) Browser Console, in a logged-in app session (anon key context):
--       const r1 = await sb.from('sites').select('id').limit(1);
--       console.log(r1.error);          // expected: permission-denied error, data null
--       const r2 = await sb.from('site_assignments').select('site_id').limit(1);
--       console.log(r2.error);          // expected: permission-denied error, data null
--       // Also confirm the embedded JOIN path stays closed:
--       const r3 = await sb.from('sites').select('id,site_assignments(employee_id)').limit(1);
--       console.log(r3.error);          // expected: permission-denied error
--       Expected error: code '42501' (permission denied) via PostgREST
--       (HTTP 401/403-class response); data = null in all three cases.
--
--   (b) SQL Editor equivalent (role check only; no app token involved):
--       select has_table_privilege('anon',          'public.sites',            'SELECT'); -- false
--       select has_table_privilege('authenticated', 'public.sites',            'SELECT'); -- false
--       select has_table_privilege('anon',          'public.site_assignments', 'SELECT'); -- false
--       select has_table_privilege('authenticated', 'public.site_assignments', 'SELECT'); -- false
--
--   (c) Network tab, all three screens after reload / re-login: NO
--       /rest/v1/sites or /rest/v1/site_assignments direct GET occurs at all (the
--       app no longer issues them); the five read RPC calls return 200.
-- ============================================================


-- ============================================================
-- POSITIVE RPC SMOKE (performed by the user AFTER the body + post-check; requires
--   VALID session tokens. Do NOT paste any real token into this file or the run
--   log -- replace <...> at run time only.)
--
--   Baseline note: the reference values below (active sites = 10, active
--   assignments = 11, admin sites = 10, sum(active_assignment_count) = 11, known
--   site with 4 active assignments) are the values last recorded on 2026-07-14.
--   The AUTHORITATIVE comparison is the C-8 counts measured IMMEDIATELY BEFORE the
--   body: if C-8 differed from these fixed values, first determine whether that is
--   a legitimate data update (sites / assignments edited since 2026-07-14) or an
--   anomaly, and compare the RPC results against the C-8 values, not against the
--   fixed ones.
--
--   employee session (index.html context):
--     select count(*) from public.list_sites_secure('<valid employee token>');
--       -- expect = C-8 sites.active (last recorded 10)
--     select count(*) from public.list_site_assignments_secure('<valid employee token>');
--       -- expect = C-8 site_assignments.active (last recorded 11)
--
--   management session (admin-app.html / genka-app.html context):
--     select count(*) from public.list_sites_admin_secure('<valid management token>');
--       -- expect = C-8 sites.active (last recorded 10)
--     select coalesce(sum(active_assignment_count), 0)
--       from public.list_sites_admin_secure('<valid management token>');
--       -- expect = C-8 site_assignments.active (last recorded 11)
--     select count(*) from public.get_site_admin_secure('<valid management token>', '<existing site id>');
--       -- expect 1 (0 for a non-existent id)
--     select count(*) from public.list_site_assignments_admin_secure('<valid management token>', '<known site id>');
--       -- expect that site's active assignment count (last recorded example: 4)
--
--   browser smoke (all three screens, production, after reload / re-login):
--     - employee (index.html): site list renders; daily report entry + history work;
--       company_id retained after saving the site period;
--       list_sites_secure / list_site_assignments_secure = 200; no app Console errors.
--     - admin (admin-app.html): site list, "assigned" counts and per-site "N名"
--       match previous values; edit modal fields (name / company / location /
--       start_date / end_date) correct; assignment checkbox initial state correct;
--       the three admin RPCs = 200; no app Console errors.
--     - cost (genka-app.html): site select / period / address / cost display
--       normal; list_sites_admin_secure = 200; no app Console errors.
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; use manually in an emergency)
--   Restores EXACTLY the four changes of this file: the two direct SELECT grants
--   and the two read policies, re-created exactly as recorded in the C-3 pre-check
--   (PERMISSIVE / FOR SELECT / TO public / USING (true)). Nothing else (write
--   policies, RPCs, other tables) is part of this rollback.
--   This RE-WEAKENS security by re-opening the anon / authenticated direct reads,
--   so use it ONLY for emergency recovery. Normally unnecessary because all three
--   screens are already on the read RPCs.
--   Re-confirm the current state (C-1..C-3) before using this. NOT executed.
-- ============================================================
-- BEGIN;
--
-- GRANT SELECT
-- ON TABLE public.sites
-- TO anon, authenticated;
--
-- GRANT SELECT
-- ON TABLE public.site_assignments
-- TO anon, authenticated;
--
-- CREATE POLICY sites_read_all
-- ON public.sites
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- CREATE POLICY sa_read
-- ON public.site_assignments
-- AS PERMISSIVE
-- FOR SELECT
-- TO public
-- USING (true);
--
-- COMMIT;
-- ============================================================
