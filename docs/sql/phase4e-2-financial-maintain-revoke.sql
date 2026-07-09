-- ============================================================
-- Phase 4-E-2: financial tables - cleanup of residual PG17 MAINTAIN privilege
--   (REVOKE MAINTAIN from anon / authenticated)
-- ============================================================
-- [STATUS] NOT EXECUTED - SKIPPED (target state already clean at execution-time and
--           final re-check; REVOKE body not run by this workflow)
--   - Initial pre-check (Supabase SQL Editor, manual, 2026-07-09) found the residual:
--       A-0 : PostgreSQL 17.6 (server_version_num=170006), is_pg17_or_newer=true
--       A   : anon/authenticated on all 4 tables -> SELECT/INSERT/UPDATE/DELETE/
--             TRUNCATE/REFERENCES/TRIGGER = false, MAINTAIN = true (residual)
--       A-2 : public = all false on all 4 tables
--       A-5a: relacl shows MAINTAIN only (8 rows: 4 tables x anon/authenticated)
--     -> MAINTAIN residual confirmed; this script was created for the cleanup.
--   - SQL file created and merged via PR #83 (merge commit 9e6e209); STATUS was
--     initially NOT EXECUTED.
--   - Execution-time pre-check (Supabase SQL Editor, manual, 2026-07-09), immediately
--     before running the REVOKE body, found the target already clean:
--       A   : anon/authenticated on all 4 tables -> all 8 privileges
--             (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) = false
--       A-5a: relacl = 0 rows for anon/authenticated
--       A-2 : public = all false on all 4 tables
--   - Final re-check (Supabase SQL Editor, manual, 2026-07-09) reconfirmed: all 8
--     privileges = false for anon/authenticated on all 4 tables (stable / clean).
--   - Therefore the REVOKE body (4 statements) was NOT run. No DB change was made.
--   - Cause of the state change (initial MAINTAIN residual -> clean) is UNIDENTIFIED
--     in this workflow (a REVOKE via some other path cannot be ruled out; this workflow
--     did NOT run the REVOKE).
--   - SEPARATE BACKLOG (default privileges): pg_default_acl still grants
--     anon / authenticated `arwdDxtm` (a=INSERT r=SELECT w=UPDATE d=DELETE D=TRUNCATE
--     x=REFERENCES t=TRIGGER m=MAINTAIN) on FUTURE public tables, so newly created
--     public tables would receive all privileges (incl. MAINTAIN) again. Not changed
--     here; tracked as a default-privileges cleanup candidate (out of scope for 4-E-2).
--   - No DB connection / SQL execution / Supabase CLI / psql from Claude Code CLI;
--     all DB checks were run manually by the user in Supabase SQL Editor.
--
-- [PURPOSE]
--   Revoke the residual PG17 MAINTAIN privilege held by anon / authenticated on the
--   four financial tables. SELECT/INSERT/UPDATE/DELETE were blocked in Phase 4-D-1/2/3,
--   and TRUNCATE/REFERENCES/TRIGGER were revoked in Phase 4-D-4; reads/writes go through
--   secure RPCs. MAINTAIN (VACUUM / ANALYZE / CLUSTER / REINDEX /
--   REFRESH MATERIALIZED VIEW / LOCK TABLE) was left on these tables as a side effect of
--   Supabase's PG17 default GRANT ALL, is not used by the app, and was explicitly deferred
--   as a "Phase 4-E-2 candidate" in the Phase 4-E-1 record. This step is the final
--   cross-cutting cleanup of MAINTAIN on the financial tables, mirroring Phase 4-E-1
--   (employees / genka_admins).
--   NOTE: MAINTAIN is a table-level maintenance privilege added in PostgreSQL 17;
--         precedent in-repo: phase4c-4-report-summary-revoke.sql, phase4e-1-...-revoke.sql.
--
-- [SCOPE]
--   Target tables:
--     public.unit_rates
--     public.employee_rates
--     public.site_budgets
--     public.invoices
--   Target privilege:
--     MAINTAIN   (PostgreSQL 17 table-level maintenance privilege; sole target)
--   Target roles:
--     anon
--     authenticated
--
-- [MUST NOT TOUCH]
--   - SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER
--     (already all false; not touched here).
--   - RLS / policies (incl. site_budgets.anon_can_update_site_budgets) / RPC definitions
--     / EXECUTE grants / SECURITY DEFINER.
--   - HTML / JS / auth / PIN logic.
--   - service_role / postgres(owner) privileges.
--   - No column-level grants exist on these tables (SELECT was revoked table-level in 4-D);
--     nothing at column level to preserve or touch.
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run REVOKE; stop and report)
--   - anon / authenticated has any of SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/
--     TRIGGER = true on any of the 4 tables (i.e. anything other than MAINTAIN) -> STOP
--     (MAINTAIN=true is EXPECTED; it is exactly what this script revokes -> NOT a stop)
--   - public has ANY privilege on any of the 4 tables (incl. pub_maintain=true) -> STOP
--   - A-5a (relacl) shows any privilege_type other than MAINTAIN for anon/authenticated -> STOP
--   - Post-check G: MAINTAIN does NOT become false (can_maintain still true) -> STOP
--
-- [ROLLBACK] (only if needed; normally NOT used)
--   See the rollback section at the end (commented out).
--   NOTE: MAINTAIN is an originally unneeded privilege, so normally do NOT restore.
-- ============================================================


-- ============================================================
-- Pre-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- A-0. PostgreSQL version check (guard for the MAINTAIN keyword; PG17+ only)
--    Expected: server_version_num >= 170000. STOP if PostgreSQL 16 or earlier.
select version()                                       as pg_version,
       current_setting('server_version_num')::int      as server_version_num,
       (current_setting('server_version_num')::int >= 170000) as is_pg17_or_newer;

-- A. Table-level privilege check (anon / authenticated on the 4 financial tables)
--    Expected: can_select..can_trigger = false ; can_maintain = true.
--    STOP if any of can_select/can_insert/can_update/can_delete/can_truncate/
--    can_references/can_trigger is true (MAINTAIN=true is EXPECTED, not a stop).
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
    ('anon',          'public.employee_rates'),
    ('authenticated', 'public.employee_rates'),
    ('anon',          'public.invoices'),
    ('authenticated', 'public.invoices'),
    ('anon',          'public.site_budgets'),
    ('authenticated', 'public.site_budgets'),
    ('anon',          'public.unit_rates'),
    ('authenticated', 'public.unit_rates')
) as v(role_name, object_name)
order by object_name, role_name;

-- A-2. PUBLIC privilege check (stop condition)
--    Expected: all false (incl. pub_maintain). STOP if any true.
select
  object_name,
  has_table_privilege('public', object_name, 'SELECT')     as pub_select,
  has_table_privilege('public', object_name, 'INSERT')     as pub_insert,
  has_table_privilege('public', object_name, 'UPDATE')     as pub_update,
  has_table_privilege('public', object_name, 'DELETE')     as pub_delete,
  has_table_privilege('public', object_name, 'TRUNCATE')   as pub_truncate,
  has_table_privilege('public', object_name, 'REFERENCES') as pub_references,
  has_table_privilege('public', object_name, 'TRIGGER')    as pub_trigger,
  has_table_privilege('public', object_name, 'MAINTAIN')   as pub_maintain
from (
  values
    ('public.employee_rates'),
    ('public.invoices'),
    ('public.site_budgets'),
    ('public.unit_rates')
) as v(object_name)
order by object_name;

-- A-5a. Table-level privileges from pg_class.relacl (anon / authenticated)
--    ACL letter map: r=SELECT a=INSERT w=UPDATE d=DELETE D=TRUNCATE x=REFERENCES
--                    t=TRIGGER m=MAINTAIN
--    Phase 4-D-4 already revoked D/x/t on these tables, so if only MAINTAIN(m) remains,
--    only privilege_type='MAINTAIN' rows should appear (8 rows: 4 tables x 2 roles).
--    STOP if any privilege_type other than MAINTAIN appears.
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
order  by c.relname, grantee, acl.privilege_type;


-- ============================================================
-- REVOKE body
--   NOTE: this is the first place that modifies DB state. Run only after
--         pre-checks A-0/A/A-2/A-5a match expectations (no STOP hit).
--   NOTE: one table per statement.
--         Order: employee_rates -> invoices -> site_budgets -> unit_rates (as in 4-D-4).
--   NOTE: touches ONLY table-level MAINTAIN.
-- ============================================================

REVOKE MAINTAIN ON TABLE public.employee_rates FROM anon, authenticated;
REVOKE MAINTAIN ON TABLE public.invoices       FROM anon, authenticated;
REVOKE MAINTAIN ON TABLE public.site_budgets   FROM anon, authenticated;
REVOKE MAINTAIN ON TABLE public.unit_rates     FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. Table-level privilege check (same shape as A)
--    Expected: for anon / authenticated on all 4 tables, all 8 privileges = false
--      (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN).
--    STOP if can_maintain is still true anywhere.
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
    ('anon',          'public.employee_rates'),
    ('authenticated', 'public.employee_rates'),
    ('anon',          'public.invoices'),
    ('authenticated', 'public.invoices'),
    ('anon',          'public.site_budgets'),
    ('authenticated', 'public.site_budgets'),
    ('anon',          'public.unit_rates'),
    ('authenticated', 'public.unit_rates')
) as v(role_name, object_name)
order by object_name, role_name;

-- G-2. PUBLIC privileges post-check (same shape as A-2; must be unchanged)
--    Expected: public remains all false on the 4 tables (incl. pub_maintain=false).
select
  object_name,
  has_table_privilege('public', object_name, 'SELECT')     as pub_select,
  has_table_privilege('public', object_name, 'INSERT')     as pub_insert,
  has_table_privilege('public', object_name, 'UPDATE')     as pub_update,
  has_table_privilege('public', object_name, 'DELETE')     as pub_delete,
  has_table_privilege('public', object_name, 'TRUNCATE')   as pub_truncate,
  has_table_privilege('public', object_name, 'REFERENCES') as pub_references,
  has_table_privilege('public', object_name, 'TRIGGER')    as pub_trigger,
  has_table_privilege('public', object_name, 'MAINTAIN')   as pub_maintain
from (
  values
    ('public.employee_rates'),
    ('public.invoices'),
    ('public.site_budgets'),
    ('public.unit_rates')
) as v(object_name)
order by object_name;

-- G-5. relacl re-check (aclexplode; same shape as A-5a)
--    Expected: 0 rows for anon / authenticated (MAINTAIN removed; nothing else was present).
--    STOP if any row remains (esp. any MAINTAIN row).
select c.relname                        as table_name,
       acl.grantee::regrole::text       as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
order  by c.relname, grantee, acl.privilege_type;


-- ============================================================
-- Production verification (app side; manual)
--   After REVOKE, confirm admin / genka flows still work; financial reads/writes go
--   through secure RPCs (200), no direct table access, no 400/401/403, no red console
--   errors. Revoking MAINTAIN does not affect the app: MAINTAIN only governs VACUUM /
--   ANALYZE / CLUSTER / REINDEX / REFRESH MATERIALIZED VIEW / LOCK TABLE, which the app
--   never issues.
--     - admin-app.html  ... admin login  (/admin)
--     - genka-app.html  ... genka login  (/genka)
-- ============================================================


-- ============================================================
-- Rollback (only if needed; temporary restore)
--   NOTE: normally NOT run (kept commented out). MAINTAIN is an originally unneeded
--         privilege, so normally do NOT restore.
-- ============================================================
-- GRANT MAINTAIN ON TABLE public.employee_rates TO anon, authenticated;
-- GRANT MAINTAIN ON TABLE public.invoices       TO anon, authenticated;
-- GRANT MAINTAIN ON TABLE public.site_budgets   TO anon, authenticated;
-- GRANT MAINTAIN ON TABLE public.unit_rates     TO anon, authenticated;
-- ============================================================
