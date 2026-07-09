-- ============================================================
-- Phase 4-F-1: public schema - revoke FUTURE-table default privileges
--   for anon / authenticated (ALTER DEFAULT PRIVILEGES ... ON TABLES)
--   Scope of THIS file: owner role `postgres` ONLY.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-09)
--   - ALTER DEFAULT PRIVILEGES body (1 statement, owner postgres) run manually by the
--     user in Supabase SQL Editor. Result: Success. No rows returned.
--   - No DB connection / SQL execution / Supabase CLI / psql from Claude Code CLI.
--   - Pre-check A-0/A/B/C/D all OK (no STOP condition hit):
--       A-0: PostgreSQL 17.6 (server_version_num=170006), is_pg17_or_newer=true
--       A  : owner postgres / public / 'r' had anon=arwdDxtm, authenticated=arwdDxtm
--            (supabase_admin had the same defaults; NON-SCOPE)
--       B  : owner postgres defaults for anon/authenticated =
--            DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
--       C  : global (all schemas) default privileges = 0 rows
--       D  : current_user=postgres, session_user=postgres, is_member_postgres=true
--   - Post-check after the ALTER:
--       G  : owner postgres / public / anon, authenticated = 0 rows (8 privileges removed)
--       G-2: owner postgres / public / postgres, service_role = 8 privileges retained (kept)
--       G-3: owner supabase_admin / public still grants anon / authenticated / postgres /
--            service_role the 8 privileges (NON-SCOPE; tracked as Phase 4-F-1b backlog)
--   - Effect: FUTURE public tables created by owner postgres no longer auto-grant
--     anon / authenticated. Existing tables unchanged.
--   See docs/db-migrations.md (2026-07-09 Phase 4-F-1 section) for the full record.
--
-- [PURPOSE]
--   Stop future public tables from auto-receiving broad privileges for anon /
--   authenticated. D-4 found default privileges (pg_default_acl) that grant
--   anon / authenticated ALL table privileges (SELECT/INSERT/UPDATE/DELETE/
--   TRUNCATE/REFERENCES/TRIGGER/MAINTAIN, i.e. `arwdDxtm`) on tables created in
--   schema public. This is the PG17 MAINTAIN re-grant source identified when
--   Phase 4-E-2 was closed (existing financial tables were already clean, but new
--   public tables would receive MAINTAIN again). This step narrows the DEFAULT for
--   FUTURE tables created by owner `postgres`; it does NOT change existing tables.
--
-- [SCOPE] (this file)
--   Owner role  : postgres ONLY.
--   Schema      : public only.
--   Object type : TABLES (relkind 'r' / defaclobjtype='r') only.
--   Grantees    : anon, authenticated.
--   Privileges  : SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - supabase_admin default privileges. NOTE: D-4 showed the SAME broad default
--     privileges (arwdDxtm for anon / authenticated on public tables) ALSO exist for
--     owner `supabase_admin`. They are NOT changed in this file because Supabase SQL
--     Editor typically runs as `postgres`, which may NOT be a member of
--     supabase_admin, so `ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin` could
--     fail with permission denied. Tracked as a BACKLOG item (Phase 4-F-1b candidate);
--     see pre-check A (supabase_admin row shown for reference) and G-3.
--   - service_role / postgres grantee default privileges (kept).
--   - Any schema other than public (storage / auth / realtime / graphql /
--     graphql_public / extensions / etc.) (kept).
--   - Default privileges for SEQUENCES / FUNCTIONS / TYPES / SCHEMAS (kept).
--   - Existing tables' direct grants (pg_class.relacl) -> Phase 4-F-2 and later.
--   - existing direct grants cleanup / stale policies cleanup (DROP POLICY)
--     -> Phase 4-F-2 / 4-F-3.
--   - RLS / policies / RPC definitions / EXECUTE / SECURITY DEFINER.
--   - HTML / JS / auth / PIN logic.
--   - docs/db-migrations.md / docs/roadmap.md (not updated in this file).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - A-0: server is PostgreSQL 16 or earlier -> STOP (MAINTAIN keyword invalid).
--   - B: owner postgres / schema public / objtype 'r' / grantee anon, authenticated
--        do NOT hold the expected default privileges (state differs from D-4) -> STOP.
--   - C: a GLOBAL default privileges entry `(all schemas)` (defaclnamespace = 0) with
--        table defaults for anon / authenticated EXISTS -> STOP.
--        Reason: a per-schema REVOKE (IN SCHEMA public) does NOT cancel a global
--        (all-schemas) default; both would need handling. Re-scope before running.
--   - D: current_user cannot act for role postgres (not a member / not superuser)
--        -> the ALTER would fail -> STOP.
--   - Anything indicating this would touch a schema other than public, or SEQUENCES /
--        FUNCTIONS / TYPES, or existing tables -> STOP and investigate.
--
-- [ROLLBACK] (only if needed; normally NOT used)
--   Re-GRANT the same privileges as default for owner postgres (FUTURE tables only).
--   See the rollback section at the end (commented out).
-- ============================================================


-- ============================================================
-- Pre-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- A-0. PostgreSQL version check (MAINTAIN keyword is PG17+ only)
--    Expected: server_version_num >= 170000. STOP if PostgreSQL 16 or earlier.
select version()                                        as pg_version,
       current_setting('server_version_num')::int       as server_version_num,
       (current_setting('server_version_num')::int >= 170000) as is_pg17_or_newer;

-- A. pg_default_acl raw listing (public schema, table/relation defaults)
--    Shows owner postgres (THIS file's target) and, for reference only,
--    supabase_admin (NOT changed here; see NON-SCOPE / backlog).
--    Expected: a row for owner postgres (objtype 'r', schema public); optionally a
--    supabase_admin row with the same broad default ACL.
select pg_get_userbyid(d.defaclrole)             as owner_role,
       n.nspname                                 as schema_name,
       d.defaclobjtype,
       d.defaclacl::text                         as default_acl_raw,
       case when pg_get_userbyid(d.defaclrole) = 'postgres'
            then 'TARGET (this file)'
            else 'reference only (NOT changed here)'
       end                                       as note
from   pg_default_acl d
join   pg_namespace n on n.oid = d.defaclnamespace
where  n.nspname = 'public'
  and  d.defaclobjtype = 'r'
order  by owner_role;

-- B. Expanded default privileges for anon / authenticated (owner postgres, aclexplode)
--    Expected: DELETE/INSERT/MAINTAIN/REFERENCES/SELECT/TRIGGER/TRUNCATE/UPDATE
--              for grantee anon and authenticated (owner postgres, schema public, table).
--    STOP if the expected privileges are not present (state differs from D-4).
select pg_get_userbyid(d.defaclrole)             as owner_role,
       n.nspname                                 as schema_name,
       pg_get_userbyid(acl.grantee)              as grantee,
       string_agg(acl.privilege_type, ', ' order by acl.privilege_type) as default_privileges
from   pg_default_acl d
join   pg_namespace n on n.oid = d.defaclnamespace
cross  join lateral aclexplode(d.defaclacl) as acl
where  n.nspname = 'public'
  and  d.defaclobjtype = 'r'
  and  pg_get_userbyid(d.defaclrole) = 'postgres'
  and  pg_get_userbyid(acl.grantee) in ('anon', 'authenticated')
group  by owner_role, schema_name, grantee
order  by grantee;

-- C. GLOBAL (all-schemas) default privileges guard (defaclnamespace = 0)
--    A per-schema REVOKE (IN SCHEMA public) does NOT cancel a global default.
--    Expected: 0 rows (no all-schemas table default for anon / authenticated).
--    STOP if any row is returned (a global default exists and must be handled too).
select pg_get_userbyid(d.defaclrole)             as owner_role,
       d.defaclobjtype,
       pg_get_userbyid(acl.grantee)              as grantee,
       string_agg(acl.privilege_type, ', ' order by acl.privilege_type) as default_privileges
from   pg_default_acl d
cross  join lateral aclexplode(d.defaclacl) as acl
where  d.defaclnamespace = 0            -- 0 = global / all schemas (no IN SCHEMA)
  and  d.defaclobjtype = 'r'
  and  pg_get_userbyid(acl.grantee) in ('anon', 'authenticated')
group  by owner_role, d.defaclobjtype, grantee
order  by owner_role, grantee;

-- D. Executing role & feasibility (can we ALTER DEFAULT PRIVILEGES FOR ROLE postgres?)
--    Expected: is_member_postgres = true (or current_user is a superuser).
--    STOP if current_user cannot act for role postgres.
select current_user,
       session_user,
       pg_has_role(current_user, 'postgres', 'MEMBER') as is_member_postgres;


-- ============================================================
-- ALTER DEFAULT PRIVILEGES body
--   NOTE: first place that modifies DB state. Run only after A-0/A/B/C/D pass
--         (no STOP condition hit).
--   NOTE: FUTURE tables only; existing tables are NOT affected.
--   NOTE: owner postgres ONLY. The supabase_admin equivalent is intentionally NOT
--         included here (see NON-SCOPE / backlog).
--   NOTE: single statement.
-- ============================================================

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES FROM anon, authenticated;


-- ============================================================
-- Post-check (SELECT only; does NOT modify DB state)
-- ============================================================

-- G. anon / authenticated default privileges removed (owner postgres; same shape as B)
--    Expected: 0 rows (owner postgres / public / table defaults for anon, authenticated).
select pg_get_userbyid(d.defaclrole)             as owner_role,
       pg_get_userbyid(acl.grantee)              as grantee,
       string_agg(acl.privilege_type, ', ' order by acl.privilege_type) as default_privileges
from   pg_default_acl d
join   pg_namespace n on n.oid = d.defaclnamespace
cross  join lateral aclexplode(d.defaclacl) as acl
where  n.nspname = 'public'
  and  d.defaclobjtype = 'r'
  and  pg_get_userbyid(d.defaclrole) = 'postgres'
  and  pg_get_userbyid(acl.grantee) in ('anon', 'authenticated')
group  by owner_role, grantee
order  by grantee;

-- G-2. service_role / postgres defaults unchanged (owner postgres)
--    Expected: service_role (and any owner/self) default privileges still present.
select pg_get_userbyid(d.defaclrole)             as owner_role,
       pg_get_userbyid(acl.grantee)              as grantee,
       string_agg(acl.privilege_type, ', ' order by acl.privilege_type) as default_privileges
from   pg_default_acl d
join   pg_namespace n on n.oid = d.defaclnamespace
cross  join lateral aclexplode(d.defaclacl) as acl
where  n.nspname = 'public'
  and  d.defaclobjtype = 'r'
  and  pg_get_userbyid(d.defaclrole) = 'postgres'
  and  pg_get_userbyid(acl.grantee) in ('service_role', 'postgres')
group  by owner_role, grantee
order  by grantee;

-- G-3. supabase_admin defaults (reference only; NOT a pass/fail check for this file)
--    supabase_admin default privileges are NOT changed by this file, so anon /
--    authenticated may STILL appear here. This is expected and tracked as a backlog
--    item (Phase 4-F-1b candidate). Informational only.
select pg_get_userbyid(d.defaclrole)             as owner_role,
       pg_get_userbyid(acl.grantee)              as grantee,
       string_agg(acl.privilege_type, ', ' order by acl.privilege_type) as default_privileges
from   pg_default_acl d
join   pg_namespace n on n.oid = d.defaclnamespace
cross  join lateral aclexplode(d.defaclacl) as acl
where  n.nspname = 'public'
  and  d.defaclobjtype = 'r'
  and  pg_get_userbyid(d.defaclrole) = 'supabase_admin'
  and  pg_get_userbyid(acl.grantee) in ('anon', 'authenticated')
group  by owner_role, grantee
order  by grantee;


-- ============================================================
-- Rollback (only if needed; temporary restore of FUTURE-table defaults)
--   NOTE: normally NOT run (kept commented out). owner postgres only.
--   NOTE: restores the default for FUTURE tables only; it does NOT retroactively
--         affect tables created after the REVOKE and before this rollback.
-- ============================================================
-- ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
--   GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
--   ON TABLES TO anon, authenticated;
-- ============================================================
