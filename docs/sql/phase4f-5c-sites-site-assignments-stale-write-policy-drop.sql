-- ============================================================
-- Phase 4-F-5-c: sites / site_assignments stale/no-op write policy drop
--   (sa_update + sa_write + anon_can_insert_sites + anon_can_update_sites)
--   Drop the four residual, no-op write policies on public.sites and
--   public.site_assignments. The anon / authenticated INSERT / UPDATE grants
--   were revoked on 2026-06-13 (Phase 3-3 sites / site_assignments direct
--   write REVOKE), and the 2026-07-14 post-check of Phase 4-F-2B-8 re-measured
--   all 8 table privileges as false for both roles on both tables, so none of
--   these policies currently authorizes anything. They are removed as
--   defense-in-depth: if a write grant ever reappeared by mistake,
--   sa_write / anon_can_insert_sites (WITH CHECK true) would silently allow
--   every INSERT and sa_update / anon_can_update_sites (USING true) would
--   silently allow every UPDATE on their tables.
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - The EXECUTION BODY must be run exactly ONCE by the user (Supabase SQL
--     Editor, manual). DO NOT RE-RUN after success: a second run fails the
--     guard at G-2 (policies already dropped) by design (fail-closed).
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution /
--     NO Supabase CLI / NO psql.
--   - Run order: PRE-CHECK (C-1..C-9) -> EXECUTION GUARD + BODY (single
--     transaction) -> POST-CHECK (P-1..P-7) -> SMOKE TEST -> ROLLBACK only in
--     an emergency, with separate explicit approval.
--
-- [PURPOSE]
--   - public.sites / public.site_assignments write access is already closed
--     at the privilege layer: anon / authenticated INSERT / UPDATE were
--     revoked on 2026-06-13 (Phase 3-3) and all 8 privileges (SELECT /
--     INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER / MAINTAIN)
--     were re-measured false for both roles on both tables on 2026-07-14
--     (Phase 4-F-2B-8 post-check).
--   - The application writes these tables ONLY through 5 SECURITY DEFINER
--     RPCs (owner postgres; FORCE RLS false on both tables, so the owner
--     execution path bypasses RLS and does NOT depend on these policies):
--       create_site_secure / update_site_secure / deactivate_site_secure /
--       set_site_assignment_secure / replace_site_assignments_secure.
--   - Therefore the four write policies are stale no-ops:
--       site_assignments.sa_update        (PERMISSIVE / {public} / UPDATE /
--                                          USING true)
--       site_assignments.sa_write         (PERMISSIVE / {public} / INSERT /
--                                          WITH CHECK true)
--       sites.anon_can_insert_sites       (PERMISSIVE / {anon} / INSERT /
--                                          WITH CHECK true)
--       sites.anon_can_update_sites       (PERMISSIVE / {anon} / UPDATE /
--                                          USING true / WITH CHECK true)
--     Dropping them removes latent allow-all write paths that would spring
--     back to life if a write grant were ever re-added by mistake.
--   - Same rationale and structure as Phase 4-F-5-a (ml_write) and 4-F-5-b
--     (machines_update / machines_write); template:
--     docs/sql/phase4f-5b-machines-stale-write-policy-drop.sql.
--   - NOTE the role difference: the sites policies target {anon} while the
--     site_assignments policies target {public}. The guard verifies each
--     EXACTLY -- do not treat them as interchangeable.
--
-- [SCOPE]
--   - Exactly FOUR policies. The ONLY DB-changing statements in this file are
--     the four DROP POLICY statements in the EXECUTION BODY.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - Table privileges (NO GRANT / NO REVOKE; anon / authenticated stay
--     all-false on both tables).
--   - RLS enabled state / FORCE RLS / table owners (unchanged).
--   - sites / site_assignments data (NO DML; the C-8 baseline must be
--     unchanged in P-7).
--   - The 5 write RPCs, 5 read RPCs, 4 internal sites-referencing RPCs and
--     the _verify_management_session helper (definitions, attributes,
--     EXECUTE ACLs -- all unchanged).
--   - PUBLIC EXECUTE on the 5 write RPCs: KNOWN to remain (Phase 4-F-2B-8
--     record, docs/db-migrations.md -- "既知の PUBLIC EXECUTE はそのまま";
--     the Phase 3 definition files GRANT to anon / authenticated but never
--     REVOKE from PUBLIC). C-4d RECORDS the current state; per the approved
--     scope it is recorded only and NOT changed here -- it joins the same
--     cross-cutting follow-up candidate as the machines write RPCs
--     (Phase 4-F-5-b finding).
--   - No CREATE / ALTER POLICY, no function DDL, no table DDL, no DML.
--   - front-end code, other tables, other policies, other roles' privileges.
--
-- [BASELINE] (real-DB measurements; re-verify ALL of it in PRE-CHECK below)
--   - Sources: Phase 4-F-2B-8 pre/post-check (Supabase SQL Editor,
--     2026-07-14, recorded in docs/db-migrations.md) and the user's re-check
--     of the 4 policy definitions + schema policy count (Supabase SQL Editor,
--     2026-07-17).
--   - sites / site_assignments: relkind 'r', RLS enabled true, FORCE RLS
--     false, owner postgres (both tables).
--   - Policies: sites = 2 (anon_can_insert_sites + anon_can_update_sites),
--     site_assignments = 2 (sa_write + sa_update); definitions exactly as in
--     [PURPOSE] above (read policies sites_read_all / sa_read were dropped by
--     2B-8 on 2026-07-14).
--   - anon / authenticated: all 8 table privileges false on both tables;
--     table ACLs list postgres / service_role only.
--   - public schema total policy count = 29 - 2 = 27 after Phase 4-F-5-b
--     (re-confirmed 27 by the user on 2026-07-17).
--     Expected transition by this file: 27 -> 23.
--   - Write RPCs (5; all SECURITY DEFINER, VOLATILE, owner postgres,
--     search_path=public, extensions; session verified FIRST via
--     public._verify_management_session(session_token_input) before any
--     input validation or DML; GRANT EXECUTE to anon / authenticated;
--     result types are NOT uniform -- verify per-RPC):
--       create_site_secure(text, text, text, date, date, uuid)
--         -> TABLE(id uuid)
--       update_site_secure(text, uuid, text, text, date, date, uuid) -> void
--       deactivate_site_secure(text, uuid) -> void
--       set_site_assignment_secure(text, uuid, uuid, boolean) -> void
--       replace_site_assignments_secure(text, uuid, uuid[]) -> void
--     Definition source: docs/sql/sites-site-assignments-secure-rpc.sql.
--     The session helper public._verify_management_session(text) raises
--     'Invalid or expired session' on failure and is internal-only (EXECUTE
--     revoked from PUBLIC / anon / authenticated at creation).
--   - Read RPCs (5; all SECURITY DEFINER, STABLE, owner postgres,
--     search_path=public, extensions; PUBLIC EXECUTE revoked at creation):
--       list_sites_secure(text) / list_site_assignments_secure(text) /
--       list_sites_admin_secure(text) / get_site_admin_secure(text, uuid) /
--       list_site_assignments_admin_secure(text, uuid).
--     Definition source: docs/sql/phase4f-2b-8-sites-site-assignments-read-rpc.sql.
--   - Internal sites-referencing RPCs (4; all SECURITY DEFINER, owner
--     postgres -- they read sites under owner rights and do NOT depend on
--     the dropped policies):
--       export_projects_summary_secure(text, integer, uuid, uuid, uuid,
--         uuid, boolean, boolean, text[], date, date)
--       create_invoice_secure(text, date, uuid, text, text, integer,
--         boolean, text, text)
--       update_invoice_secure(text, uuid, date, uuid, text, text, integer,
--         boolean, text, text)
--       create_machine_location_secure(text, uuid, uuid, text)
--   - Data reference values (2026-07-14; counts are NOT a fixed STOP
--     condition -- business rows may have changed): sites total 20 /
--     active 10 / inactive 10 / null 0; site_assignments total 30 /
--     active 12 / inactive 18 / null 0; integrity checks all 0.
--
-- [FRONT-END PRECONDITIONS] (verified in the repo on 2026-07-17, main
--   7854520; SQL cannot check these -- recorded here as facts; see C-7)
--   - sites / site_assignments direct read / write via .from('sites') /
--     .from('site_assignments') = 0 across the front-end application code
--     (index.html / admin-app.html / genka-app.html). genka-app.html calls
--     none of the 5 write RPCs either.
--   - Write paths are ONLY the 5 RPCs:
--       index.html:1790  update_site_secure
--       index.html:1809  set_site_assignment_secure
--       index.html:1821  create_site_secure
--       index.html:1822  deactivate_site_secure
--       admin-app.html:482 update_site_secure
--       admin-app.html:493 create_site_secure
--       admin-app.html:508 replace_site_assignments_secure
--       admin-app.html:524 deactivate_site_secure
--   - Reads go through the 5 read RPCs only (enforced by 2B-8 on 2026-07-14).
--   - No application or SQL code references the policy names 'sa_write' /
--     'sa_update' / 'anon_can_insert_sites' / 'anon_can_update_sites'
--     (docs/sql mentions are baseline/records only).
--
-- [STOP CONDITIONS] (if any is hit during PRE-CHECK, do NOT run the body;
--   stop & report -- do NOT guess or "fix" divergence)
--   - C-1: either table missing, relkind <> 'r', RLS <> true,
--          FORCE RLS <> false, or owner <> postgres.
--   - C-2: ANY of the 8 privileges is true for anon or authenticated on
--          either table (an unexpected live write grant means the policies
--          are NOT no-ops -- this file must not run; a separate REVOKE
--          design comes first).
--   - C-2b/C-2c/C-2d: any table ACL entry for PUBLIC / anon / authenticated,
--          any unexpected grantee, or any column-level ACL on either table.
--   - C-3: any of the 4 policies missing (already dropped -> do NOT re-run),
--          duplicated, definition differing from the baseline (INCLUDING the
--          roles value: {anon} for the sites pair, {public} for the
--          site_assignments pair), any additional policy, or per-table
--          policy_count <> 2.
--   - C-3b: public schema policy count <> 27 (schema-level state has drifted
--          from the 2026-07-17 measurement -- reconcile first).
--   - C-4/C-4b/C-4c: any of the 5 write RPCs missing, overloaded, not
--          SECURITY DEFINER, not VOLATILE, owner not postgres, search_path
--          not fixed, identity arguments or PER-RPC result type differing,
--          session verification (_verify_management_session) not found in
--          the body, or anon / authenticated EXECUTE <> true.
--   - C-4d: RECORD the PUBLIC EXECUTE state (known-present per the 2B-8
--          record; no exact per-function measurement exists). PUBLIC EXECUTE
--          being present is NOT by itself a stop condition for this drop
--          (function ACLs and table policies are independent layers; it is
--          the recorded cross-cutting follow-up candidate). STOP only if the
--          output contradicts C-4c or shows grantees that make the recorded
--          write-path model wrong.
--   - C-5: any read RPC, internal RPC, or _verify_management_session
--          missing or differing (the app depends on them; divergence from
--          the recorded state must be reconciled first).
--   - C-6: any SECURITY INVOKER routine referencing either table, any view /
--          materialized view depending on either table, or any user trigger
--          on either table.
--   - C-7: any front-end / repository precondition above is NOT satisfied.
--   - C-8: (data baseline) record the aggregates; they are the invariant vs
--          P-7. The absolute values are NOT a stop condition.
--
-- [ROLLBACK] (see the commented section at the end -- reference only)
--   Re-creates the four policies exactly as measured in C-3 (sites pair
--   TO anon; site_assignments pair TO public). Policy layer only; NO grant
--   is restored. Requires separate explicit approval. WARNING: rollback
--   re-creates the latent allow-all write paths this file removes.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. table attributes for BOTH tables.
--    Expected: 2 rows, each relkind = 'r', rls_enabled = true,
--      rls_forced = false, owner = postgres.
--    STOP if either table is missing or anything differs.
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
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- C-2. anon / authenticated table grants on BOTH tables.
--    Expected: ALL 8 privileges false for BOTH roles on BOTH tables
--      (2B-8 post-check baseline, 2026-07-14; 32 items in total).
--    STOP if ANY privilege is true -- the policies would then NOT be no-ops.
--    NOTE: 'MAINTAIN' requires PostgreSQL 17+ in has_table_privilege (this
--      project runs PG 17.x per the Phase 4-F-2A record).
select
  t.tbl,
  v.role_name,
  has_table_privilege(v.role_name, t.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, t.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, t.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, t.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, t.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, t.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, t.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, t.tbl, 'MAINTAIN')   as can_maintain
from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
cross join (values ('anon'), ('authenticated')) as v(role_name)
order by t.tbl, v.role_name;

-- C-2b. raw table ACLs (relacl) for BOTH tables, ALL grantees.
--    Expected: entries for postgres (owner) and service_role ONLY.
--    STOP if PUBLIC (grantee 0), anon, authenticated, or any unexpected
--    grantee appears with ANY privilege.
select
  c.relname as table_name,
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
  and c.relname in ('sites', 'site_assignments')
order by c.relname, grantee, acl.privilege_type;

-- C-2c. information_schema.role_table_grants for BOTH tables.
--    Expected: 0 rows (the filter selects only PUBLIC / anon / authenticated
--      so any divergence is visible: STOP if any row appears).
select table_name, grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('sites', 'site_assignments')
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by table_name, grantee, privilege_type;

-- C-2d. column-level ACLs (attacl) on BOTH tables.
--    Expected: 0 rows (no column ACL exists at all on these tables).
--    STOP if any row is returned (an unexpected column-level grant -- write
--    or read -- means the recorded baseline no longer holds).
select
  c.relname as table_name,
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
  and c.relname in ('sites', 'site_assignments')
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by c.relname, a.attname, grantee;

-- C-3. policies on BOTH tables -- full definitions (also the ROLLBACK
--    source).
--    Expected: exactly 4 rows, matching EXACTLY:
--      site_assignments.sa_write : PERMISSIVE, roles {public}, cmd INSERT,
--                                  qual null, with_check true.
--      site_assignments.sa_update: PERMISSIVE, roles {public}, cmd UPDATE,
--                                  qual true, with_check null.
--      sites.anon_can_insert_sites: PERMISSIVE, roles {anon}, cmd INSERT,
--                                  qual null, with_check true.
--      sites.anon_can_update_sites: PERMISSIVE, roles {anon}, cmd UPDATE,
--                                  qual true, with_check true.
--    NOTE the roles difference: {anon} on the sites pair, {public} on the
--    site_assignments pair.
--    STOP if any policy is missing (already dropped -> do NOT run the body),
--    duplicated, or differing; if any additional policy exists; or if the
--    per-table counts are not 2 / 2.
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
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

select tablename, count(*) as policy_count   -- expect sites = 2, site_assignments = 2
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
group by tablename
order by tablename;

-- C-3b. total policy count across schema public (whole-schema invariant).
--    Expected: 27 (user re-measurement 2026-07-17, after Phase 4-F-5-b).
--    STOP and reconcile if it differs (another change happened since).
--    P-1b after the body must equal EXACTLY this value - 4 (only the four
--    write policies disappear; no other table's policies are touched).
--    Expected transition: 27 -> 23.
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- C-4. write RPC baseline -- 5 functions (must be UNCHANGED in P-5).
--    Expected: EXACTLY 5 rows, one per function, each with
--      security_definer = true, volatility = 'v' (VOLATILE),
--      owner = postgres, config containing search_path=public, extensions,
--      and the PER-RPC result type / identity args below (result types are
--      NOT uniform -- do not assume TABLE(id uuid) for all):
--        create_site_secure -> TABLE(id uuid);
--          session_token_input text, name_input text, location_input text,
--          start_date_input date, end_date_input date, company_id_input uuid
--        update_site_secure -> void;
--          session_token_input text, id_input uuid, name_input text,
--          location_input text, start_date_input date, end_date_input date,
--          company_id_input uuid
--        deactivate_site_secure -> void;
--          session_token_input text, id_input uuid
--        set_site_assignment_secure -> void;
--          session_token_input text, site_id_input uuid,
--          employee_id_input uuid, is_active_input boolean
--        replace_site_assignments_secure -> void;
--          session_token_input text, site_id_input uuid,
--          employee_ids_input uuid[]
--    A 6th row would be an unexpected OVERLOAD -> STOP.
--    STOP if any function is missing or any attribute differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,      -- expect true
  p.provolatile               as volatility,            -- expect 'v' (VOLATILE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid)             as result_type,  -- expect PER-RPC value above
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
order by p.proname;

-- C-4b. write RPC session verification is present in each function body.
--    Expected: 5 rows, has_mgmt_session_check = true for ALL.
--    (All 5 call public._verify_management_session(session_token_input)
--     FIRST, before any input validation or DML; the helper raises 'Invalid
--     or expired session' on failure. strpos is used instead of LIKE so the
--     underscores are matched literally.)
--    STOP if any row is false (the deployed function differs from the repo
--    definition).
select
  p.oid::regprocedure::text as function_signature,
  strpos(p.prosrc, '_verify_management_session') > 0 as has_mgmt_session_check
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
order by p.proname;

-- C-4c. write RPC EXECUTE privileges (baseline; UNCHANGED in P-5).
--    Expected: 5 rows, anon_execute = true AND authenticated_execute = true
--      for ALL (per the GRANT statements in the definition file).
--    STOP if any is false.
select
  p.oid::regprocedure::text as function_signature,
  has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
order by p.proname;

-- C-4d. write RPC PUBLIC EXECUTE state (RECORD ONLY -- known to remain).
--    The Phase 4-F-2B-8 record explicitly notes the known PUBLIC EXECUTE on
--    these write RPCs was left as-is ("既知の PUBLIC EXECUTE はそのまま"),
--    and the Phase 3 definition file (sites-site-assignments-secure-rpc.sql)
--    GRANTs to anon / authenticated but never REVOKEs from PUBLIC, so rows
--    are EXPECTED here.
--    -> RECORD the output. Per the approved scope it is recorded only and
--       NOT changed here; it joins the machines write RPCs (Phase 4-F-5-b
--       finding) as one cross-cutting "write RPC PUBLIC EXECUTE revoke"
--       follow-up candidate. It does NOT block this policy drop (function
--       ACLs and table policies are independent layers). The GUARD therefore
--       does NOT assert a PUBLIC EXECUTE value; P-5 re-runs this query and
--       must return the IDENTICAL result (this file must not change it).
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
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE'
order by p.proname;

-- C-5. read RPCs still exist (the app's read path; NOT touched by this
--    file).
--    Expected: 5 rows -- each SECURITY DEFINER = true, volatility 's'
--      (STABLE), owner postgres, config search_path=public, extensions, and
--      the PER-RPC result type (definition source:
--      docs/sql/phase4f-2b-8-sites-site-assignments-read-rpc.sql):
--        list_sites_secure(text)
--          -> TABLE(id uuid, name text, company_id uuid, location text,
--                   start_date date, end_date date)
--        list_site_assignments_secure(text)
--          -> TABLE(site_id uuid, employee_id uuid)
--        list_sites_admin_secure(text)
--          -> TABLE(id uuid, name text, company_id uuid, location text,
--                   start_date date, end_date date,
--                   active_assignment_count bigint)
--        get_site_admin_secure(text, uuid)
--          -> TABLE(id uuid, name text, company_id uuid, location text,
--                   start_date date, end_date date)
--        list_site_assignments_admin_secure(text, uuid)
--          -> TABLE(employee_id uuid)
--    STOP if any is missing or differs (state diverged from the record).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's' (STABLE)
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid) as result_type          -- expect PER-RPC value above
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure',
                    'list_site_assignments_secure',
                    'list_sites_admin_secure',
                    'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;

select p.proname, count(*) as overload_count   -- expect 1 for each of the 5 names
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_sites_secure',
                    'list_site_assignments_secure',
                    'list_sites_admin_secure',
                    'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
group by p.proname
order by p.proname;

-- C-5b. internal sites-referencing RPCs (SECURITY DEFINER owner execution --
--    they do NOT depend on the dropped policies; NOT touched by this file).
--    Expected: 4 rows with EXACTLY these signatures (any extra row for one
--      of these names is an unexpected OVERLOAD -> STOP):
--        export_projects_summary_secure(text, integer, uuid, uuid, uuid,
--          uuid, boolean, boolean, text[], date, date)
--        create_invoice_secure(text, date, uuid, text, text, integer,
--          boolean, text, text)
--        update_invoice_secure(text, uuid, date, uuid, text, text, integer,
--          boolean, text, text)
--        create_machine_location_secure(text, uuid, uuid, text)
--      each SECURITY DEFINER = true, owner postgres, config
--      search_path=public, extensions.
--    STOP if any is missing, overloaded, or any attribute differs.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config                 -- expect search_path=public, extensions
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure',
                    'create_invoice_secure',
                    'update_invoice_secure',
                    'create_machine_location_secure')
order by p.proname;

select p.proname, count(*) as overload_count   -- expect 1 for each of the 4 names
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure',
                    'create_invoice_secure',
                    'update_invoice_secure',
                    'create_machine_location_secure')
group by p.proname
order by p.proname;

-- C-5c. _verify_management_session helper (internal-only; NOT touched).
--    Expected: 1 row -- signature _verify_management_session(text),
--      SECURITY DEFINER = true, owner postgres, config search_path=public,
--      extensions, result type TABLE(actor_type text, actor_id uuid)
--      (definition source: docs/sql/sites-site-assignments-secure-rpc.sql),
--      and EXECUTE false for anon / authenticated (revoked at creation --
--      the helper is internal-only).
--    STOP if missing, overloaded, or any attribute / EXECUTE state differs.
select
  p.oid::regprocedure::text   as function_signature,    -- expect _verify_management_session(text), exactly 1 row
  p.prosecdef                 as is_security_definer,   -- expect true
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid) as result_type,         -- expect TABLE(actor_type text, actor_id uuid)
  has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_execute,          -- expect false
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute  -- expect false
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';

-- C-5d. _verify_management_session PUBLIC EXECUTE is absent (REVOKEd from
--    PUBLIC at creation, unlike the write RPCs).
--    Expected: 0 rows. STOP if any row is returned.
select
  p.oid::regprocedure::text as function_signature,
  'PUBLIC'                  as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = '_verify_management_session'
  and acl.grantee = 0
  and acl.privilege_type = 'EXECUTE';

-- C-6. dependency check: nothing besides the known SECURITY DEFINER RPCs may
--    depend on sites / site_assignments.
-- C-6a. SECURITY INVOKER routines whose source references either table.
--    Expected: 0 rows. STOP if any row is returned (an invoker-rights
--    routine could be affected by policy changes).
select
  p.oid::regprocedure::text as function_signature,
  p.prosecdef               as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = false
  and (p.prosrc ilike '%sites%' or p.prosrc ilike '%site_assignments%')
order by function_signature;

-- C-6b. views / materialized views depending on either table.
--    Expected: 0 rows. STOP if any row is returned.
select distinct
  dep_n.nspname as view_schema,
  dep_c.relname as view_name,
  dep_c.relkind as relkind,         -- 'v' = view, 'm' = materialized view
  src_c.relname as depends_on
from pg_depend d
join pg_rewrite rw    on rw.oid = d.objid
join pg_class dep_c   on dep_c.oid = rw.ev_class
join pg_namespace dep_n on dep_n.oid = dep_c.relnamespace
join pg_class src_c   on src_c.oid = d.refobjid
join pg_namespace src_n on src_n.oid = src_c.relnamespace
where d.classid = 'pg_rewrite'::regclass
  and d.refclassid = 'pg_class'::regclass
  and src_n.nspname = 'public'
  and src_c.relname in ('sites', 'site_assignments')
  and dep_c.relname not in ('sites', 'site_assignments')
order by view_schema, view_name;

-- C-6c. user triggers on either table.
--    Expected: 0 rows. STOP if any row is returned.
select
  c.relname as table_name,
  t.tgname  as trigger_name,
  p.proname as trigger_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and t.tgisinternal = false
order by c.relname, t.tgname;

-- C-7. front-end / repository preconditions (NOT checkable from SQL;
--    confirmed from the repo BEFORE running the body -- recorded here as
--    facts). "front-end application code" = index.html / admin-app.html /
--    genka-app.html. Documentation string hits inside docs/sql are EXCLUDED
--    from these counts.
--    If ANY of these is NOT true, STOP and do NOT run the body:
--    - sites / site_assignments direct read / write via .from(...) = 0 in
--      the front-end application code (verified 2026-07-17, main 7854520).
--    - The ONLY application write paths are the 5 write RPCs:
--      index.html:1790 update_site_secure / index.html:1809
--      set_site_assignment_secure / index.html:1821 create_site_secure /
--      index.html:1822 deactivate_site_secure / admin-app.html:482
--      update_site_secure / admin-app.html:493 create_site_secure /
--      admin-app.html:508 replace_site_assignments_secure /
--      admin-app.html:524 deactivate_site_secure. genka-app.html calls none.
--    - Reads go through the 5 read RPCs only (enforced by 2B-8 on
--      2026-07-14).
--    - No application or SQL code references the policy names 'sa_write' /
--      'sa_update' / 'anon_can_insert_sites' / 'anon_can_update_sites'
--      (docs/sql mentions are baseline/records only).
--    - No view / materialized view / trigger creation on either table exists
--      anywhere in docs/sql.

-- C-8. data baseline for BOTH tables (INVARIANT vs P-7).
--    Record all values. Reference values from 2026-07-14: sites 20/10/10/0;
--    site_assignments 30/12/18/0; integrity checks 0 -- business rows may
--    have changed since; ANY current value is fine (the absolute numbers are
--    NOT a stop condition). The whole result only must be UNCHANGED by the
--    body, which performs NO DML.
select
  'sites' as tbl,
  count(*)                                  as total_rows,
  count(*) filter (where is_active = true)  as active_rows,
  count(*) filter (where is_active = false) as inactive_rows,
  count(*) filter (where is_active is null) as null_active_rows
from public.sites
union all
select
  'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments
order by tbl;

-- C-8b. referential integrity reference values (INVARIANT vs P-7; last
--    recorded all 0).
select
  (select count(*) from public.site_assignments sa
     where sa.site_id is null)                          as sa_null_site_id,
  (select count(*) from public.site_assignments sa
     where sa.employee_id is null)                      as sa_null_employee_id,
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where sa.site_id is not null and s.id is null)     as sa_orphan_site;


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-8 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction
--   as the body: if any expectation fails, it RAISEs, the transaction
--   aborts, and NOTHING is changed (fail-closed). A second run fails the
--   guard at G-2 (policies already dropped) before any statement that would
--   modify state -- the body must NOT be re-run after success.
--   The ONLY DB-changing statements are the FOUR DROP POLICY statements.
--   No GRANT / REVOKE, no CREATE / ALTER POLICY, no function DDL, no table
--   DDL, no DML.
--   DROP POLICY is used WITHOUT "IF EXISTS" on purpose: unexpected absence
--   must fail the whole transaction loudly instead of half-succeeding
--   silently (all four drops commit together or none does).
-- ============================================================

BEGIN;

-- GUARD (read-only; aborts the transaction on any unexpected state)
DO $guard$
declare
  v_cnt integer;
  rec   record;
begin
  -- G-1. both tables exist with expected attributes (relkind r, RLS on,
  --      NOT forced, owner postgres).
  for rec in
    select t.tname
    from (values ('sites'), ('site_assignments')) as t(tname)
  loop
    select count(*) into v_cnt
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = rec.tname
      and c.relkind = 'r'
      and c.relrowsecurity = true
      and c.relforcerowsecurity = false
      and pg_get_userbyid(c.relowner) = 'postgres';
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-1): public.% with relkind r / RLS on / FORCE off / owner postgres not found (count=%)', rec.tname, v_cnt;
    end if;
  end loop;

  -- G-2. each of the 4 policies exists exactly once (by table + name).
  --      0 rows means the body already ran (or the policy vanished) -> STOP,
  --      do NOT re-run; >1 is divergence.
  for rec in
    select t.tname, t.pname
    from (values ('site_assignments', 'sa_update'),
                 ('site_assignments', 'sa_write'),
                 ('sites',            'anon_can_insert_sites'),
                 ('sites',            'anon_can_update_sites')) as t(tname, pname)
  loop
    select count(*) into v_cnt
    from pg_policies
    where schemaname = 'public' and tablename = rec.tname
      and policyname = rec.pname;
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-2): %.% is MISSING -- body may have run before; reconcile, do NOT re-run', rec.tname, rec.pname;
    elsif v_cnt > 1 then
      raise exception 'GUARD STOP (G-2): %.% is DUPLICATED (% rows)', rec.tname, rec.pname, v_cnt;
    end if;
  end loop;

  -- G-3. all four definitions match the baseline EXACTLY. NOTE the roles
  --      values: {public} on the site_assignments pair, {anon} on the sites
  --      pair -- they are verified separately and must NOT be interchanged.
  --      sa_update: PERMISSIVE / {public} / UPDATE / qual true /
  --      with_check null.
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
    raise exception 'GUARD STOP (G-3): sa_update DEFINITION DIFFERS from baseline PERMISSIVE/{public}/UPDATE/qual true/with_check null';
  end if;
  --      sa_write: PERMISSIVE / {public} / INSERT / qual null /
  --      with_check true.
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
    raise exception 'GUARD STOP (G-3): sa_write DEFINITION DIFFERS from baseline PERMISSIVE/{public}/INSERT/qual null/with_check true';
  end if;
  --      anon_can_insert_sites: PERMISSIVE / {anon} / INSERT / qual null /
  --      with_check true.
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
    raise exception 'GUARD STOP (G-3): anon_can_insert_sites DEFINITION DIFFERS from baseline PERMISSIVE/{anon}/INSERT/qual null/with_check true';
  end if;
  --      anon_can_update_sites: PERMISSIVE / {anon} / UPDATE / qual true /
  --      with_check true (the only one of the four with BOTH qual and
  --      with_check non-null).
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
    raise exception 'GUARD STOP (G-3): anon_can_update_sites DEFINITION DIFFERS from baseline PERMISSIVE/{anon}/UPDATE/qual true/with_check true';
  end if;

  -- G-4. the four policies are the ONLY policies on the two tables
  --      (per-table count = 2 each; no unexpected policy).
  for rec in
    select t.tname
    from (values ('sites'), ('site_assignments')) as t(tname)
  loop
    select count(*) into v_cnt
    from pg_policies
    where schemaname = 'public' and tablename = rec.tname;
    if v_cnt <> 2 then
      raise exception 'GUARD STOP (G-4): % policy count = % (expected exactly 2)', rec.tname, v_cnt;
    end if;
  end loop;

  -- G-5. whole-schema invariant: public schema policy count = 27 (as
  --      measured 2026-07-17 after Phase 4-F-5-b). A different value means
  --      OTHER schema-level changes happened after this file was designed ->
  --      fail-closed STOP; reconcile (and update this file via a reviewed
  --      PR) before running. Do NOT loosen this check ad hoc.
  select count(*) into v_cnt
  from pg_policies
  where schemaname = 'public';
  if v_cnt <> 27 then
    raise exception 'GUARD STOP (G-5): public schema policy count = % (expected 27) -- schema state drifted from the designed baseline; reconcile before running', v_cnt;
  end if;

  -- G-6. anon / authenticated have NONE of the 8 table privileges on either
  --      table. Any true privilege means the policies are NOT no-ops -> STOP
  --      (a REVOKE design would be needed first; that is NOT this file's
  --      scope).
  perform 1
  from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
  cross join (values ('anon'), ('authenticated')) as r(role_name)
  cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                     ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')) as p(priv)
  where has_table_privilege(r.role_name, t.tbl, p.priv);
  if found then
    raise exception 'GUARD STOP (G-6): anon/authenticated hold an unexpected table privilege on sites/site_assignments -- the policies are NOT no-ops; do NOT drop them in this state';
  end if;

  -- G-7. raw ACL: no table ACL entry of ANY kind for PUBLIC / anon /
  --      authenticated on either table, and no column-level ACL at all.
  select count(*) into v_cnt
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
  left join pg_roles r on r.oid = acl.grantee
  where n.nspname = 'public'
    and c.relname in ('sites', 'site_assignments')
    and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated'));
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-7): unexpected table ACL entries for PUBLIC/anon/authenticated on sites/site_assignments (% rows)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_attribute a
  join pg_class c     on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('sites', 'site_assignments')
    and a.attnum > 0
    and not a.attisdropped
    and a.attacl is not null;
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-7): unexpected column-level ACL on sites/site_assignments (% columns)', v_cnt;
  end if;

  -- G-8. the 5 write RPCs: exact signature, NO overload, SECURITY DEFINER,
  --      VOLATILE, owner postgres, fixed search_path, PER-RPC result type
  --      (NOT uniform: TABLE(id uuid) for create_site_secure, void for the
  --      other four), session verification present in the body
  --      (_verify_management_session, matched literally via strpos), and
  --      anon / authenticated EXECUTE = true.
  --      PUBLIC EXECUTE is deliberately NOT asserted here: it is KNOWN to
  --      remain (2B-8 record) -- it is recorded in C-4d, re-recorded in P-5,
  --      and belongs to the separate cross-cutting follow-up step. This file
  --      must not change and does not depend on it.
  --      NOTE: the search_path comparison expects the recorded storage form
  --      'search_path=public, extensions'. If the guard stops here while C-4
  --      shows a correctly fixed search_path with only different spacing,
  --      STOP and report -- reconcile the baseline; do NOT loosen this check
  --      ad hoc.
  for rec in
    select t.fname, t.fsig, t.fargs, t.fresult
    from (values
      ('create_site_secure',
       'public.create_site_secure(text, text, text, date, date, uuid)',
       'session_token_input text, name_input text, location_input text, start_date_input date, end_date_input date, company_id_input uuid',
       'TABLE(id uuid)'),
      ('update_site_secure',
       'public.update_site_secure(text, uuid, text, text, date, date, uuid)',
       'session_token_input text, id_input uuid, name_input text, location_input text, start_date_input date, end_date_input date, company_id_input uuid',
       'void'),
      ('deactivate_site_secure',
       'public.deactivate_site_secure(text, uuid)',
       'session_token_input text, id_input uuid',
       'void'),
      ('set_site_assignment_secure',
       'public.set_site_assignment_secure(text, uuid, uuid, boolean)',
       'session_token_input text, site_id_input uuid, employee_id_input uuid, is_active_input boolean',
       'void'),
      ('replace_site_assignments_secure',
       'public.replace_site_assignments_secure(text, uuid, uuid[])',
       'session_token_input text, site_id_input uuid, employee_ids_input uuid[]',
       'void')
    ) as t(fname, fsig, fargs, fresult)
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
      and pg_get_function_result(p.oid) = rec.fresult
      and pg_get_function_identity_arguments(p.oid) = rec.fargs
      and strpos(p.prosrc, '_verify_management_session') > 0;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-8): % attributes/signature/result type/session-check differ from the recorded baseline', rec.fname;
    end if;
    if not has_function_privilege('anon', to_regprocedure(rec.fsig), 'EXECUTE')
       or not has_function_privilege('authenticated', to_regprocedure(rec.fsig), 'EXECUTE') then
      raise exception 'GUARD STOP (G-8): anon/authenticated EXECUTE on % differs from the recorded baseline (expected true for both)', rec.fname;
    end if;
  end loop;

  -- G-9. the 5 read RPCs, 4 internal sites-referencing RPCs and the
  --      _verify_management_session helper still exist with the recorded
  --      attributes (the app depends on them; their absence signals
  --      divergence -- this file does not touch them).
  -- G-9a. read RPCs: exact signature, NO overload, SECURITY DEFINER,
  --       STABLE, owner postgres, fixed search_path, and PER-RPC result
  --       type matching the repo definitions
  --       (docs/sql/phase4f-2b-8-sites-site-assignments-read-rpc.sql)
  --       exactly.
  for rec in
    select t.fname, t.fsig, t.fresult
    from (values
      ('list_sites_secure',
       'public.list_sites_secure(text)',
       'TABLE(id uuid, name text, company_id uuid, location text, start_date date, end_date date)'),
      ('list_site_assignments_secure',
       'public.list_site_assignments_secure(text)',
       'TABLE(site_id uuid, employee_id uuid)'),
      ('list_sites_admin_secure',
       'public.list_sites_admin_secure(text)',
       'TABLE(id uuid, name text, company_id uuid, location text, start_date date, end_date date, active_assignment_count bigint)'),
      ('get_site_admin_secure',
       'public.get_site_admin_secure(text, uuid)',
       'TABLE(id uuid, name text, company_id uuid, location text, start_date date, end_date date)'),
      ('list_site_assignments_admin_secure',
       'public.list_site_assignments_admin_secure(text, uuid)',
       'TABLE(employee_id uuid)')
    ) as t(fname, fsig, fresult)
  loop
    if to_regprocedure(rec.fsig) is null then
      raise exception 'GUARD STOP (G-9): read RPC % is missing', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-9): read RPC % has unexpected overloads (count=%, expected 1)', rec.fname, v_cnt;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname
      and p.prosecdef = true
      and p.provolatile = 's'
      and pg_get_userbyid(p.proowner) = 'postgres'
      and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%'
      and pg_get_function_result(p.oid) = rec.fresult;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-9): read RPC % attributes/result type differ from the recorded baseline', rec.fname;
    end if;
  end loop;
  -- G-9b. internal sites-referencing RPCs: exact signature, NO overload,
  --       SECURITY DEFINER, owner postgres, fixed search_path.
  for rec in
    select t.fname, t.fsig
    from (values
      ('export_projects_summary_secure',
       'public.export_projects_summary_secure(text, integer, uuid, uuid, uuid, uuid, boolean, boolean, text[], date, date)'),
      ('create_invoice_secure',
       'public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text)'),
      ('update_invoice_secure',
       'public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text)'),
      ('create_machine_location_secure',
       'public.create_machine_location_secure(text, uuid, uuid, text)')
    ) as t(fname, fsig)
  loop
    if to_regprocedure(rec.fsig) is null then
      raise exception 'GUARD STOP (G-9): internal RPC % is missing', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname;
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-9): internal RPC % has unexpected overloads (count=%, expected 1)', rec.fname, v_cnt;
    end if;
    select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = rec.fname
      and p.prosecdef = true
      and pg_get_userbyid(p.proowner) = 'postgres'
      and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%';
    if v_cnt <> 1 then
      raise exception 'GUARD STOP (G-9): internal RPC % attributes differ from the recorded baseline', rec.fname;
    end if;
  end loop;
  -- G-9c. _verify_management_session helper: exists exactly once with the
  --       recorded attributes and stays internal-only (no EXECUTE for
  --       anon / authenticated, no PUBLIC EXECUTE).
  if to_regprocedure('public._verify_management_session(text)') is null then
    raise exception 'GUARD STOP (G-9): _verify_management_session(text) is missing';
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = '_verify_management_session';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-9): _verify_management_session has unexpected overloads (count=%, expected 1)', v_cnt;
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = '_verify_management_session'
    and p.prosecdef = true
    and pg_get_userbyid(p.proowner) = 'postgres'
    and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%';
  if v_cnt <> 1 then
    raise exception 'GUARD STOP (G-9): _verify_management_session attributes differ from the recorded baseline';
  end if;
  if has_function_privilege('anon', to_regprocedure('public._verify_management_session(text)'), 'EXECUTE')
     or has_function_privilege('authenticated', to_regprocedure('public._verify_management_session(text)'), 'EXECUTE') then
    raise exception 'GUARD STOP (G-9): _verify_management_session is EXECUTABLE by anon/authenticated -- it must stay internal-only';
  end if;
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
  where n.nspname = 'public'
    and p.proname = '_verify_management_session'
    and acl.grantee = 0
    and acl.privilege_type = 'EXECUTE';
  if v_cnt <> 0 then
    raise exception 'GUARD STOP (G-9): _verify_management_session has PUBLIC EXECUTE -- it must stay internal-only';
  end if;

  raise notice 'GUARD OK: state matches the expected baseline; proceeding to drop the 4 stale write policies';
end
$guard$;

-- BODY (EXACTLY FOUR DB changes; no IF EXISTS -- unexpected absence must
-- fail the whole transaction; all four drops commit together or none does)

DROP POLICY sa_update ON public.site_assignments;
DROP POLICY sa_write ON public.site_assignments;
DROP POLICY anon_can_insert_sites ON public.sites;
DROP POLICY anon_can_update_sites ON public.sites;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. policies on both tables after the drop.
--    Expected: 0 rows; per-table policy_count = 0; each named count = 0
--      (all four gone; nothing else existed).
select
  tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments')
order by tablename, cmd, policyname;

select count(*) as policy_count   -- expect 0
from pg_policies
where schemaname = 'public'
  and tablename in ('sites', 'site_assignments');

select
  count(*) filter (where policyname = 'sa_update')             as sa_update_count,             -- expect 0
  count(*) filter (where policyname = 'sa_write')              as sa_write_count,              -- expect 0
  count(*) filter (where policyname = 'anon_can_insert_sites') as anon_can_insert_sites_count, -- expect 0
  count(*) filter (where policyname = 'anon_can_update_sites') as anon_can_update_sites_count  -- expect 0
from pg_policies
where schemaname = 'public';

-- P-1b. total policy count across schema public.
--    Expected: 23 -- EXACTLY the C-3b value (27) minus 4 (only the four
--      write policies disappeared; no other table's policies were touched).
select count(*) as public_schema_policy_count
from pg_policies
where schemaname = 'public';

-- P-2. table attributes UNCHANGED for both tables.
--    Expected: 2 rows, each relkind = 'r', rls_enabled = true,
--      rls_forced = false, owner = postgres (same as C-1).
select
  c.relname             as table_name,
  c.relkind             as relkind,
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
order by c.relname;

-- P-3. anon / authenticated table grants UNCHANGED (all 8 privileges false
--    on both tables; this file performed NO GRANT / REVOKE).
select
  t.tbl,
  v.role_name,
  has_table_privilege(v.role_name, t.tbl, 'SELECT')     as can_select,
  has_table_privilege(v.role_name, t.tbl, 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, t.tbl, 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, t.tbl, 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, t.tbl, 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, t.tbl, 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, t.tbl, 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, t.tbl, 'MAINTAIN')   as can_maintain
from (values ('public.sites'), ('public.site_assignments')) as t(tbl)
cross join (values ('anon'), ('authenticated')) as v(role_name)
order by t.tbl, v.role_name;

-- P-4. raw table ACL / role_table_grants / column ACL UNCHANGED from
--    C-2b/C-2c/C-2d.
--    Expected: identical output to C-2b (postgres / service_role only);
--      0 rows for the C-2c filter; 0 rows for column ACLs.
select
  c.relname as table_name,
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
  and c.relname in ('sites', 'site_assignments')
order by c.relname, grantee, acl.privilege_type;

select table_name, grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('sites', 'site_assignments')
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by table_name, grantee, privilege_type;   -- expect 0 rows

select
  c.relname as table_name,
  a.attname as column_name,
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type
from pg_attribute a
join pg_class c      on c.oid = a.attrelid
join pg_namespace n  on n.oid = c.relnamespace
cross join lateral aclexplode(a.attacl) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname in ('sites', 'site_assignments')
  and a.attnum > 0
  and not a.attisdropped
  and a.attacl is not null
order by c.relname, a.attname, grantee;         -- expect 0 rows

-- P-5. the 5 write RPCs UNCHANGED from the C-4 baseline.
--    Expected: 5 rows identical to C-4 (SECURITY DEFINER, VOLATILE, owner
--      postgres, fixed search_path, PER-RPC result type, same identity
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
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
order by p.proname;                       -- expect 5 rows, same as C-4/C-4b/C-4c

select
  p.oid::regprocedure::text as function_signature,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('create_site_secure',
                    'update_site_secure',
                    'deactivate_site_secure',
                    'set_site_assignment_secure',
                    'replace_site_assignments_secure')
  and acl.grantee = 0
  and acl.privilege_type = 'EXECUTE'
order by p.proname;                       -- expect IDENTICAL output to C-4d

-- P-6. read RPCs, internal RPCs and _verify_management_session UNCHANGED
--    (same as C-5 / C-5b / C-5c / C-5d).
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
  and p.proname in ('list_sites_secure',
                    'list_site_assignments_secure',
                    'list_sites_admin_secure',
                    'get_site_admin_secure',
                    'list_site_assignments_admin_secure')
order by p.proname;                       -- expect 5 rows, same as C-5

select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('export_projects_summary_secure',
                    'create_invoice_secure',
                    'update_invoice_secure',
                    'create_machine_location_secure')
order by p.proname;                       -- expect 4 rows, same as C-5b

select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config,
  pg_get_function_result(p.oid) as result_type,
  has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = '_verify_management_session';   -- expect 1 row, same as C-5c

select
  p.oid::regprocedure::text as function_signature,
  'PUBLIC'                  as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname = '_verify_management_session'
  and acl.grantee = 0
  and acl.privilege_type = 'EXECUTE';             -- expect 0 rows, same as C-5d

-- P-7. data UNCHANGED from the C-8 / C-8b baseline (INVARIANT).
--    Expected: every value equals C-8 / C-8b. The body performs no DML, so
--      this must match; any difference is external write activity, not this
--      file.
select
  'sites' as tbl,
  count(*)                                  as total_rows,
  count(*) filter (where is_active = true)  as active_rows,
  count(*) filter (where is_active = false) as inactive_rows,
  count(*) filter (where is_active is null) as null_active_rows
from public.sites
union all
select
  'site_assignments',
  count(*),
  count(*) filter (where is_active = true),
  count(*) filter (where is_active = false),
  count(*) filter (where is_active is null)
from public.site_assignments
order by tbl;

select
  (select count(*) from public.site_assignments sa
     where sa.site_id is null)                          as sa_null_site_id,
  (select count(*) from public.site_assignments sa
     where sa.employee_id is null)                      as sa_null_employee_id,
  (select count(*) from public.site_assignments sa
     left join public.sites s on s.id = sa.site_id
     where sa.site_id is not null and s.id is null)     as sa_orphan_site;


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   [DB negative -- direct INSERT / UPDATE stay impossible on BOTH tables]
--     - Primary evidence: P-3 / P-4 (anon / authenticated INSERT / UPDATE =
--       false; no ACL entries). The privilege layer -- not the dropped
--       policies -- is what blocks direct writes, and it is proven
--       unchanged.
--     - Optional live negative tests (safe by design -- each wrapped in a
--       transaction that is ALWAYS rolled back, so even an unexpected
--       success persists nothing; no real business values are used):
--         -- (a) anon direct INSERT into sites
--         BEGIN;
--         SET LOCAL ROLE anon;
--         INSERT INTO public.sites (name) VALUES ('negative-smoke');
--         ROLLBACK;
--         -- (b) anon direct UPDATE on sites
--         BEGIN;
--         SET LOCAL ROLE anon;
--         UPDATE public.sites SET is_active = is_active WHERE false;
--         ROLLBACK;
--         -- (c) anon direct INSERT into site_assignments
--         BEGIN;
--         SET LOCAL ROLE anon;
--         INSERT INTO public.site_assignments (site_id, employee_id)
--         VALUES (gen_random_uuid(), gen_random_uuid());
--         ROLLBACK;
--         -- (d) anon direct UPDATE on site_assignments
--         BEGIN;
--         SET LOCAL ROLE anon;
--         UPDATE public.site_assignments SET is_active = is_active
--         WHERE false;
--         ROLLBACK;
--       Expected: ERROR 42501 insufficient_privilege (permission denied for
--       table sites / site_assignments) at each INSERT / UPDATE statement;
--       then run ROLLBACK to end the aborted transaction. Confirm EACH of
--       the four operations (a) / (b) / (c) / (d) individually and record a
--       per-operation PASS/FAIL flag -- do not summarize them as one result.
--       PASS only when the statement fails with SQLSTATE 42501
--       (insufficient_privilege). A success, or a failure with any OTHER
--       error / SQLSTATE, is a FAIL -> stop and report; do not treat a
--       different rejection as equivalent.
--       (The table ACL check fires at executor startup, BEFORE any
--       constraint or row evaluation -- the WHERE false does not bypass
--       it -- so no other error can precede 42501 while the privilege is
--       absent.)
--       If SET LOCAL ROLE anon fails in the SQL Editor session, skip this --
--       P-3 already proves the same fact via has_table_privilege.
--
--   [RPC negative -- invalid session is rejected; no data change]
--     - In the SQL Editor (uses a dummy literal and gen_random_uuid() --
--       real token values and real business UUIDs must never be used or
--       recorded). deactivate_site_secure is chosen because its ONLY logic
--       before the session check is nothing:
--       public._verify_management_session runs FIRST, before any input
--       validation or row lookup, so an invalid session can never reach the
--       UPDATE (and the random uuid matches no site anyway):
--         select public.deactivate_site_secure(
--           'invalid-token-for-negative-test',
--           gen_random_uuid());
--       Expected: ERROR 'Invalid or expired session' (raised by
--       _verify_management_session; see
--       docs/sql/sites-site-assignments-secure-rpc.sql). No row is changed.
--       Known risk: if the deployed function body had diverged (session
--       check no longer first), a different error could surface -- C-4b /
--       G-8 guard against that by verifying the session-check reference in
--       prosrc before the body.
--
--   [Production read-only check (browser; no writes)]
--     - Employee screen (index.html): login succeeds; sites list and
--       assignment views render.
--     - Admin screen (admin-app.html): sites management list renders. If
--       the site detail modal (openSiteModal) is opened as part of the
--       read-only check, it additionally exercises get_site_admin_secure
--       and list_site_assignments_admin_secure -- confirm HTTP 200 for
--       those too (opening the modal is a read-only view operation).
--     - Network: list_sites_secure = HTTP 200; list_site_assignments_secure
--       = HTTP 200; list_sites_admin_secure = HTTP 200 (where the screen
--       calls them); NO direct /rest/v1/sites or /rest/v1/site_assignments
--       read or write.
--     - Console: no red errors.
--     - NO write operation (create / update / deactivate / assignment
--       change) is performed.
--
--   [Write positive -- NOT performed by default]
--     - Creating or updating a real site / assignment just to test would
--       create a throwaway business row / change; do NOT do it. P-5 (write
--       RPC attributes / EXECUTE unchanged) plus the invalid-session
--       negative above stand in as the write-path evidence.
--     - The next genuine site create / update / assignment change
--       (performed in normal use) serves as the real positive check; if it
--       failed, evaluate ROLLBACK.
--     - If an explicit positive write test is ever wanted, it requires the
--       user's separate explicit approval first.
-- ============================================================


-- ============================================================
-- ROLLBACK (reference only -- NOT executed; requires the user's separate
--   explicit approval; NEVER run in the same session/flow as the body)
--   Re-creates the four policies EXACTLY as measured in the C-3 pre-check.
--   NOTE the roles: the site_assignments pair is TO public, the sites pair
--   is TO anon -- do NOT interchange them.
--   Policy layer ONLY: NO table privilege is granted back, NO RPC / RLS /
--   owner change. Re-confirm the current state (C-1..C-3) before using
--   this. WARNING: restoring these policies re-creates the latent allow-all
--   write paths this file removed -- if any write grant later reappeared
--   for anon / authenticated, direct INSERT / UPDATE would be open again.
--   Normally unnecessary: the application write path (the 5 SECURITY
--   DEFINER RPCs, owner postgres, FORCE RLS false) does not depend on these
--   policies.
-- ============================================================
-- BEGIN;
--
-- CREATE POLICY sa_update
-- ON public.site_assignments
-- AS PERMISSIVE
-- FOR UPDATE
-- TO public
-- USING (true);
--
-- CREATE POLICY sa_write
-- ON public.site_assignments
-- AS PERMISSIVE
-- FOR INSERT
-- TO public
-- WITH CHECK (true);
--
-- CREATE POLICY anon_can_insert_sites
-- ON public.sites
-- AS PERMISSIVE
-- FOR INSERT
-- TO anon
-- WITH CHECK (true);
--
-- CREATE POLICY anon_can_update_sites
-- ON public.sites
-- AS PERMISSIVE
-- FOR UPDATE
-- TO anon
-- USING (true)
-- WITH CHECK (true);
--
-- COMMIT;
-- ============================================================
