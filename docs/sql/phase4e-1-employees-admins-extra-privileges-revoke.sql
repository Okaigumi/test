-- ============================================================
-- Phase 4-E-1: employees / genka_admins - cleanup of residual unneeded privileges
--   (REVOKE TRUNCATE / REFERENCES / TRIGGER from anon / authenticated)
-- ============================================================
-- [STATUS] NOT EXECUTED (☆未実行☆)
--   - DB execution is performed manually by the user in Supabase SQL Editor.
--   - No DB connection / SQL execution / Supabase CLI / psql from Claude Code CLI.
--   - Run order: pre-check (A..F) -> confirm no STOP condition -> REVOKE body ->
--     post-check (G / G-2 / G-3) -> production 3-flow login check.
--   - The execution record is added to docs/db-migrations.md in a later PR
--     (not written in this file).
--
-- [PURPOSE]
--   Revoke the residual, non-read, unneeded privileges (TRUNCATE / REFERENCES /
--   TRIGGER) held by anon / authenticated on public.employees / public.genka_admins.
--   SELECT was already narrowed to column-level grants (2026-05-28) and INSERT /
--   UPDATE were already revoked (2026-05-30); writes go through *_secure RPCs and
--   login goes through create_*_session RPCs. This step is the cross-cutting cleanup
--   of the TRUNCATE / REFERENCES / TRIGGER privileges left behind on these two tables,
--   mirroring Phase 4-D-4 (financial tables).
--
-- [SCOPE]
--   Target tables:
--     public.employees
--     public.genka_admins
--   Target privileges:
--     TRUNCATE
--     REFERENCES
--     TRIGGER
--   Target roles:
--     anon
--     authenticated
--
-- [MUST NOT TOUCH]
--   - Column-level SELECT grants (login screens depend on them):
--       employees    : id, name, role, is_active, company_id, can_genka, can_admin
--       genka_admins : id, name, is_active
--     (pin is NOT granted and must stay ungranted.)
--   - RLS / policies / RPC definitions / EXECUTE grants / SECURITY DEFINER.
--   - HTML / JS / auth / PIN logic.
--   - service_role / postgres(owner) privileges.
--   - SELECT / INSERT / UPDATE / DELETE table privileges (already handled; not touched here).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run REVOKE; stop and report)
--   - anon / authenticated has table-level SELECT / INSERT / UPDATE / DELETE = true
--     on employees or genka_admins  -> STOP
--     (note: table-level SELECT should be false; column-level SELECT is separate and expected)
--   - public has ANY privilege on employees or genka_admins  -> STOP
--   - pin column has SELECT or REFERENCES granted to anon / authenticated / PUBLIC  -> STOP
--   - The column-level SELECT grant set differs from the expected set above
--     (missing/extra columns, or pin present)  -> STOP
--   - RLS is disabled (relrowsecurity=false) on either table  -> STOP
--   - Unexpected policy exists (e.g. employees_update_public reappeared, or any
--     unknown policy)  -> STOP
--   - Unexpected user-defined trigger exists on either table  -> STOP
--   - Unexpected FK references appear beyond the known ones  -> STOP
--   - A relevant secure/session RPC has prosecdef=false  -> STOP
--
-- [ROLLBACK] (only if needed; normally NOT used)
--   See the rollback section at the end (commented out).
--   NOTE: these are originally unneeded privileges, so normally do NOT restore.
-- ============================================================


-- ============================================================
-- Pre-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- A. Table-level privilege check (anon / authenticated on the two tables)
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
    ('anon',          'public.employees'),
    ('authenticated', 'public.employees'),
    ('anon',          'public.genka_admins'),
    ('authenticated', 'public.genka_admins')
) as v(role_name, object_name)
order by object_name, role_name;

-- A-2. public privilege check (for stop condition)
--    Expected: public has NO privilege on either table (all false).
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
    ('public.employees'),
    ('public.genka_admins')
) as v(object_name)
order by object_name;

-- A-3. Column-level SELECT grant check (must be preserved by this REVOKE)
--    Expected grant set (grantee in anon / authenticated):
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin
--      genka_admins : id, name, is_active
--    STOP if the set differs (missing/extra columns), or if pin appears.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  grantee in ('anon', 'authenticated')
order  by table_name, grantee, column_name;

-- A-4. pin column danger check (SELECT / REFERENCES on pin)
--    Expected: 0 rows (no pin column privilege for anon / authenticated / PUBLIC).
--    STOP if any row is returned.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  column_name = 'pin'
  and  privilege_type in ('SELECT', 'REFERENCES')
  and  grantee in ('anon', 'authenticated', 'PUBLIC')
order  by table_name, grantee, privilege_type;

-- B. RLS check (not changed; inspection only)
--    Expected: both tables relrowsecurity=true.
--    STOP if relrowsecurity=false on either table.
select relname             as table_name,
       relrowsecurity      as rls_enabled,
       relforcerowsecurity as rls_forced
from   pg_class
where  relnamespace = 'public'::regnamespace
  and  relname in ('employees', 'genka_admins')
order  by relname;

-- C. Policy check (not changed; inspection only)
--    Expected: no employees_update_public (removed 2026-05-30) and no unknown policy.
--    STOP if employees_update_public reappears or an unexpected policy exists.
select schemaname, tablename, policyname, cmd, roles
from   pg_policies
where  schemaname = 'public'
  and  tablename in ('employees', 'genka_admins')
order  by tablename, cmd, policyname;

-- D. Trigger check (not changed; inspection only)
--    Expected: 0 user-defined triggers per table (tgisinternal=false).
--    STOP if an unexpected user-defined trigger exists.
select c.relname as table_name,
       t.tgname  as trigger_name
from   pg_trigger t
join   pg_class c     on c.oid = t.tgrelid
join   pg_namespace n on n.oid = c.relnamespace
where  n.nspname = 'public'
  and  c.relname in ('employees', 'genka_admins')
  and  t.tgisinternal = false
order  by c.relname, t.tgname;

-- E. FK check (not changed; inspection only)
--    Known FKs that reference these tables as target:
--      employee_sessions.employee_id -> employees   (ON DELETE CASCADE)
--      admin_sessions.admin_id       -> genka_admins (ON DELETE CASCADE)
--      employee_rates.employee_id    -> employees
--    NOTE: REFERENCES is the privilege to CREATE new FKs; existing FK constraints
--          are NOT affected by this REVOKE.
--    STOP if an unexpected FK reference appears beyond the known ones (investigate first).
select con.conname  as constraint_name,
       src.relname  as from_table,
       tgt.relname  as to_table
from   pg_constraint con
join   pg_class src   on src.oid = con.conrelid
join   pg_class tgt   on tgt.oid = con.confrelid
join   pg_namespace n on n.oid = src.relnamespace
where  con.contype = 'f'
  and  n.nspname = 'public'
  and  ( src.relname in ('employees', 'genka_admins')
      or tgt.relname in ('employees', 'genka_admins') )
order  by from_table, to_table, constraint_name;

-- F. Session / secure RPC check (not changed; inspection only)
--    Expected: login/session and *_secure RPCs remain prosecdef=true / owner=postgres.
--    STOP if any relevant RPC has prosecdef=false.
select p.proname,
       p.prosecdef,
       pg_get_userbyid(p.proowner) as owner,
       p.proconfig
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public'
  and  p.proname in (
         'create_employee_session', 'revoke_employee_session',
         'create_admin_session', 'revoke_admin_session',
         'create_employee_secure', 'update_employee_secure',
         'create_genka_admin_secure', 'update_genka_admin_secure'
       )
order  by p.proname;


-- ============================================================
-- REVOKE body
--   NOTE: this is the first place that modifies DB state. Run only after
--         pre-checks A..F all match expectations (and no STOP condition is hit).
--   NOTE: one table per statement. Order: employees -> genka_admins.
--   NOTE: this touches ONLY table-level TRUNCATE / REFERENCES / TRIGGER.
--         Column-level SELECT grants are NOT affected.
-- ============================================================

REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.employees FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE public.genka_admins FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. Table-level privilege check (same shape as A)
--    Expected: for anon / authenticated on both tables,
--      can_select=false / can_insert=false / can_update=false / can_delete=false /
--      can_truncate=false / can_references=false / can_trigger=false
--      (all 8 table-level privileges false).
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
    ('anon',          'public.employees'),
    ('authenticated', 'public.employees'),
    ('anon',          'public.genka_admins'),
    ('authenticated', 'public.genka_admins')
) as v(role_name, object_name)
order by object_name, role_name;

-- G-2. public privileges post-check (same shape as A-2; must be unchanged)
--    Expected: public remains all false on both tables (public not touched here).
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
    ('public.employees'),
    ('public.genka_admins')
) as v(object_name)
order by object_name;

-- G-3. Column-level SELECT grant re-check (must be UNCHANGED from A-3)
--    Expected: same grant set as A-3 (login screens keep working).
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin
--      genka_admins : id, name, is_active
--    This confirms the REVOKE did NOT remove the column-level SELECT grants.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  grantee in ('anon', 'authenticated')
order  by table_name, grantee, column_name;


-- ============================================================
-- Production verification (app side; manual)
--   After REVOKE, confirm all three login flows still work and the
--   employee/admin lists still render (these use the column-level SELECT).
--     - index.html      ... employee login (/)
--     - admin-app.html   ... admin login   (/admin)
--     - genka-app.html   ... genka login    (/genka)
-- ============================================================


-- ============================================================
-- Rollback (only if needed; temporary restore)
--   NOTE: normally NOT run (kept commented out). These are originally unneeded
--         privileges, so normally do NOT restore.
--   NOTE: use only in an emergency if an unexpected impact is found in production
--         after the REVOKE; restore the relevant table's line, find the cause, then
--         REVOKE again.
-- ============================================================
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.employees TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLE public.genka_admins TO anon, authenticated;
-- ============================================================
