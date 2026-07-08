-- ============================================================
-- Phase 4-E-1: employees / genka_admins - cleanup of residual unneeded privileges
--   (REVOKE TRUNCATE / REFERENCES / TRIGGER / MAINTAIN from anon / authenticated)
-- ============================================================
-- [STATUS] NOT EXECUTED (☆未実行☆)
--   - DB execution is performed manually by the user in Supabase SQL Editor.
--   - No DB connection / SQL execution / Supabase CLI / psql from Claude Code CLI.
--   - Run order: pre-check (A-0..F) -> confirm no STOP condition -> REVOKE body ->
--     post-check (G / G-2 / G-3 / G-4 / G-5) -> production 3-flow login check.
--   - The execution record is added to docs/db-migrations.md in a later PR
--     (not written in this file).
--
-- [PURPOSE]
--   Revoke the residual, non-read, unneeded privileges (TRUNCATE / REFERENCES /
--   TRIGGER / MAINTAIN) held by anon / authenticated on public.employees /
--   public.genka_admins.
--   SELECT was already narrowed to column-level grants (2026-05-28) and INSERT /
--   UPDATE were already revoked (2026-05-30); writes go through *_secure RPCs and
--   login goes through create_*_session RPCs. This step is the cross-cutting cleanup
--   of the TRUNCATE / REFERENCES / TRIGGER / MAINTAIN privileges left behind on these
--   two tables, mirroring Phase 4-D-4 (financial tables).
--   NOTE on MAINTAIN: MAINTAIN is a table-level maintenance privilege added in
--   PostgreSQL 17 (allows VACUUM / ANALYZE / CLUSTER / REINDEX /
--   REFRESH MATERIALIZED VIEW / LOCK TABLE). It was granted to anon / authenticated
--   as a side effect of Supabase's PG17 default GRANT ALL, is not used by the app
--   (PostgREST CRUD / RPC never issues these commands), and is therefore treated as
--   a residual unneeded privilege to be revoked here (same as the in-repo precedent
--   docs/sql/phase4c-4-report-summary-revoke.sql, which revoked MAINTAIN too).
--
-- [SCOPE]
--   Target tables:
--     public.employees
--     public.genka_admins
--   Target privileges:
--     TRUNCATE
--     REFERENCES
--     TRIGGER
--     MAINTAIN   (PostgreSQL 17 table-level maintenance privilege; see PURPOSE note)
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
--     (note: table-level TRUNCATE / REFERENCES / TRIGGER / MAINTAIN = true is EXPECTED
--            here; they are exactly what this script revokes -> NOT a stop condition)
--   - public has ANY privilege on employees or genka_admins  -> STOP
--   - pin column has SELECT granted to anon / authenticated / PUBLIC  -> STOP
--     (note: a REFERENCES row shown against pin in information_schema.column_privileges
--            is very likely the TABLE-level REFERENCES reflected onto every column, NOT a
--            real column-level grant; a REFERENCES row alone is therefore NOT a stop
--            condition. The table-level REVOKE REFERENCES removes it. A REAL column-level
--            REFERENCES grant lives in pg_attribute.attacl and is checked in A-5.)
--   - A REAL column-level REFERENCES grant on any column (incl. pin) exists in
--     pg_attribute.attacl for anon / authenticated  -> STOP (needs a column-level REVOKE too)
--   - The column-level SELECT grant set differs from the expected set above
--     (missing/extra columns, or pin present)  -> STOP
--   - A column-level grant other than the expected SELECT set exists in attacl  -> STOP
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

-- A-0. PostgreSQL version check (guard for the MAINTAIN privilege keyword)
--    MAINTAIN is a table-level privilege introduced in PostgreSQL 17. The REVOKE body
--    and the can_maintain / pub_maintain checks below use the 'MAINTAIN' keyword, which
--    does NOT exist in PostgreSQL 16 or earlier (has_table_privilege / REVOKE would
--    raise: unrecognized privilege type "MAINTAIN").
--    Expected: PostgreSQL 17 or later (Supabase current).
--    STOP if the server is PostgreSQL 16 or earlier -> do NOT run this script as-is
--          (the MAINTAIN parts would error; re-scope before running).
select version()             as pg_version,
       current_setting('server_version_num')::int as server_version_num;
-- (server_version_num >= 170000 means PostgreSQL 17+.)

-- A. Table-level privilege check (anon / authenticated on the two tables)
--    Expected: can_select=false / can_insert=false / can_update=false / can_delete=false
--              can_truncate=true / can_references=true / can_trigger=true / can_maintain=true
--    STOP if any of can_select / can_insert / can_update / can_delete is true.
--    NOTE: can_truncate / can_references / can_trigger / can_maintain = true is EXPECTED
--          (that is what this script revokes); it is NOT a stop condition.
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
    ('anon',          'public.employees'),
    ('authenticated', 'public.employees'),
    ('anon',          'public.genka_admins'),
    ('authenticated', 'public.genka_admins')
) as v(role_name, object_name)
order by object_name, role_name;

-- A-2. public privilege check (for stop condition)
--    Expected: public has NO privilege on either table (all false, incl. pub_maintain).
--    STOP if any privilege is true (including pub_maintain=true).
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
    ('public.employees'),
    ('public.genka_admins')
) as v(object_name)
order by object_name;

-- A-3. Column-level SELECT grant check (must be preserved by this REVOKE)
--    NOTE: limited to privilege_type='SELECT' on purpose. information_schema.
--          column_privileges reflects a TABLE-level REFERENCES grant onto EVERY column,
--          so an unfiltered query would list REFERENCES on all columns (incl. pin) and
--          pollute this SELECT-set check. Filtering to SELECT isolates the real
--          column-level SELECT grants (which live in pg_attribute.attacl).
--    Expected grant set (grantee in anon / authenticated):
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin
--      genka_admins : id, name, is_active
--    STOP if the SELECT set differs (missing/extra columns), or if pin appears.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  grantee in ('anon', 'authenticated')
  and  privilege_type = 'SELECT'
order  by table_name, grantee, column_name;

-- A-4. pin column SELECT danger check (SELECT on pin only)
--    NOTE: only SELECT is checked here. A REFERENCES row against pin in
--          information_schema.column_privileges is very likely the table-level
--          REFERENCES reflected onto every column (removed by the table-level REVOKE),
--          not a real column-level grant. The real column-level REFERENCES check is A-5
--          (pg_attribute.attacl). So do NOT treat a reflected REFERENCES as a stop here.
--    Expected: 0 rows (no pin SELECT for anon / authenticated / PUBLIC).
--    STOP if any row is returned.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  column_name = 'pin'
  and  privilege_type = 'SELECT'
  and  grantee in ('anon', 'authenticated', 'PUBLIC')
order  by table_name, grantee;

-- A-5. relacl / attacl separation diagnostic (table-level vs REAL column-level)
--    Purpose: distinguish a TABLE-level grant (pg_class.relacl, reflected onto all
--    columns in information_schema.column_privileges) from a REAL column-level grant
--    (pg_attribute.attacl). This is what A-3/A-4 cannot tell apart on their own.
--
-- A-5a. Table-level privileges from pg_class.relacl (anon / authenticated)
--    Expected: TRUNCATE / REFERENCES / TRIGGER / MAINTAIN present at TABLE level (that is
--              exactly what this script revokes). SELECT/INSERT/UPDATE should NOT be present
--              at table level (SELECT is column-level; INSERT/UPDATE were revoked earlier).
--    NOTE: MAINTAIN (letter m) is a PostgreSQL 17 table-level privilege and shows up here
--          via aclexplode without any query change; this A-5a query is what detected the
--          residual MAINTAIN in the first place. Seeing MAINTAIN here is EXPECTED (it is
--          revoked by the REVOKE body) -> NOT a stop condition.
--    ACL letter map: r=SELECT a=INSERT w=UPDATE d=DELETE D=TRUNCATE x=REFERENCES t=TRIGGER
--                    m=MAINTAIN
select c.relname                         as table_name,
       acl.grantee::regrole::text        as grantee,
       acl.privilege_type
from   pg_class c
cross  join lateral aclexplode(c.relacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relname in ('employees', 'genka_admins')
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
order  by c.relname, grantee, acl.privilege_type;

-- A-5b. REAL column-level privileges from pg_attribute.attacl (anon / authenticated)
--    NOTE: MAINTAIN (like TRUNCATE / TRIGGER / DELETE) has NO column-level form in
--          PostgreSQL; only SELECT / INSERT / UPDATE / REFERENCES can be column-level.
--          So this attacl diagnostic concerns mainly the column-level SELECT set and any
--          REAL column-level REFERENCES; MAINTAIN can never appear in attacl (it is
--          table-level only, checked in A-5a / A / G).
--    Expected: ONLY SELECT on the expected columns
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin
--      genka_admins : id, name, is_active
--    STOP if:
--      - any REFERENCES (or any non-SELECT) appears at column level for anon/authenticated
--      - pin has any column-level privilege
--      - the column-level SELECT set differs from the expected set
--    (0 rows here would mean SELECT is granted some other way; cross-check with A-3.)
select c.relname                         as table_name,
       a.attname                         as column_name,
       acl.grantee::regrole::text        as grantee,
       acl.privilege_type
from   pg_class c
join   pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
cross  join lateral aclexplode(a.attacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relname in ('employees', 'genka_admins')
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
order  by c.relname, a.attname, grantee, acl.privilege_type;

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
--   NOTE: this touches ONLY table-level TRUNCATE / REFERENCES / TRIGGER / MAINTAIN.
--         Column-level SELECT grants are NOT affected (they live in pg_attribute.attacl,
--         a separate ACL from the table-level pg_class.relacl revoked here).
-- ============================================================

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.employees FROM anon, authenticated;
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.genka_admins FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. Table-level privilege check (same shape as A)
--    Expected: for anon / authenticated on both tables,
--      can_select=false / can_insert=false / can_update=false / can_delete=false /
--      can_truncate=false / can_references=false / can_trigger=false / can_maintain=false
--      (all 8 table-level privileges false:
--       SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN).
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
    ('anon',          'public.employees'),
    ('authenticated', 'public.employees'),
    ('anon',          'public.genka_admins'),
    ('authenticated', 'public.genka_admins')
) as v(role_name, object_name)
order by object_name, role_name;

-- G-2. public privileges post-check (same shape as A-2; must be unchanged)
--    Expected: public remains all false on both tables (public not touched here),
--              including pub_maintain=false.
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
    ('public.employees'),
    ('public.genka_admins')
) as v(object_name)
order by object_name;

-- G-3. Column-level SELECT grant re-check (must be UNCHANGED from A-3)
--    NOTE: limited to privilege_type='SELECT' (same as A-3) so the table-level
--          REFERENCES reflection does not pollute this check. After the REVOKE the
--          reflected REFERENCES rows disappear anyway; here we only verify SELECT is intact.
--    Expected: same SELECT set as A-3 (login screens keep working).
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin
--      genka_admins : id, name, is_active
--    This confirms the REVOKE did NOT remove the column-level SELECT grants.
select grantee, table_name, column_name, privilege_type
from   information_schema.column_privileges
where  table_schema = 'public'
  and  table_name in ('employees', 'genka_admins')
  and  grantee in ('anon', 'authenticated')
  and  privilege_type = 'SELECT'
order  by table_name, grantee, column_name;

-- G-4. pin REFERENCES removal check (has_column_privilege)
--    Confirms the reflected/any REFERENCES on pin is gone after the table-level REVOKE.
--    Expected: pin_ref = false for all 4 rows (employees / genka_admins x anon / authenticated).
select role_name,
       object_name,
       has_column_privilege(role_name, object_name, 'pin', 'REFERENCES') as pin_ref
from (
  values
    ('anon',          'public.employees'),
    ('authenticated', 'public.employees'),
    ('anon',          'public.genka_admins'),
    ('authenticated', 'public.genka_admins')
) as v(role_name, object_name)
order by object_name, role_name;

-- G-5. attacl re-check (no REAL column-level pin/REFERENCES remains)
--    NOTE: MAINTAIN is table-level only and never appears in attacl, so this column-level
--          re-check concerns the column SELECT set and any REAL column-level REFERENCES;
--          MAINTAIN removal is verified in G (table-level can_maintain=false), not here.
--    Expected: only the SELECT set remains at column level (same as A-5b); NO REFERENCES,
--              and pin has no column-level privilege, for anon / authenticated.
--    Expected rows: exactly the column-level SELECT set and nothing else, i.e.
--      employees    : id, name, role, is_active, company_id, can_genka, can_admin  (SELECT)
--      genka_admins : id, name, is_active                                          (SELECT)
--      -> any REFERENCES row, any pin row, or any non-SELECT row = STOP / investigate.
--    Cross-check with G:
--      - G shows can_references=false at TABLE level (relacl) after the REVOKE.
--      - G-5 shows NO REFERENCES at COLUMN level (attacl).
--      Both together prove the REFERENCES seen against pin in A-3/A-4 was only the
--      table-level grant reflected onto every column (now removed by the table-level
--      REVOKE), and that no REAL column-level REFERENCES was ever present / left behind.
--      If G says can_references=false BUT G-5 still shows a REFERENCES row, that means a
--      REAL column-level REFERENCES grant existed and a column-level REVOKE is still needed.
select c.relname                         as table_name,
       a.attname                         as column_name,
       acl.grantee::regrole::text        as grantee,
       acl.privilege_type
from   pg_class c
join   pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
cross  join lateral aclexplode(a.attacl) as acl
where  c.relnamespace = 'public'::regnamespace
  and  c.relname in ('employees', 'genka_admins')
  and  acl.grantee::regrole::text in ('anon', 'authenticated')
order  by c.relname, a.attname, grantee, acl.privilege_type;


-- ============================================================
-- Production verification (app side; manual)
--   After REVOKE, confirm all three login flows still work and the
--   employee/admin lists still render (these use the column-level SELECT).
--   Revoking TRUNCATE / REFERENCES / TRIGGER / MAINTAIN does NOT affect login or
--   normal operations: login goes through create_*_session RPCs (EXECUTE grants,
--   untouched here), reads use column-level SELECT, and MAINTAIN only governs
--   VACUUM / ANALYZE / CLUSTER / REINDEX / LOCK TABLE, which the app never issues.
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
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.employees TO anon, authenticated;
-- GRANT TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.genka_admins TO anon, authenticated;
-- ============================================================
