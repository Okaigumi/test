-- ============================================================
-- Phase 4-F-2A: existing public tables - cleanup of residual extra (non-CRUD)
--   direct privileges for anon / authenticated
--   (REVOKE TRUNCATE / REFERENCES / TRIGGER / MAINTAIN)
-- ============================================================
-- [STATUS] EXECUTED (2026-07-09)
--   - Manually executed by the user in the Supabase SQL Editor.
--   - EXECUTION BODY (all 15 statements) returned "Success. No rows returned".
--   - Pre-checks A-0 / A / A-2 / A-3 / A-4 / A-5 all passed.
--   - Post-checks G / G-2 / G-3 all passed:
--       * TRUNCATE / REFERENCES / TRIGGER / MAINTAIN are all false on all 15
--         target tables for anon / authenticated.
--       * SELECT / INSERT / UPDATE / DELETE unchanged from the A-4 pre-snapshot.
--   - DB execution done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All checks (pre / post) were run manually by the user in
--     the Supabase SQL Editor.
--   - Recorded in docs/db-migrations.md (2026-07-09 Phase 4-F-2A section).
--
-- [PURPOSE]
--   Remove the residual non-CRUD "extra" privileges (TRUNCATE / REFERENCES /
--   TRIGGER / MAINTAIN) still held by anon / authenticated on EXISTING public
--   tables. These are leftovers of Supabase's PG17 default GRANT ALL and are not
--   used by the app (reads go through direct SELECT or secure read RPCs; writes go
--   through secure RPCs). This mirrors the earlier cross-cutting cleanups
--   (phase4c-5 reports T/R/T, phase4d-4 financial T/R/T, phase4e-1 / phase4e-2
--   MAINTAIN) and extends them to the remaining existing tables.
--
--   NOTE ON RELATION TO PHASE 4-F-1:
--     - Phase 4-F-1 changed DEFAULT privileges for FUTURE tables (owner postgres,
--       ALTER DEFAULT PRIVILEGES). It did NOT touch existing tables.
--     - Phase 4-F-2A (this file) targets EXISTING tables' direct grants
--       (pg_class.relacl) only. Different objects, different mechanism.
--
--   NOTE: MAINTAIN is a table-level maintenance privilege added in PostgreSQL 17
--         (VACUUM / ANALYZE / CLUSTER / REINDEX / REFRESH MATERIALIZED VIEW /
--         LOCK TABLE). The app never issues these, so revoking it is a no-op for
--         the app. TRUNCATE / REFERENCES / TRIGGER are likewise unused by the app.
--
-- [SCOPE]
--   Object type : EXISTING public tables' direct grants (pg_class.relacl) only.
--   Schema      : public only.
--   Grantees    : anon, authenticated ONLY.
--   Privileges  : TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ONLY.
--   Target tables (15 total):
--     Batch 1 (REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) - 13 tables:
--       admin_sessions, companies, company_categories, employee_sessions,
--       machine_locations, machines, materials, paid_leave_grants,
--       paid_leave_requests, site_assignments, site_categories, sites,
--       subcontractors
--     Batch 2 (REVOKE MAINTAIN only) - 2 tables:
--       notices, reports
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - SELECT / INSERT / UPDATE / DELETE (never listed in any REVOKE below).
--     NOTE: admin_sessions / employee_sessions STILL hold INSERT / SELECT / UPDATE
--           for anon / authenticated (confirmed by introspection). Phase 4-F-2A
--           does NOT touch those; they are handled carefully in a LATER, separate
--           step. This file removes ONLY the non-CRUD extras on those two tables.
--   - RLS / policies (no DROP POLICY here; stale policy cleanup is Phase 4-F-3).
--   - RPC definitions / EXECUTE grants / SECURITY DEFINER.
--   - HTML / JS / auth / PIN logic.
--   - default privileges (pg_default_acl) - that was Phase 4-F-1 (owner postgres);
--     owner supabase_admin default privileges remain a separate backlog (4-F-1b).
--   - employees / genka_admins (already handled: column-restricted SELECT +
--     MAINTAIN revoked in Phase 4-E-1).
--   - financial 4 tables (invoices / site_budgets / unit_rates / employee_rates):
--     already clean (Phase 4-D-4 T/R/T + Phase 4-E-2 MAINTAIN); not included.
--   - service_role / postgres(owner) privileges.
--   - PUBLIC role (checked informationally in A-5, but not a target).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - A-0: server is PostgreSQL 16 or earlier -> STOP (MAINTAIN keyword invalid).
--   - A-2: a public table OUTSIDE the 15 targets holds TRUNCATE/REFERENCES/TRIGGER/
--          MAINTAIN for anon / authenticated -> STOP (target set incomplete; re-scope).
--   - Post-check G: any of SELECT / INSERT / UPDATE / DELETE changed vs A-4 (pre) on
--          any target table/role -> STOP and investigate (should be impossible given
--          the REVOKE text lists only the 4 non-CRUD privileges; guard against typos).
--   - Post-check G: TRUNCATE/REFERENCES/TRIGGER/MAINTAIN not false where expected -> STOP.
--
-- [ROLLBACK] (only if needed; normally NOT used)
--   See the rollback section at the end (commented out). These are originally
--   unneeded privileges, so normally do NOT restore.
-- ============================================================


-- ============================================================
-- Pre-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- A-0. PostgreSQL version check (guard for the MAINTAIN keyword; PG17+ only)
--    Expected: server_version_num >= 170000. STOP if PostgreSQL 16 or earlier.
select version()                                       as pg_version,
       current_setting('server_version_num')::int      as server_version_num,
       (current_setting('server_version_num')::int >= 170000) as is_pg17_or_newer;

-- A. Table-level 8-privilege matrix (anon / authenticated on the 15 target tables)
--    Records the full pre-state. Used together with A-4 to prove CRUD is unchanged.
--    Expected (targets): can_truncate/can_references/can_trigger/can_maintain reflect
--    the residuals to be removed. can_select/insert/update/delete vary per table and
--    are NOT changed by this file.
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger,
  has_table_privilege(role_name, object_name, 'MAINTAIN')   as can_maintain
from (
  values
    ('anon',          'public.admin_sessions'),
    ('authenticated', 'public.admin_sessions'),
    ('anon',          'public.companies'),
    ('authenticated', 'public.companies'),
    ('anon',          'public.company_categories'),
    ('authenticated', 'public.company_categories'),
    ('anon',          'public.employee_sessions'),
    ('authenticated', 'public.employee_sessions'),
    ('anon',          'public.machine_locations'),
    ('authenticated', 'public.machine_locations'),
    ('anon',          'public.machines'),
    ('authenticated', 'public.machines'),
    ('anon',          'public.materials'),
    ('authenticated', 'public.materials'),
    ('anon',          'public.notices'),
    ('authenticated', 'public.notices'),
    ('anon',          'public.paid_leave_grants'),
    ('authenticated', 'public.paid_leave_grants'),
    ('anon',          'public.paid_leave_requests'),
    ('authenticated', 'public.paid_leave_requests'),
    ('anon',          'public.reports'),
    ('authenticated', 'public.reports'),
    ('anon',          'public.site_assignments'),
    ('authenticated', 'public.site_assignments'),
    ('anon',          'public.site_categories'),
    ('authenticated', 'public.site_categories'),
    ('anon',          'public.sites'),
    ('authenticated', 'public.sites'),
    ('anon',          'public.subcontractors'),
    ('authenticated', 'public.subcontractors')
) as v(role_name, object_name)
order by object_name, role_name;

-- A-2. Completeness guard: any public table OUTSIDE the 15 targets that still grants
--    TRUNCATE / REFERENCES / TRIGGER / MAINTAIN to anon / authenticated.
--    Expected: 0 rows. STOP if any row is returned (the target set is incomplete;
--    re-scope before running the body).
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relkind = 'r'
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
  and  acl.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')
  and  c.relname not in (
        'admin_sessions', 'companies', 'company_categories', 'employee_sessions',
        'machine_locations', 'machines', 'materials', 'notices',
        'paid_leave_grants', 'paid_leave_requests', 'reports', 'site_assignments',
        'site_categories', 'sites', 'subcontractors'
       )
order  by table_name, grantee, acl.privilege_type;

-- A-3. Presence check: the privileges we intend to REVOKE actually exist on the
--    targets (so the REVOKE is meaningful, not a blind no-op).
--    Expected (Batch 1 - 13 tables): rows for TRUNCATE / REFERENCES / TRIGGER / MAINTAIN.
--    Expected (Batch 2 - notices / reports): rows for MAINTAIN only.
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relkind = 'r'
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
  and  acl.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')
  and  c.relname in (
        'admin_sessions', 'companies', 'company_categories', 'employee_sessions',
        'machine_locations', 'machines', 'materials', 'notices',
        'paid_leave_grants', 'paid_leave_requests', 'reports', 'site_assignments',
        'site_categories', 'sites', 'subcontractors'
       )
order  by table_name, grantee, acl.privilege_type;

-- A-4. CRUD pre-state snapshot (SELECT / INSERT / UPDATE / DELETE only).
--    Record these values now; POST-CHECK G must show them UNCHANGED. This is the
--    explicit guard that Phase 4-F-2A never touches CRUD.
--    NOTE: admin_sessions / employee_sessions are expected to still show some of
--    SELECT / INSERT / UPDATE = true here; that is intentional (handled later).
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT') as can_select,
  has_table_privilege(role_name, object_name, 'INSERT') as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE') as can_update,
  has_table_privilege(role_name, object_name, 'DELETE') as can_delete
from (
  values
    ('anon',          'public.admin_sessions'),
    ('authenticated', 'public.admin_sessions'),
    ('anon',          'public.companies'),
    ('authenticated', 'public.companies'),
    ('anon',          'public.company_categories'),
    ('authenticated', 'public.company_categories'),
    ('anon',          'public.employee_sessions'),
    ('authenticated', 'public.employee_sessions'),
    ('anon',          'public.machine_locations'),
    ('authenticated', 'public.machine_locations'),
    ('anon',          'public.machines'),
    ('authenticated', 'public.machines'),
    ('anon',          'public.materials'),
    ('authenticated', 'public.materials'),
    ('anon',          'public.notices'),
    ('authenticated', 'public.notices'),
    ('anon',          'public.paid_leave_grants'),
    ('authenticated', 'public.paid_leave_grants'),
    ('anon',          'public.paid_leave_requests'),
    ('authenticated', 'public.paid_leave_requests'),
    ('anon',          'public.reports'),
    ('authenticated', 'public.reports'),
    ('anon',          'public.site_assignments'),
    ('authenticated', 'public.site_assignments'),
    ('anon',          'public.site_categories'),
    ('authenticated', 'public.site_categories'),
    ('anon',          'public.sites'),
    ('authenticated', 'public.sites'),
    ('anon',          'public.subcontractors'),
    ('authenticated', 'public.subcontractors')
) as v(role_name, object_name)
order by object_name, role_name;

-- A-5. PUBLIC role check (informational; not a target).
--    Shows whether PUBLIC holds any of the 4 extra privileges on the targets.
--    Not a stop condition for this file (scope is anon / authenticated), but useful
--    to know if a later PUBLIC-scoped cleanup is warranted.
select c.relname                        as table_name,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relkind = 'r'
  and  acl.grantee = 0            -- 0 = PUBLIC pseudo-role
  and  acl.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')
  and  c.relname in (
        'admin_sessions', 'companies', 'company_categories', 'employee_sessions',
        'machine_locations', 'machines', 'materials', 'notices',
        'paid_leave_grants', 'paid_leave_requests', 'reports', 'site_assignments',
        'site_categories', 'sites', 'subcontractors'
       )
order  by table_name, acl.privilege_type;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the first place that modifies DB state. Run only after the
--         pre-checks A-0 / A-2 pass (no STOP hit) and A / A-3 / A-4 are recorded.
--   NOTE: 15 statements total. One table per statement. Tables in alphabetical order.
--   NOTE: Batch 1 (13 tables) revokes TRUNCATE, REFERENCES, TRIGGER, MAINTAIN.
--         Batch 2 (2 tables: notices, reports) revokes MAINTAIN only.
--   NOTE: SELECT / INSERT / UPDATE / DELETE are NEVER listed below.
-- ============================================================

-- Batch 1: REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN (13 tables)
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.admin_sessions      FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.companies           FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.company_categories  FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.employee_sessions   FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.machine_locations   FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.machines            FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.materials           FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.paid_leave_grants   FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.paid_leave_requests FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.site_assignments    FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.site_categories     FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.sites               FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.subcontractors      FROM anon, authenticated;

-- Batch 2: REVOKE MAINTAIN only (2 tables)
REVOKE MAINTAIN ON TABLE public.notices FROM anon, authenticated;
REVOKE MAINTAIN ON TABLE public.reports FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. Table-level 8-privilege matrix (same shape as A).
--    Expected:
--      - TRUNCATE / REFERENCES / TRIGGER / MAINTAIN = false on all 15 targets.
--      - SELECT / INSERT / UPDATE / DELETE = UNCHANGED vs A-4 (compare row by row).
--    STOP if any CRUD value differs from A-4, or if any of the 4 extras is still true.
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger,
  has_table_privilege(role_name, object_name, 'MAINTAIN')   as can_maintain
from (
  values
    ('anon',          'public.admin_sessions'),
    ('authenticated', 'public.admin_sessions'),
    ('anon',          'public.companies'),
    ('authenticated', 'public.companies'),
    ('anon',          'public.company_categories'),
    ('authenticated', 'public.company_categories'),
    ('anon',          'public.employee_sessions'),
    ('authenticated', 'public.employee_sessions'),
    ('anon',          'public.machine_locations'),
    ('authenticated', 'public.machine_locations'),
    ('anon',          'public.machines'),
    ('authenticated', 'public.machines'),
    ('anon',          'public.materials'),
    ('authenticated', 'public.materials'),
    ('anon',          'public.notices'),
    ('authenticated', 'public.notices'),
    ('anon',          'public.paid_leave_grants'),
    ('authenticated', 'public.paid_leave_grants'),
    ('anon',          'public.paid_leave_requests'),
    ('authenticated', 'public.paid_leave_requests'),
    ('anon',          'public.reports'),
    ('authenticated', 'public.reports'),
    ('anon',          'public.site_assignments'),
    ('authenticated', 'public.site_assignments'),
    ('anon',          'public.site_categories'),
    ('authenticated', 'public.site_categories'),
    ('anon',          'public.sites'),
    ('authenticated', 'public.sites'),
    ('anon',          'public.subcontractors'),
    ('authenticated', 'public.subcontractors')
) as v(role_name, object_name)
order by object_name, role_name;

-- G-2. Completeness re-check (same shape as A-2).
--    Expected: 0 rows (no public table outside the 15 targets holds any of the 4
--    extras for anon / authenticated). STOP if any row remains.
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relkind = 'r'
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
  and  acl.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN')
  and  c.relname not in (
        'admin_sessions', 'companies', 'company_categories', 'employee_sessions',
        'machine_locations', 'machines', 'materials', 'notices',
        'paid_leave_grants', 'paid_leave_requests', 'reports', 'site_assignments',
        'site_categories', 'sites', 'subcontractors'
       )
order  by table_name, grantee, acl.privilege_type;

-- G-3. relacl re-check (aclexplode) for the 15 targets.
--    Expected: NO row with privilege_type in (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN)
--    for anon / authenticated. Rows for SELECT / INSERT / UPDATE (e.g. on the two
--    session tables and the SELECT-retaining master tables) may still appear and are
--    NOT touched by this file. STOP if any of the 4 extras remains.
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relkind = 'r'
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
  and  c.relname in (
        'admin_sessions', 'companies', 'company_categories', 'employee_sessions',
        'machine_locations', 'machines', 'materials', 'notices',
        'paid_leave_grants', 'paid_leave_requests', 'reports', 'site_assignments',
        'site_categories', 'sites', 'subcontractors'
       )
order  by table_name, grantee, acl.privilege_type;


-- ============================================================
-- Rollback (only if needed; temporary restore)
--   NOTE: normally NOT run (kept commented out). These are originally unneeded
--         (default-privilege leakage) privileges, so normally do NOT restore.
--   NOTE: symmetric to the EXECUTION BODY (Batch 1 = 4 privileges, Batch 2 = MAINTAIN).
-- ============================================================
-- -- Batch 1 rollback (13 tables)
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.admin_sessions      TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.companies           TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.company_categories  TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.employee_sessions   TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.machine_locations   TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.machines            TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.materials           TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.paid_leave_grants   TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.paid_leave_requests TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.site_assignments    TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.site_categories     TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.sites               TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.subcontractors      TO anon, authenticated;
-- -- Batch 2 rollback (2 tables)
-- GRANT MAINTAIN ON TABLE public.notices TO anon, authenticated;
-- GRANT MAINTAIN ON TABLE public.reports TO anon, authenticated;
-- ============================================================
