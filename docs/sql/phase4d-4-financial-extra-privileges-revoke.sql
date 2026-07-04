-- ============================================================
-- Phase 4-D-4: financial tables - cleanup of residual unneeded privileges
--   (REVOKE TRUNCATE / REFERENCES / TRIGGER from anon / authenticated)
-- ============================================================
-- [STATUS] NOT EXECUTED
--   - Not yet run in Supabase SQL Editor.
--   - No DB connection / Supabase CLI from Claude Code CLI. DB execution is done
--     manually by the user.
--
-- [PURPOSE]
--   Revoke the residual, non-read, unneeded privileges (TRUNCATE / REFERENCES /
--   TRIGGER) held by anon / authenticated on the four financial tables
--   (unit_rates / employee_rates / site_budgets / invoices).
--   SELECT / INSERT / UPDATE / DELETE were already blocked in Phase 4-D-1 /
--   4-D-2 / 4-D-3, and reads are consolidated behind secure read RPCs.
--   This step is the cross-cutting cleanup of the TRUNCATE / REFERENCES / TRIGGER
--   privileges that were left behind and deferred as "later privilege review"
--   in each of 4-D-1c / 4-D-2c / 4-D-3c.
--
-- [SCOPE]
--   Target tables:
--     public.unit_rates
--     public.employee_rates
--     public.site_budgets
--     public.invoices
--   Target privileges:
--     TRUNCATE
--     REFERENCES
--     TRIGGER
--   Target roles:
--     anon
--     authenticated
--
-- [STAGE B SUMMARY] (verified by the user, run manually in Supabase SQL Editor)
--   1. Privilege state (four financial tables)
--      - anon / authenticated: SELECT / INSERT / UPDATE / DELETE = false
--      - anon / authenticated: TRUNCATE / REFERENCES / TRIGGER = true (<- removal target)
--      - public: all privileges = false
--   2. RLS state
--      - all four tables: relrowsecurity=true / relforcerowsecurity=false
--   3. Policies
--      - employee_rates: er_read / er_update / er_write
--      - invoices:       inv_read / inv_update / inv_write
--      - site_budgets:   anon_can_update_site_budgets / sb_read / sb_update / sb_write
--      - unit_rates:     ur_read / ur_update / ur_write
--      NOTE: site_budgets.anon_can_update_site_budgets remains as an existing policy.
--        However, per check #1 the anon direct UPDATE grant is false, so it does not
--        block this REVOKE. Record it as a later policy-review candidate (not touched here).
--   4. Existing triggers
--      - all four tables: 0 user-defined triggers
--   5. Foreign keys
--      - employee_rates -> employees
--      - invoices -> companies / invoices -> sites
--      - site_budgets -> companies / site_budgets -> sites
--      - unit_rates -> companies
--      - No FK references a financial table as its target. (Revoking REFERENCES does
--        not affect existing FKs; REFERENCES is the privilege to CREATE new FKs, and
--        existing FK constraints are retained.)
--   6. Secure RPCs
--      - All financial secure RPCs: prosecdef=true / owner=postgres /
--        search_path=public, extensions (fixed)
--
-- [NON-GOALS] (intentionally not touched in this step)
--   - No RPC changes (read/write RPC definitions, EXECUTE grants, SECURITY DEFINER unchanged)
--   - No RLS changes
--   - No policy changes (incl. anon_can_update_site_budgets; review is a separate step)
--   - No HTML changes
--   - SELECT / INSERT / UPDATE / DELETE out of scope (already blocked; not touched here)
--   - service_role / postgres(owner) not touched
--   - No update to docs/db-migrations.md / docs/roadmap.md (not done in this file)
--   - No DB execution (this file is created only; execution is manual by the user)
--   - No Supabase CLI
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run REVOKE; stop and report)
--   - Any of the four tables has SELECT / INSERT / UPDATE / DELETE = true for
--     anon / authenticated -> STOP
--   - public has any privilege on any of the four tables -> STOP
--   - RLS is disabled or otherwise disagrees with Stage B (RLS enabled) -> STOP
--   - Policies differ unexpectedly from the Stage B snapshot -> STOP
--   - Any secure RPC has prosecdef=false or otherwise disagrees with Stage B
--     (all SECURITY DEFINER) -> STOP
--
-- [ROLLBACK] (only if needed; normally not used)
--   See the rollback section at the end (commented out).
--   NOTE: these are originally unneeded privileges, so normally do not restore.
-- ============================================================


-- ============================================================
-- Pre-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- A. Privilege check (same shape as check #1)
--    Current anon / authenticated privileges on the four financial tables.
--    Expected: can_select=false / can_insert=false / can_update=false / can_delete=false
--              can_truncate=true / can_references=true / can_trigger=true
--    STOP if any of can_select / can_insert / can_update / can_delete is true.
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger
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

-- A-2. public privileges (for stop condition)
--    Expected: public has NO privilege on any of the four tables (all false).
--    STOP if any privilege is true.
select
  object_name,
  has_table_privilege('public', object_name, 'SELECT')     as pub_select,
  has_table_privilege('public', object_name, 'INSERT')     as pub_insert,
  has_table_privilege('public', object_name, 'UPDATE')     as pub_update,
  has_table_privilege('public', object_name, 'DELETE')     as pub_delete,
  has_table_privilege('public', object_name, 'TRUNCATE')   as pub_truncate,
  has_table_privilege('public', object_name, 'REFERENCES') as pub_references,
  has_table_privilege('public', object_name, 'TRIGGER')    as pub_trigger
from (
  values
    ('public.employee_rates'),
    ('public.invoices'),
    ('public.site_budgets'),
    ('public.unit_rates')
) as v(object_name)
order by object_name;

-- B. RLS check (not changed; inspection only)
--    Expected: all four tables relrowsecurity=true / relforcerowsecurity=false.
select relname               as table_name,
       relrowsecurity        as rls_enabled,
       relforcerowsecurity   as rls_forced
from   pg_class
where  relnamespace = 'public'::regnamespace
  and  relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
order  by relname;

-- C. Policy check (not changed; inspection only)
--    Expected (Stage B):
--      employee_rates: er_read / er_update / er_write
--      invoices:       inv_read / inv_update / inv_write
--      site_budgets:   anon_can_update_site_budgets / sb_read / sb_update / sb_write
--      unit_rates:     ur_read / ur_update / ur_write
select schemaname, tablename, policyname, cmd, roles
from   pg_policies
where  schemaname = 'public'
  and  tablename in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
order  by tablename, cmd, policyname;

-- D. Trigger check (not changed; inspection only)
--    Expected: 0 user-defined triggers per table (tgisinternal=false).
select c.relname as table_name,
       t.tgname  as trigger_name
from   pg_trigger t
join   pg_class c    on c.oid = t.tgrelid
join   pg_namespace n on n.oid = c.relnamespace
where  n.nspname = 'public'
  and  c.relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
  and  t.tgisinternal = false
order  by c.relname, t.tgname;

-- E. FK check (not changed; inspection only)
--    Expected (Stage B):
--      employee_rates -> employees
--      invoices -> companies / invoices -> sites
--      site_budgets -> companies / site_budgets -> sites
--      unit_rates -> companies
--      No FK references a financial table as its target.
--    NOTE: REFERENCES is the privilege to CREATE new FKs; existing FK constraints
--          are not affected by this REVOKE.
select con.conname  as constraint_name,
       src.relname  as from_table,
       tgt.relname  as to_table
from   pg_constraint con
join   pg_class src   on src.oid = con.conrelid
join   pg_class tgt   on tgt.oid = con.confrelid
join   pg_namespace n on n.oid = src.relnamespace
where  con.contype = 'f'
  and  n.nspname = 'public'
  and  ( src.relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates')
      or tgt.relname in ('employee_rates', 'invoices', 'site_budgets', 'unit_rates') )
order  by from_table, to_table, constraint_name;

-- F. Secure RPC check (not changed; inspection only)
--    Expected (Stage B): all financial secure RPCs are prosecdef=true /
--      owner=postgres / search_path=public, extensions (fixed).
select p.proname,
       p.prosecdef,
       pg_get_userbyid(p.proowner) as owner,
       p.proconfig
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public'
  and  p.proname in (
         -- unit_rates / employee_rates (4-D-1)
         'list_unit_rates_secure', 'get_unit_rate_secure',
         'list_employee_rates_secure', 'get_employee_rate_secure',
         -- site_budgets (4-D-2)
         'list_site_budgets_secure', 'get_site_budget_secure',
         -- invoices (4-D-3)
         'list_invoices_secure', 'get_invoice_secure',
         'create_invoice_secure', 'update_invoice_secure',
         'reject_invoice_secure', 'restore_invoice_secure'
       )
order  by p.proname;


-- ============================================================
-- REVOKE body
--   NOTE: this is the first place that modifies DB state. Run only after
--         pre-checks A..F all match expectations (and no stop condition is hit).
--   NOTE: one table per statement.
--         Order: employee_rates -> invoices -> site_budgets -> unit_rates.
-- ============================================================

REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.employee_rates FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.invoices FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.site_budgets FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.unit_rates FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. Privilege check (same shape as A)
--    Expected: for anon / authenticated on all four tables,
--      can_select=false / can_insert=false / can_update=false / can_delete=false /
--      can_truncate=false / can_references=false / can_trigger=false
--      (i.e. all 8 privileges are false on the four target tables)
select
  role_name,
  object_name,
  has_table_privilege(role_name, object_name, 'SELECT')     as can_select,
  has_table_privilege(role_name, object_name, 'INSERT')     as can_insert,
  has_table_privilege(role_name, object_name, 'UPDATE')     as can_update,
  has_table_privilege(role_name, object_name, 'DELETE')     as can_delete,
  has_table_privilege(role_name, object_name, 'TRUNCATE')   as can_truncate,
  has_table_privilege(role_name, object_name, 'REFERENCES') as can_references,
  has_table_privilege(role_name, object_name, 'TRIGGER')    as can_trigger
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

-- G-2. public privileges post-check (same shape as A-2; must be unchanged)
--    Expected: public remains all false on the four tables (public not touched here).
select
  object_name,
  has_table_privilege('public', object_name, 'SELECT')     as pub_select,
  has_table_privilege('public', object_name, 'INSERT')     as pub_insert,
  has_table_privilege('public', object_name, 'UPDATE')     as pub_update,
  has_table_privilege('public', object_name, 'DELETE')     as pub_delete,
  has_table_privilege('public', object_name, 'TRUNCATE')   as pub_truncate,
  has_table_privilege('public', object_name, 'REFERENCES') as pub_references,
  has_table_privilege('public', object_name, 'TRIGGER')    as pub_trigger
from (
  values
    ('public.employee_rates'),
    ('public.invoices'),
    ('public.site_budgets'),
    ('public.unit_rates')
) as v(object_name)
order by object_name;


-- ============================================================
-- Rollback (only if needed; temporary restore)
--   NOTE: normally NOT run (kept commented out). These are originally unneeded
--         privileges, so normally do not restore.
--   NOTE: use only in an emergency if an unexpected impact is found in production
--         after the REVOKE; restore the relevant table's line, find the cause, then
--         REVOKE again.
-- ============================================================
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.employee_rates TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.invoices TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.site_budgets TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.unit_rates TO anon, authenticated;
-- ============================================================
