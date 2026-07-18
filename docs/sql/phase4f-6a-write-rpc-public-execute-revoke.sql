-- ============================================================
-- Phase 4-F-6-a: write/admin RPC PUBLIC EXECUTE revoke (32 functions)
--   Revoke the explicit PUBLIC EXECUTE grant from the 32 SECURITY DEFINER
--   write/admin RPCs listed in [SCOPE]. The Phase 2/3-era definition files
--   granted EXECUTE to anon / authenticated explicitly but never revoked the
--   PUBLIC EXECUTE that had also been granted explicitly, so PUBLIC EXECUTE
--   remains on all 32 (confirmed by the 2026-07-18 whole-schema read-only
--   survey run by the user). PUBLIC EXECUTE is redundant for the app (the
--   only client roles are anon / authenticated, which keep their OWN
--   explicit grants) and is removed as defense-in-depth: a future role
--   would otherwise silently inherit EXECUTE on every write RPC.
--   Same change class and structure as Phase 4-F-4-a (notices RPC PUBLIC
--   EXECUTE revoke) and the 2B-6 side step (create_machine_location_secure).
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - The EXECUTION BODY must be run exactly ONCE by the user (Supabase SQL
--     Editor, manual). DO NOT RE-RUN after success: a second run fails the
--     guard at G-3 (PUBLIC already revoked on the targets) by design
--     (fail-closed).
--   - DB execution is done by the user, manually, in the Supabase SQL
--     Editor. Claude Code CLI performs NO DB connection / NO SQL execution /
--     NO Supabase CLI / NO psql.
--   - Run order: PRE-CHECK (C-1..C-6) -> EXECUTION GUARD + BODY (single
--     transaction) -> POST-CHECK (P-1..P-4) -> SMOKE TEST -> ROLLBACK only
--     in an emergency, with separate explicit approval.
--
-- [WHY anon / authenticated ACCESS IS UNAFFECTED]
--   - has_function_privilege('anon', ...) can be true EITHER via an explicit
--     anon ACL entry OR via a PUBLIC entry. The 2026-07-18 survey confirmed
--     ALL 32 targets carry EXPLICIT anon and authenticated EXECUTE entries
--     in proacl (in addition to the explicit PUBLIC entry).
--   - REVOKE ... FROM PUBLIC removes ONLY the PUBLIC entry; the anon /
--     authenticated entries are untouched, so the effective EXECUTE for
--     both client roles is unchanged. The guard verifies the explicit
--     entries per function BEFORE the body (G-3) and the post-check proves
--     them unchanged after (P-2) -- both at the ACL level (aclexplode) and
--     at the effective level (has_function_privilege).
--
-- [SCOPE] (exactly 32 functions; the ONLY DB-changing statements are the
--   32 REVOKE EXECUTE ... FROM PUBLIC statements in the body)
--   machines (5):
--     create_machine_secure / update_machine_secure /
--     deactivate_machine_secure / create_machine_admin_secure /
--     update_machine_admin_secure
--   sites / site_assignments (5):
--     create_site_secure / update_site_secure / deactivate_site_secure /
--     set_site_assignment_secure / replace_site_assignments_secure
--   employees / genka_admins (4):
--     create_employee_secure / update_employee_secure /
--     create_genka_admin_secure / update_genka_admin_secure
--   materials (2): create_material_secure / deactivate_material_secure
--   rates (2): upsert_employee_rate_secure / upsert_unit_rate_secure
--   invoices (4): create_invoice_secure / update_invoice_secure /
--     reject_invoice_secure / restore_invoice_secure
--   site_budgets (4): upsert_site_budget_secure / update_site_budget_secure
--     / deactivate_site_budget_secure / restore_site_budget_secure
--   reports (3): create_report_secure / update_report_secure /
--     update_report_photo_secure
--   paid_leave (3): create_paid_leave_request_secure /
--     review_paid_leave_request_secure / save_paid_leave_grant_secure
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - The 4 session RPCs -- create_admin_session(uuid, text) /
--     revoke_admin_session(text) / create_employee_session(uuid, text) /
--     revoke_employee_session(text). They are the login/logout critical
--     path (called with the anon key BEFORE login) and are handled in a
--     SEPARATE step (Phase 4-F-6-b) with dedicated login/logout smoke.
--     They MUST NOT appear in this file's REVOKE list; the guard stops if
--     one is found in the target list (G-3) and the post-check proves their
--     PUBLIC EXECUTE unchanged (P-4).
--   - anon / authenticated EXECUTE grants (NO GRANT / NO REVOKE on them).
--   - Function definitions (no CREATE OR REPLACE / ALTER / DROP FUNCTION).
--   - Tables / views / policies / RLS / data (no DDL besides the REVOKEs,
--     no DML).
--   - front-end code.
--   - Positive write smoke is NOT performed (EXECUTE reachability for the
--     client roles is proven unchanged by P-2/P-3 instead).
--
-- [BASELINE] (real-DB measurements, Supabase SQL Editor, 2026-07-18 --
--   whole-schema survey + per-function pre-design check, all passed;
--   re-verify ALL of it in PRE-CHECK below)
--   - public schema SECURITY DEFINER functions: 78 total.
--   - PUBLIC EXECUTE effective true: 36 = these 32 targets + the 4 session
--     RPCs (exact set match confirmed). false: 42. Expected transition by
--     this file: 36 -> 4 (the session RPCs only).
--   - All 32 targets: plpgsql, owner postgres, SECURITY DEFINER, VOLATILE,
--     search_path=public, extensions, overload = 1, proacl NOT NULL,
--     explicit PUBLIC / anon / authenticated EXECUTE all present,
--     effective PUBLIC / anon / authenticated EXECUTE all true.
--   - default-ACL-derived PUBLIC: 0 (all 36 are explicit PUBLIC entries).
--   - The 3 re-created current versions match the repo definitions:
--     review_paid_leave_request_secure / save_paid_leave_grant_secure
--     (dual employee_sessions + admin_sessions inline verification;
--     docs/sql/paid-leave-admin-session-compatible-rpc.sql) and
--     upsert_site_budget_secure (docs/sql/site-budget-upsert-null-fix.sql).
--   - Result types (from the repo definitions, confirmed consistent with
--     the DB): see the per-function expected values in C-2 / G-3.
--
-- [STOP CONDITIONS] (if any is hit during PRE-CHECK, do NOT run the body;
--   stop & report -- do NOT guess or "fix" divergence)
--   - C-1: SECURITY DEFINER total <> 78 or PUBLIC-true total <> 36.
--   - C-2/C-2b: any target missing, overloaded, attribute/result-type
--     mismatch, proacl NULL, explicit PUBLIC absent (already revoked -> do
--     NOT re-run), explicit anon or authenticated absent (revoking PUBLIC
--     would break the app -> a separate GRANT design would come first), or
--     any effective EXECUTE false.
--   - C-3: any session RPC missing, PUBLIC-false, or lacking explicit
--     anon / authenticated entries.
--   - C-4: the PUBLIC-true set differs from "32 targets + 4 session RPCs"
--     (any row returned).
--   - C-5: any of the 3 re-created functions diverging from the repo
--     definitions (signature / result type / session-verification
--     references / overload).
--
-- [ROLLBACK] (see the commented section at the end -- reference only)
--   GRANT EXECUTE ... TO PUBLIC x 32. NORMALLY FORBIDDEN: use only if a
--   production failure is confirmed to be caused by this step AND the user
--   gives separate explicit approval. anon / authenticated grants are not
--   touched in either direction.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body.
-- ============================================================

-- C-1. whole-schema baseline.
--    Expected: security_definer_total = 78, public_execute_true_total = 36.
--    STOP if either differs (schema state drifted since the 2026-07-18
--    survey; reconcile first).
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

-- C-2. the 32 targets in detail.
--    Expected: 32 rows; each actual_signature non-NULL, language plpgsql,
--      owner postgres, security_definer true, volatility 'v', config
--      containing search_path=public, extensions, result_type equal to
--      expected_result, overload_count 1, proacl_is_null false, all three
--      explicit_* true, all three effective_* true.
--    STOP on any divergence (see STOP CONDITIONS).
with targets(fsig, fresult) as (values
  ('public.create_machine_secure(text, text, text, text, date, date, integer)', 'TABLE(id uuid)'),
  ('public.update_machine_secure(text, uuid, text, text, text, date, date, integer)', 'TABLE(id uuid)'),
  ('public.deactivate_machine_secure(text, uuid)', 'TABLE(id uuid)'),
  ('public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer)', 'TABLE(id uuid)'),
  ('public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer)', 'TABLE(id uuid)'),
  ('public.create_site_secure(text, text, text, date, date, uuid)', 'TABLE(id uuid)'),
  ('public.update_site_secure(text, uuid, text, text, date, date, uuid)', 'void'),
  ('public.deactivate_site_secure(text, uuid)', 'void'),
  ('public.set_site_assignment_secure(text, uuid, uuid, boolean)', 'void'),
  ('public.replace_site_assignments_secure(text, uuid, uuid[])', 'void'),
  ('public.create_employee_secure(text, text, text, text, uuid, boolean)', 'TABLE(id uuid, name text)'),
  ('public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)', 'void'),
  ('public.create_genka_admin_secure(text, text, text)', 'TABLE(id uuid, name text)'),
  ('public.update_genka_admin_secure(text, uuid, text, boolean, text)', 'void'),
  ('public.create_material_secure(text, text)', 'TABLE(id uuid)'),
  ('public.deactivate_material_secure(text, uuid)', 'TABLE(id uuid)'),
  ('public.upsert_employee_rate_secure(text, uuid, integer, date)', 'uuid'),
  ('public.upsert_unit_rate_secure(text, text, text, integer, text)', 'uuid'),
  ('public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text)', 'TABLE(id uuid)'),
  ('public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text)', 'void'),
  ('public.reject_invoice_secure(text, uuid)', 'void'),
  ('public.restore_invoice_secure(text, uuid)', 'void'),
  ('public.upsert_site_budget_secure(text, uuid, integer, integer, text)', 'TABLE(id uuid)'),
  ('public.update_site_budget_secure(text, uuid, uuid, integer, integer, text)', 'void'),
  ('public.deactivate_site_budget_secure(text, uuid)', 'void'),
  ('public.restore_site_budget_secure(text, uuid)', 'void'),
  ('public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)', 'TABLE(id uuid)'),
  ('public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)', 'void'),
  ('public.update_report_photo_secure(text, uuid, text[], integer)', 'void'),
  ('public.create_paid_leave_request_secure(text, date, text, text)', 'TABLE(id uuid)'),
  ('public.review_paid_leave_request_secure(text, uuid, text)', 'void'),
  ('public.save_paid_leave_grant_secure(text, uuid, integer, numeric)', 'void')
)
select
  t.fsig                        as expected_signature,
  t.fresult                     as expected_result,
  p.oid::regprocedure::text     as actual_signature,      -- NULL = missing target
  l.lanname                     as language,              -- expect plpgsql
  pg_get_userbyid(p.proowner)   as owner,                 -- expect postgres
  p.prosecdef                   as security_definer,      -- expect true
  p.provolatile                 as volatility,            -- expect 'v'
  p.proconfig                   as config,                -- expect search_path=public, extensions
  pg_get_function_result(p.oid) as result_type,           -- expect = expected_result
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

-- C-2b. aggregate over the same 32 targets (single row).
--    Expected: 32, 32, 32, 32, 32, 32, 32, 0, 0, 0, 0, 0.
with targets(fsig) as (values
  ('public.create_machine_secure(text, text, text, text, date, date, integer)'),
  ('public.update_machine_secure(text, uuid, text, text, text, date, date, integer)'),
  ('public.deactivate_machine_secure(text, uuid)'),
  ('public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer)'),
  ('public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer)'),
  ('public.create_site_secure(text, text, text, date, date, uuid)'),
  ('public.update_site_secure(text, uuid, text, text, date, date, uuid)'),
  ('public.deactivate_site_secure(text, uuid)'),
  ('public.set_site_assignment_secure(text, uuid, uuid, boolean)'),
  ('public.replace_site_assignments_secure(text, uuid, uuid[])'),
  ('public.create_employee_secure(text, text, text, text, uuid, boolean)'),
  ('public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)'),
  ('public.create_genka_admin_secure(text, text, text)'),
  ('public.update_genka_admin_secure(text, uuid, text, boolean, text)'),
  ('public.create_material_secure(text, text)'),
  ('public.deactivate_material_secure(text, uuid)'),
  ('public.upsert_employee_rate_secure(text, uuid, integer, date)'),
  ('public.upsert_unit_rate_secure(text, text, text, integer, text)'),
  ('public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text)'),
  ('public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text)'),
  ('public.reject_invoice_secure(text, uuid)'),
  ('public.restore_invoice_secure(text, uuid)'),
  ('public.upsert_site_budget_secure(text, uuid, integer, integer, text)'),
  ('public.update_site_budget_secure(text, uuid, uuid, integer, integer, text)'),
  ('public.deactivate_site_budget_secure(text, uuid)'),
  ('public.restore_site_budget_secure(text, uuid)'),
  ('public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)'),
  ('public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)'),
  ('public.update_report_photo_secure(text, uuid, text[], integer)'),
  ('public.create_paid_leave_request_secure(text, date, text, text)'),
  ('public.review_paid_leave_request_secure(text, uuid, text)'),
  ('public.save_paid_leave_grant_secure(text, uuid, integer, numeric)')
),
resolved as (
  select t.fsig, p.oid, p.proname, p.proacl, p.proowner, p.proconfig
  from targets t
  left join pg_proc p on p.oid = to_regprocedure(t.fsig)
)
select
  count(*) as target_function_count,                                                              -- 32
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))                                 as explicit_public_execute_count,        -- 32
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'anon' and a.privilege_type = 'EXECUTE'))                            as explicit_anon_execute_count,          -- 32
  count(*) filter (where oid is not null and exists (select 1 from aclexplode(proacl) a
           join pg_roles r on r.oid = a.grantee
           where r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE'))                   as explicit_authenticated_execute_count, -- 32
  count(*) filter (where oid is not null and exists (
           select 1 from aclexplode(coalesce(proacl, acldefault('f', proowner))) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))                                 as effective_public_execute_count,       -- 32
  count(*) filter (where oid is not null and has_function_privilege('anon', oid, 'EXECUTE'))      as effective_anon_execute_count,         -- 32
  count(*) filter (where oid is not null and has_function_privilege('authenticated', oid, 'EXECUTE')) as effective_authenticated_execute_count, -- 32
  count(*) filter (where oid is not null and pg_get_userbyid(proowner) <> 'postgres')             as non_postgres_owner_count,             -- 0
  count(*) filter (where oid is not null and (proconfig is null
           or array_to_string(proconfig, ',') not like '%search_path=%'))                         as unfixed_search_path_count,            -- 0
  count(*) filter (where oid is not null and (select count(*) from pg_proc p2
           join pg_namespace n2 on n2.oid = p2.pronamespace
           where n2.nspname = 'public' and p2.proname = resolved.proname) <> 1)                   as unexpected_overload_count,            -- 0
  count(*) filter (where oid is null)                                                             as missing_target_count,                 -- 0
  count(*) filter (where proname in ('create_admin_session','revoke_admin_session',
           'create_employee_session','revoke_employee_session'))                                  as session_function_accidentally_included_count  -- 0
from resolved;

-- C-3. the 4 session RPCs are OUT OF SCOPE and currently PUBLIC-true.
--    Expected: 4 rows, fn_exists true, effective_public_execute true,
--      explicit_anon_execute true, explicit_authenticated_execute true.
--    (They stay PUBLIC-true through this step; Phase 4-F-6-b handles them.)
with sess(fsig) as (values
  ('public.create_admin_session(uuid, text)'),
  ('public.revoke_admin_session(text)'),
  ('public.create_employee_session(uuid, text)'),
  ('public.revoke_employee_session(text)'))
select
  t.fsig,
  (p.oid is not null) as fn_exists,
  exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
           where a.grantee = 0 and a.privilege_type = 'EXECUTE') as effective_public_execute,
  exists (select 1 from aclexplode(p.proacl) a join pg_roles r on r.oid = a.grantee
           where r.rolname = 'anon' and a.privilege_type = 'EXECUTE') as explicit_anon_execute,
  exists (select 1 from aclexplode(p.proacl) a join pg_roles r on r.oid = a.grantee
           where r.rolname = 'authenticated' and a.privilege_type = 'EXECUTE') as explicit_authenticated_execute
from sess t
left join pg_proc p on p.oid = to_regprocedure(t.fsig)
order by t.fsig;

-- C-4. set equality: the whole-schema PUBLIC-true set (36) equals exactly
--    "32 targets + 4 session RPCs". Expected: 0 rows.
--    STOP if any row is returned (an unexpected PUBLIC-true function, or a
--    listed function missing / already-PUBLIC-false).
with expected(fsig) as (values
  ('public.create_machine_secure(text, text, text, text, date, date, integer)'),
  ('public.update_machine_secure(text, uuid, text, text, text, date, date, integer)'),
  ('public.deactivate_machine_secure(text, uuid)'),
  ('public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer)'),
  ('public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer)'),
  ('public.create_site_secure(text, text, text, date, date, uuid)'),
  ('public.update_site_secure(text, uuid, text, text, date, date, uuid)'),
  ('public.deactivate_site_secure(text, uuid)'),
  ('public.set_site_assignment_secure(text, uuid, uuid, boolean)'),
  ('public.replace_site_assignments_secure(text, uuid, uuid[])'),
  ('public.create_employee_secure(text, text, text, text, uuid, boolean)'),
  ('public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)'),
  ('public.create_genka_admin_secure(text, text, text)'),
  ('public.update_genka_admin_secure(text, uuid, text, boolean, text)'),
  ('public.create_material_secure(text, text)'),
  ('public.deactivate_material_secure(text, uuid)'),
  ('public.upsert_employee_rate_secure(text, uuid, integer, date)'),
  ('public.upsert_unit_rate_secure(text, text, text, integer, text)'),
  ('public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text)'),
  ('public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text)'),
  ('public.reject_invoice_secure(text, uuid)'),
  ('public.restore_invoice_secure(text, uuid)'),
  ('public.upsert_site_budget_secure(text, uuid, integer, integer, text)'),
  ('public.update_site_budget_secure(text, uuid, uuid, integer, integer, text)'),
  ('public.deactivate_site_budget_secure(text, uuid)'),
  ('public.restore_site_budget_secure(text, uuid)'),
  ('public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)'),
  ('public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)'),
  ('public.update_report_photo_secure(text, uuid, text[], integer)'),
  ('public.create_paid_leave_request_secure(text, date, text, text)'),
  ('public.review_paid_leave_request_secure(text, uuid, text)'),
  ('public.save_paid_leave_grant_secure(text, uuid, integer, numeric)'),
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

-- C-5. the 3 re-created current versions match the repo definitions.
--    Expected: 3 rows --
--      review_paid_leave_request_secure(text, uuid, text) -> void,
--        references employee_sessions AND admin_sessions (dual inline),
--        uses_mgmt_session_helper false
--      save_paid_leave_grant_secure(text, uuid, integer, numeric) -> void,
--        same dual inline verification
--      upsert_site_budget_secure(text, uuid, integer, integer, text)
--        -> TABLE(id uuid), references admin_sessions
--      all: SECURITY DEFINER, owner postgres, fixed search_path,
--        overload_count 1.
select
  p.oid::regprocedure::text                 as function_signature,
  pg_get_function_identity_arguments(p.oid) as args,
  pg_get_function_result(p.oid)             as result_type,
  p.prosecdef                               as security_definer,
  p.provolatile                             as volatility,
  pg_get_userbyid(p.proowner)               as owner,
  p.proconfig                               as config,
  strpos(p.prosrc, '_verify_management_session') > 0 as uses_mgmt_session_helper,
  strpos(p.prosrc, 'employee_sessions') > 0 as references_employee_sessions,
  strpos(p.prosrc, 'admin_sessions') > 0    as references_admin_sessions,
  (select count(*) from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
    where n2.nspname = 'public' and p2.proname = p.proname) as overload_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('review_paid_leave_request_secure',
                    'save_paid_leave_grant_secure',
                    'upsert_site_budget_secure')
order by p.proname;

-- C-6. front-end / repository preconditions (NOT checkable from SQL;
--    confirmed from the repo, main 7578c14 -- recorded here as facts).
--    - All 32 targets are called by the front-end ONLY with a session token
--      obtained after login (anon key + explicit anon/authenticated
--      EXECUTE); no code path depends on PUBLIC EXECUTE.
--    - The 4 session RPCs are called with the anon key BEFORE login
--      (index.html:909 / admin-app.html:306 / genka-app.html:504 for
--      create; index.html:921 / admin-app.html:319 / genka-app.html:521
--      for revoke) -- they are OUT OF SCOPE here (Phase 4-F-6-b).
--    - No application or SQL code grants PUBLIC EXECUTE at runtime.


-- ============================================================
-- EXECUTION GUARD + BODY (ONE transaction; run ONLY after C-1..C-6 passed)
--   The GUARD (DO block) is READ-ONLY and runs INSIDE the same transaction
--   as the body: if any expectation fails, it RAISEs, the transaction
--   aborts, and NOTHING is changed (fail-closed). A second run fails the
--   guard at G-3 (explicit PUBLIC already absent on a target) before any
--   statement that would modify state -- the body must NOT be re-run after
--   success.
--   The ONLY DB-changing statements are the 32 REVOKE EXECUTE ... FROM
--   PUBLIC statements. No GRANT, no CREATE / ALTER / DROP FUNCTION, no
--   table / view / policy DDL, no DML, and NO statement touches the 4
--   session RPCs.
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

  -- G-2. whole-schema baseline: PUBLIC EXECUTE effective true = 36.
  select count(*) into v_cnt
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef = true
    and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                 where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_cnt <> 36 then
    raise exception 'GUARD STOP (G-2): PUBLIC EXECUTE true total = % (expected 36) -- schema drifted (or this body already ran); reconcile, do NOT re-run blindly', v_cnt;
  end if;

  -- G-3. each of the 32 targets matches the measured baseline EXACTLY.
  --      Includes the session-RPC exclusion check: a session function name
  --      in this list would be a design error -> STOP.
  --      An absent explicit PUBLIC entry means the body already ran (or
  --      someone revoked it) -> STOP, do NOT re-run.
  --      An absent explicit anon / authenticated entry means the REVOKE
  --      would cut off the app -> STOP (separate GRANT design first).
  for rec in
    select t.fname, t.fsig, t.fresult
    from (values
      ('create_machine_secure', 'public.create_machine_secure(text, text, text, text, date, date, integer)', 'TABLE(id uuid)'),
      ('update_machine_secure', 'public.update_machine_secure(text, uuid, text, text, text, date, date, integer)', 'TABLE(id uuid)'),
      ('deactivate_machine_secure', 'public.deactivate_machine_secure(text, uuid)', 'TABLE(id uuid)'),
      ('create_machine_admin_secure', 'public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer)', 'TABLE(id uuid)'),
      ('update_machine_admin_secure', 'public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer)', 'TABLE(id uuid)'),
      ('create_site_secure', 'public.create_site_secure(text, text, text, date, date, uuid)', 'TABLE(id uuid)'),
      ('update_site_secure', 'public.update_site_secure(text, uuid, text, text, date, date, uuid)', 'void'),
      ('deactivate_site_secure', 'public.deactivate_site_secure(text, uuid)', 'void'),
      ('set_site_assignment_secure', 'public.set_site_assignment_secure(text, uuid, uuid, boolean)', 'void'),
      ('replace_site_assignments_secure', 'public.replace_site_assignments_secure(text, uuid, uuid[])', 'void'),
      ('create_employee_secure', 'public.create_employee_secure(text, text, text, text, uuid, boolean)', 'TABLE(id uuid, name text)'),
      ('update_employee_secure', 'public.update_employee_secure(text, uuid, text, text, boolean, uuid, text)', 'void'),
      ('create_genka_admin_secure', 'public.create_genka_admin_secure(text, text, text)', 'TABLE(id uuid, name text)'),
      ('update_genka_admin_secure', 'public.update_genka_admin_secure(text, uuid, text, boolean, text)', 'void'),
      ('create_material_secure', 'public.create_material_secure(text, text)', 'TABLE(id uuid)'),
      ('deactivate_material_secure', 'public.deactivate_material_secure(text, uuid)', 'TABLE(id uuid)'),
      ('upsert_employee_rate_secure', 'public.upsert_employee_rate_secure(text, uuid, integer, date)', 'uuid'),
      ('upsert_unit_rate_secure', 'public.upsert_unit_rate_secure(text, text, text, integer, text)', 'uuid'),
      ('create_invoice_secure', 'public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text)', 'TABLE(id uuid)'),
      ('update_invoice_secure', 'public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text)', 'void'),
      ('reject_invoice_secure', 'public.reject_invoice_secure(text, uuid)', 'void'),
      ('restore_invoice_secure', 'public.restore_invoice_secure(text, uuid)', 'void'),
      ('upsert_site_budget_secure', 'public.upsert_site_budget_secure(text, uuid, integer, integer, text)', 'TABLE(id uuid)'),
      ('update_site_budget_secure', 'public.update_site_budget_secure(text, uuid, uuid, integer, integer, text)', 'void'),
      ('deactivate_site_budget_secure', 'public.deactivate_site_budget_secure(text, uuid)', 'void'),
      ('restore_site_budget_secure', 'public.restore_site_budget_secure(text, uuid)', 'void'),
      ('create_report_secure', 'public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)', 'TABLE(id uuid)'),
      ('update_report_secure', 'public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text)', 'void'),
      ('update_report_photo_secure', 'public.update_report_photo_secure(text, uuid, text[], integer)', 'void'),
      ('create_paid_leave_request_secure', 'public.create_paid_leave_request_secure(text, date, text, text)', 'TABLE(id uuid)'),
      ('review_paid_leave_request_secure', 'public.review_paid_leave_request_secure(text, uuid, text)', 'void'),
      ('save_paid_leave_grant_secure', 'public.save_paid_leave_grant_secure(text, uuid, integer, numeric)', 'void')
    ) as t(fname, fsig, fresult)
  loop
    if rec.fname in ('create_admin_session', 'revoke_admin_session',
                     'create_employee_session', 'revoke_employee_session') then
      raise exception 'GUARD STOP (G-3): session RPC % is in the 6-a target list -- it belongs to Phase 4-F-6-b; design error, do NOT run', rec.fname;
    end if;
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
      raise exception 'GUARD STOP (G-3): % lacks the EXPLICIT anon EXECUTE entry -- revoking PUBLIC would cut off the app; STOP (a GRANT design must come first)', rec.fname;
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

  -- G-4. the 4 session RPCs exist, keep PUBLIC-true, and carry explicit
  --      anon / authenticated entries (they are NOT touched by this body).
  --      Set equality follows: G-3 proved the 32 targets are PUBLIC-true,
  --      G-4 proves the 4 session RPCs are PUBLIC-true, and G-2 proved the
  --      whole-schema PUBLIC-true total is exactly 36 -- so those 36
  --      distinct functions ARE the whole PUBLIC-true set (no unexpected
  --      member can exist).
  for rec in
    select t.fsig
    from (values
      ('public.create_admin_session(uuid, text)'),
      ('public.revoke_admin_session(text)'),
      ('public.create_employee_session(uuid, text)'),
      ('public.revoke_employee_session(text)')
    ) as t(fsig)
  loop
    if to_regprocedure(rec.fsig) is null then
      raise exception 'GUARD STOP (G-4): session RPC % is missing', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p, aclexplode(p.proacl) a
    where p.oid = to_regprocedure(rec.fsig)
      and a.grantee = 0 and a.privilege_type = 'EXECUTE';
    if v_cnt = 0 then
      raise exception 'GUARD STOP (G-4): session RPC % has no explicit PUBLIC EXECUTE (expected true until Phase 4-F-6-b) -- baseline diverged', rec.fsig;
    end if;
    select count(*) into v_cnt
    from pg_proc p, aclexplode(p.proacl) a
    join pg_roles r on r.oid = a.grantee
    where p.oid = to_regprocedure(rec.fsig)
      and r.rolname in ('anon', 'authenticated') and a.privilege_type = 'EXECUTE';
    if v_cnt < 2 then
      raise exception 'GUARD STOP (G-4): session RPC % lacks explicit anon/authenticated EXECUTE entries', rec.fsig;
    end if;
  end loop;

  raise notice 'GUARD OK: 32 targets + 4 session RPCs match the measured baseline; proceeding to 32 x REVOKE EXECUTE FROM PUBLIC';
end
$guard$;

-- BODY (EXACTLY 32 DB changes: REVOKE EXECUTE ... FROM PUBLIC only.
-- anon / authenticated grants are NOT touched. The 4 session RPCs are NOT
-- in this list.)

REVOKE EXECUTE ON FUNCTION public.create_machine_secure(text, text, text, text, date, date, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_machine_secure(text, uuid, text, text, text, date, date, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.deactivate_machine_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_site_secure(text, text, text, date, date, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_site_secure(text, uuid, text, text, date, date, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.deactivate_site_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_site_assignment_secure(text, uuid, uuid, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.replace_site_assignments_secure(text, uuid, uuid[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_employee_secure(text, text, text, text, uuid, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_employee_secure(text, uuid, text, text, boolean, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_genka_admin_secure(text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_genka_admin_secure(text, uuid, text, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_material_secure(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.deactivate_material_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_employee_rate_secure(text, uuid, integer, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_unit_rate_secure(text, text, text, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.reject_invoice_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.restore_invoice_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_site_budget_secure(text, uuid, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_site_budget_secure(text, uuid, uuid, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.deactivate_site_budget_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.restore_site_budget_secure(text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_report_photo_secure(text, uuid, text[], integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_paid_leave_request_secure(text, date, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.review_paid_leave_request_secure(text, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.save_paid_leave_grant_secure(text, uuid, integer, numeric) FROM PUBLIC;

COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- P-1. whole-schema totals after the body.
--    Expected: security_definer_total = 78 (unchanged),
--      public_execute_true_total = 4 (was 36; exactly -32).
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

-- P-1b. the remaining PUBLIC-true functions are EXACTLY the 4 session RPCs.
--    Expected: 4 rows -- create_admin_session(uuid, text) /
--      revoke_admin_session(text) / create_employee_session(uuid, text) /
--      revoke_employee_session(text); nothing else.
select p.oid::regprocedure::text as still_public_true
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef = true
  and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               where a.grantee = 0 and a.privilege_type = 'EXECUTE')
order by 1;

-- P-2. the 32 targets after the body -- re-run the C-2 query UNCHANGED
--    (same 32-row VALUES list; copy it from C-2).
--    Expected differences vs C-2: explicit_public_execute = false and
--      effective_public_execute = false for ALL 32.
--    Expected UNCHANGED vs C-2: everything else -- language / owner /
--      security_definer / volatility / config / result_type /
--      overload_count 1 / proacl_is_null false /
--      explicit_anon_execute true / explicit_authenticated_execute true /
--      effective_anon_execute true / effective_authenticated_execute true.

-- P-3. aggregate -- re-run the C-2b query UNCHANGED.
--    Expected: 32, 0, 32, 32, 0, 32, 32, 0, 0, 0, 0, 0
--    (public counts drop to 0; anon / authenticated counts stay 32).

-- P-4. session RPCs unchanged -- re-run the C-3 query UNCHANGED.
--    Expected: identical output to C-3 (4 rows, effective_public_execute
--      still true, explicit anon / authenticated still true).


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   [RPC negative -- invalid session is rejected exactly as before]
--     - The revoke changes ONLY who may call; the in-function session
--       verification is untouched. Confirm the behaviour is unchanged with
--       dummy values (no real token / no real UUID; nothing is persisted --
--       the functions raise BEFORE any DML).
--     - IMPORTANT: run the two statements SEPARATELY (one per SQL Editor
--       run). Each is EXPECTED to raise, so running them as one batch
--       would abort at the first error and leave the second unexecuted.
--       Record a per-statement PASS/FAIL.
--         -- (1) run alone:
--         select * from public.deactivate_machine_secure(
--           'invalid-token-for-negative-test', gen_random_uuid());
--         -- (2) run alone:
--         select public.deactivate_site_secure(
--           'invalid-token-for-negative-test', gen_random_uuid());
--       Expected: ERROR P0001 'Invalid or expired session' for both (raised
--       by public._verify_management_session before any input validation or
--       row lookup). PASS only on that exact error; a success, or any other
--       error, is a FAIL -> stop and report.
--     - Positive write smoke is NOT performed: the client roles' EXECUTE is
--       proven unchanged by P-2/P-3 (explicit + effective), so behaviour
--       for the app cannot have changed.
--
--   [Production read-only check (browser; no writes)]
--     - index.html / admin-app.html / genka-app.html: log in normally (the
--       login path itself is untouched by this step -- session RPCs keep
--       PUBLIC until Phase 4-F-6-b), then confirm the main lists and detail
--       views render on each screen.
--     - Network: the related read RPCs return HTTP 200; no direct REST
--       access to tables; no unexpected 401 / 403 on any RPC call.
--     - Console: no red errors.
--     - Do NOT create / update / delete any business data.
--     - Full login/logout verification is deferred to Phase 4-F-6-b (the
--       session-RPC step); here a normal login session is sufficient.
-- ============================================================


-- ============================================================
-- EMERGENCY ROLLBACK (reference only -- NOT executed; NORMALLY FORBIDDEN.
--   Use ONLY if a production failure is confirmed to be caused by this
--   step AND the user gives separate explicit approval. This restores the
--   explicit PUBLIC EXECUTE entries exactly as measured in C-2; it does
--   NOT touch the anon / authenticated grants in either direction.
--   WARNING: it re-opens EXECUTE to every present and future role.)
-- ============================================================
-- BEGIN;
-- GRANT EXECUTE ON FUNCTION public.create_machine_secure(text, text, text, text, date, date, integer) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_machine_secure(text, uuid, text, text, text, date, date, integer) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.deactivate_machine_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_machine_admin_secure(text, text, uuid, boolean, text, text, date, date, integer) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_machine_admin_secure(text, uuid, text, uuid, boolean, text, text, date, date, integer) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_site_secure(text, text, text, date, date, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_site_secure(text, uuid, text, text, date, date, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.deactivate_site_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.set_site_assignment_secure(text, uuid, uuid, boolean) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.replace_site_assignments_secure(text, uuid, uuid[]) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_employee_secure(text, text, text, text, uuid, boolean) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_employee_secure(text, uuid, text, text, boolean, uuid, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_genka_admin_secure(text, text, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_genka_admin_secure(text, uuid, text, boolean, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_material_secure(text, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.deactivate_material_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.upsert_employee_rate_secure(text, uuid, integer, date) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.upsert_unit_rate_secure(text, text, text, integer, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_invoice_secure(text, date, uuid, text, text, integer, boolean, text, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_invoice_secure(text, uuid, date, uuid, text, text, integer, boolean, text, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.reject_invoice_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.restore_invoice_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.upsert_site_budget_secure(text, uuid, integer, integer, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_site_budget_secure(text, uuid, uuid, integer, integer, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.deactivate_site_budget_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.restore_site_budget_secure(text, uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_report_secure(text, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_report_secure(text, uuid, date, uuid[], uuid[], time without time zone, time without time zone, text, integer, integer, jsonb, text, jsonb, uuid[], jsonb, integer, integer, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.update_report_photo_secure(text, uuid, text[], integer) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.create_paid_leave_request_secure(text, date, text, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.review_paid_leave_request_secure(text, uuid, text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.save_paid_leave_grant_secure(text, uuid, integer, numeric) TO PUBLIC;
-- COMMIT;
-- ============================================================
