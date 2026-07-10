-- ============================================================
-- Phase 4-F-2B-3: remove residual direct SELECT / INSERT / UPDATE grants on
--   public.admin_sessions and public.employee_sessions for anon / authenticated.
-- ============================================================
-- [STATUS] EXECUTED (2026-07-11)
--   - Manually executed by the user in the Supabase SQL Editor, ONE statement at a
--     time, with a login/logout smoke test between the two statements.
--       * admin_sessions REVOKE:    "Success. No rows returned".
--       * employee_sessions REVOKE: "Success. No rows returned".
--   - Pre-checks S-1..S-9 all passed (no STOP condition hit).
--   - Inter-statement smoke tests all passed:
--       * after admin_sessions: admin-app / genka-app new login, screen, RPC,
--         logout all OK.
--       * after employee_sessions: employee (index) new login, screen, daily-report
--         (日報) RPC, logout all OK.
--   - Post-checks P-1..P-7 all passed (see docs/db-migrations.md 2026-07-11 section).
--   - DB execution is done by the user. No DB connection / Supabase CLI / psql from
--     Claude Code CLI. All DB execution and checks (pre / post) are performed
--     manually by the user in the Supabase SQL Editor.
--   - The pre-check results recorded below (S-1..S-9) reflect the user's Supabase
--     SQL Editor run; the queries are kept re-runnable.
--   - Recorded in docs/db-migrations.md (2026-07-11 Phase 4-F-2B-3 section).
--
-- [PURPOSE]
--   Remove the direct SELECT / INSERT / UPDATE grant currently held by
--   anon / authenticated on public.admin_sessions and public.employee_sessions.
--     - Repository investigation and live DB introspection found NO in-app session
--       access path that uses these anon / authenticated table grants:
--         * Front-end: 0 direct table access (no .from('admin_sessions') /
--           .from('employee_sessions'); no dynamic table-name usage). All session
--           handling is via .rpc(...) calls only.
--         * RPC: 42 session-referencing routines, all SECURITY DEFINER = true,
--           owner = postgres (RLS-bypass path). Session writes happen only inside
--           these SECURITY DEFINER routines, which run with the owner's privileges
--           and do NOT depend on the anon / authenticated table grants.
--             - session INSERT routines: 2 (create_admin_session,
--               create_employee_session).
--             - session UPDATE routines: 0 (no routine UPDATEs the session tables;
--               there is no session-extension mechanism).
--             - session DELETE routines: 4 (create_* cleanup + revoke_* logout).
--         * RLS: both tables have RLS enabled with 0 policies (deny-by-default),
--           so the residual SELECT / INSERT / UPDATE grants are already inert for
--           direct access even while the grants exist.
--     - Login / logout continue to work AFTER the revoke, because they go through
--       SECURITY DEFINER RPCs whose EXECUTE grant is unchanged by this file.
--     - DB management operations performed via privileged roles are OUT OF SCOPE
--       for this REVOKE (this file only touches anon / authenticated).
--   This file targets EXISTING table direct grants (pg_class.relacl) only.
--
-- [SCOPE]
--   Schema     : public only.
--   Tables     : admin_sessions, employee_sessions ONLY.
--   Grantees   : anon, authenticated ONLY.
--   Privileges : SELECT, INSERT, UPDATE ONLY.
--
-- [NON-SCOPE] (intentionally NOT touched here)
--   - DELETE grant (already false for anon / authenticated; not listed).
--   - postgres / service_role / table owner privileges (not changed).
--   - RLS (not enabled/disabled/forced here).
--   - policies (none exist; no CREATE / DROP POLICY).
--   - RPC / function definitions / EXECUTE grants (login / logout RPCs untouched).
--   - view / materialized view definitions.
--   - trigger definitions.
--   - foreign key / constraint definitions, internal constraint triggers, and
--     child-table privileges (not changed here).
--   - HTML / JS / auth / PIN logic.
--   - default privileges (pg_default_acl).
--   - any other table.
--   - docs/roadmap.md, docs/db-migrations.md (updated separately in the record step).
--
-- [STOP CONDITIONS] (if any is hit during pre-check, do NOT run the body; stop & report)
--   - Any target grant differs from the recorded pre-check (e.g. SELECT / INSERT /
--     UPDATE already false, or DELETE now true) -> STOP and re-investigate.
--   - Any policy exists on either session table -> STOP (the deny-by-default
--     premise changed; re-check first).
--   - Any RPC EXECUTE change: the 4 login / logout RPCs are not EXECUTE = true for
--     anon / authenticated -> STOP (revoke would break the login entry path).
--   - Any SECURITY INVOKER routine references the session tables, OR any routine's
--     owner lacks the needed privilege, OR body_updates_sessions = true for any
--     routine -> STOP (a live access path may depend on the grants).
--   - Any view / materialized view referencing the session tables is returned
--     -> STOP (assess manually before the body).
--   - Any trigger on the session tables, or trigger function writing them
--     -> STOP.
--   - Any new front-end direct access to the session tables is discovered -> STOP.
--   - New / unexpected routine / trigger / view / FK dependency is found -> STOP.
--   - A new-login or logout smoke test fails after a statement -> STOP (consider the
--     ROLLBACK for the just-revoked table).
--   - The body would change any privilege / table outside SCOPE -> STOP.
--
-- [ROLLBACK] (see the commented section at the end)
--   Assuming that no OTHER related state has been changed (policies, function / view
--   definitions, triggers, ownership, default privileges, etc.), the commented GRANT
--   restores the TABLE-PRIVILEGE layer to its pre-REVOKE state -- i.e. it re-adds
--   exactly the direct SELECT / INSERT / UPDATE grant this file removed. This is NOT
--   a claim of full system restoration; it only reverses the direct grant change.
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Recorded results below reflect the user's Supabase SQL Editor run prior to this
--   file. The queries are re-runnable to re-confirm before executing the body.
-- ============================================================

-- S-1. session tables existence + RLS state.
--    Recorded: both tables exist, relkind = 'r', rls_enabled = true, rls_forced = false.
--    STOP if a table is missing, or rls_enabled is not true (unexpected).
select
  n.nspname             as schema_name,
  c.relname             as table_name,
  c.relkind             as relkind,          -- expected 'r' (ordinary table)
  c.relrowsecurity      as rls_enabled,      -- expected true
  c.relforcerowsecurity as rls_forced        -- expected false
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('admin_sessions', 'employee_sessions')
order by c.relname;

-- S-2. anon / authenticated effective CRUD on the session tables.
--    Recorded: SELECT = true, INSERT = true, UPDATE = true, DELETE = false
--      (both tables x both roles).
--    POST-CHECK Q-1 must show SELECT / INSERT / UPDATE = false afterwards, DELETE
--    unchanged (false).
--    STOP if SELECT / INSERT / UPDATE is already false (inconsistent), or DELETE true.
select
  v.object_name,
  v.role_name,
  has_table_privilege(v.role_name, v.object_name, 'SELECT') as can_select,
  has_table_privilege(v.role_name, v.object_name, 'INSERT') as can_insert,
  has_table_privilege(v.role_name, v.object_name, 'UPDATE') as can_update,
  has_table_privilege(v.role_name, v.object_name, 'DELETE') as can_delete
from (values
  ('anon',          'public.admin_sessions'),
  ('authenticated', 'public.admin_sessions'),
  ('anon',          'public.employee_sessions'),
  ('authenticated', 'public.employee_sessions')
) as v(role_name, object_name)
order by v.object_name, v.role_name;

-- S-3. session tables pg_policies (all rows).
--    Recorded: 0 rows (both tables have RLS enabled with no policies -> deny-by-default).
--    STOP if any policy is present (deny-by-default premise changed; re-check first).
select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('admin_sessions', 'employee_sessions')
order by tablename, policyname;

-- S-4. relacl / aclexplode: explicit anon / authenticated SELECT / INSERT / UPDATE grant.
--    Recorded: anon / authenticated hold SELECT / INSERT / UPDATE only; DELETE absent;
--      postgres / service_role are OUT OF SCOPE (not listed here).
--    STOP if a DELETE row is returned for anon / authenticated (inconsistent with
--    the recorded state), or if the SELECT / INSERT / UPDATE rows are absent.
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname in ('admin_sessions', 'employee_sessions')
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
order by c.relname, grantee, acl.privilege_type;

-- S-5. LIVE dependency scan: routines that reference the session tables (body text
--    search), with SECURITY DEFINER flag, owner, owner privileges, RLS-bypass
--    conditions, and whether the body writes the session tables. prokind is
--    restricted to 'f' / 'p' INSIDE a MATERIALIZED CTE so pg_get_functiondef is
--    never called on aggregate / window routines.
--    Recorded: 42 referencing routines, all SECURITY DEFINER = true, owner = postgres,
--      owner required privileges all true, RLS-bypass conditions satisfied,
--      search_path fixed. body_inserts_sessions = true for 2 routines
--      (create_admin_session, create_employee_session); body_updates_sessions = true
--      for 0 routines; body_deletes_sessions = true for 4 routines.
--    STOP (and check manually) if any of the following is returned:
--      * any SECURITY INVOKER routine referencing the session tables;
--      * any routine whose owner lacks the privilege needed to read / write them;
--      * body_updates_sessions = true for ANY routine (repo says 0);
--      * owner is not superuser AND not bypassrls AND not (table-owner with
--        FORCE RLS = false) -- i.e. no valid RLS-bypass basis.
with target_routines as materialized (
  select
    p.oid,
    p.prosecdef,
    p.proowner
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where p.prokind in ('f', 'p')
    and n.nspname not in ('pg_catalog', 'information_schema')
),
tbls as (
  select
    max(case when c.relname = 'admin_sessions'    then c.relowner end) as as_owner,
    max(case when c.relname = 'employee_sessions' then c.relowner end) as es_owner,
    bool_or(c.relname = 'admin_sessions'    and c.relforcerowsecurity) as as_force_rls,
    bool_or(c.relname = 'employee_sessions' and c.relforcerowsecurity) as es_force_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('admin_sessions', 'employee_sessions')
)
select
  r.oid::regprocedure::text                                          as function_signature,
  r.prosecdef                                                        as is_security_definer,
  pg_get_userbyid(r.proowner)                                        as owner,
  has_table_privilege(r.proowner, 'public.admin_sessions', 'SELECT')    as o_as_select,
  has_table_privilege(r.proowner, 'public.admin_sessions', 'INSERT')    as o_as_insert,
  has_table_privilege(r.proowner, 'public.admin_sessions', 'DELETE')    as o_as_delete,
  has_table_privilege(r.proowner, 'public.employee_sessions', 'SELECT') as o_es_select,
  has_table_privilege(r.proowner, 'public.employee_sessions', 'INSERT') as o_es_insert,
  has_table_privilege(r.proowner, 'public.employee_sessions', 'DELETE') as o_es_delete,
  ro.rolsuper                                                        as owner_is_superuser,
  ro.rolbypassrls                                                    as owner_has_bypassrls,
  (r.proowner = t.as_owner)                                          as owner_is_as_table_owner,
  (r.proowner = t.es_owner)                                          as owner_is_es_table_owner,
  t.as_force_rls,
  t.es_force_rls,
  (pg_get_functiondef(r.oid) ~* '\minsert\s+into\s+(public\.)?(admin_sessions|employee_sessions)\M') as body_inserts_sessions,
  (pg_get_functiondef(r.oid) ~* '\mupdate\s+(public\.)?(admin_sessions|employee_sessions)\M')        as body_updates_sessions,
  (pg_get_functiondef(r.oid) ~* '\mdelete\s+from\s+(public\.)?(admin_sessions|employee_sessions)\M') as body_deletes_sessions
from target_routines r
cross join tbls t
join pg_roles ro on ro.oid = r.proowner
where pg_get_functiondef(r.oid) ilike '%admin_sessions%'
   or pg_get_functiondef(r.oid) ilike '%employee_sessions%'
order by function_signature;

-- S-6. login / logout RPC EXECUTE for anon / authenticated (entry path must survive).
--    Recorded: all 8 rows EXECUTE = true
--      (create_admin_session, revoke_admin_session,
--       create_employee_session, revoke_employee_session).
--    STOP if any row is false (revoke would break the login / logout entry path).
--    POST-CHECK: these must remain true after the body (unchanged by this file).
select
  v.role_name,
  v.func_sig,
  has_function_privilege(v.role_name, v.func_sig, 'EXECUTE') as can_execute
from (values
  ('anon',          'public.create_admin_session(uuid, text)'),
  ('authenticated', 'public.create_admin_session(uuid, text)'),
  ('anon',          'public.revoke_admin_session(text)'),
  ('authenticated', 'public.revoke_admin_session(text)'),
  ('anon',          'public.create_employee_session(uuid, text)'),
  ('authenticated', 'public.create_employee_session(uuid, text)'),
  ('anon',          'public.revoke_employee_session(text)'),
  ('authenticated', 'public.revoke_employee_session(text)')
) as v(role_name, func_sig)
order by v.func_sig, v.role_name;

-- S-7. LIVE dependency scan: views / materialized views referencing the session tables.
--    Recorded: 0 rows.
--    STOP if ANY row is returned: do NOT auto-conclude "safe". Manually assess each
--    (security_invoker vs owner-privilege, the owner's rights, and reachability by
--    anon / authenticated) BEFORE the body.
select
  c.oid::regclass                                as view_name,
  c.relkind                                      as relkind,   -- 'v' = view, 'm' = matview
  pg_get_userbyid(c.relowner)                    as owner,
  coalesce(
    array_to_string(c.reloptions, ',') ilike '%security_invoker=true%',
    false
  )                                              as is_security_invoker
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('v', 'm')
  and n.nspname not in ('pg_catalog', 'information_schema')
  and (
        pg_get_viewdef(c.oid) ilike '%admin_sessions%'
     or pg_get_viewdef(c.oid) ilike '%employee_sessions%'
      )
order by view_name;

-- S-8. LIVE dependency scan: triggers on the session tables, and trigger functions
--    that write them. pg_get_functiondef is called only on user (non-internal)
--    trigger functions here.
--    Recorded: 0 user-defined triggers on the session tables, and 0 trigger functions
--      that INSERT / UPDATE / DELETE them.
--    STOP if ANY row is returned (a write path may depend on these grants).
select
  tn.nspname                              as table_schema,
  t.tgname                                as trigger_name,
  c.relname                               as on_table,
  p.oid::regprocedure::text               as trigger_function,
  p.prosecdef                             as is_security_definer,
  pg_get_userbyid(p.proowner)             as owner
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace tn
  on tn.oid = c.relnamespace
join pg_proc  p on p.oid = t.tgfoid
where not t.tgisinternal
  and (
        (
          tn.nspname = 'public'
          and c.relname in ('admin_sessions', 'employee_sessions')
        )
     or pg_get_functiondef(p.oid) ~* '\m(insert\s+into|update|delete\s+from)\s+(public\.)?(admin_sessions|employee_sessions)\M'
      )
order by table_schema, on_table, t.tgname;

-- S-9. FK / unique constraints on / referencing the session tables (informational only).
--    Recorded:
--      * admin_sessions.admin_id    -> genka_admins(id) ON DELETE CASCADE.
--      * employee_sessions.employee_id -> employees(id) ON DELETE CASCADE.
--      * token_hash UNIQUE, one per table.
--      * NO child table references the session tables (no reverse FK).
--    This list is for information confirmation only. This file does NOT change FK
--    definitions, internal constraint triggers, or child-table privileges. Revoking
--    the anon / authenticated SELECT / INSERT / UPDATE direct grant does not change
--    any FK definition. FK existence alone is NOT a STOP condition; a reverse FK
--    (a child table referencing the session tables) WOULD be a STOP-and-review signal.
select
  conrelid::regclass          as child_table,
  confrelid::regclass         as parent_table,
  conname                     as constraint_name,
  pg_get_constraintdef(oid)   as constraint_def
from pg_constraint
where contype in ('f', 'u')
  and (
        conrelid  in ('public.admin_sessions'::regclass, 'public.employee_sessions'::regclass)
     or confrelid in ('public.admin_sessions'::regclass, 'public.employee_sessions'::regclass)
      )
order by child_table, constraint_name;


-- ============================================================
-- EXECUTION BODY
--   NOTE: this is the FIRST place that modifies DB state. Run ONLY after the
--         pre-checks (S-1..S-9) are re-confirmed with no STOP condition hit.
--   NOTE: 2 statements. Do NOT run them together. Run ONE statement at a time in the
--         Supabase SQL Editor, and perform the smoke test below between them.
--   NOTE: SELECT / INSERT / UPDATE are the ONLY privileges listed. DELETE is never
--         listed. No other table. No DROP POLICY. No GRANT.
--   NOTE: re-runnable -- REVOKE of an already-absent privilege is a no-op.
--
--   -- Statement 1: admin_sessions --------------------------------------------------
--   After running statement 1, SMOKE TEST (before running statement 2):
--     * admin-app: perform a NEW login.
--     * genka-app: perform a NEW login.
--     * exercise a post-login RPC in each.
--     * logout in each.
--     If any of these fails -> STOP (consider the ROLLBACK for admin_sessions).
--
--   -- Statement 2: employee_sessions -----------------------------------------------
--   After running statement 2, SMOKE TEST:
--     * index.html: perform a NEW employee login.
--     * exercise a post-login daily-report (日報) RPC.
--     * logout.
--     If any of these fails -> STOP (consider the ROLLBACK for employee_sessions).
-- ============================================================

REVOKE SELECT, INSERT, UPDATE
ON TABLE public.admin_sessions
FROM anon, authenticated;

REVOKE SELECT, INSERT, UPDATE
ON TABLE public.employee_sessions
FROM anon, authenticated;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- Q-1. anon / authenticated effective CRUD on the session tables.
--    Expected: SELECT = false, INSERT = false, UPDATE = false, DELETE = false
--      (both tables x both roles).
--    STOP if SELECT / INSERT / UPDATE is still true, or DELETE changed vs S-2.
select
  v.object_name,
  v.role_name,
  has_table_privilege(v.role_name, v.object_name, 'SELECT') as can_select,
  has_table_privilege(v.role_name, v.object_name, 'INSERT') as can_insert,
  has_table_privilege(v.role_name, v.object_name, 'UPDATE') as can_update,
  has_table_privilege(v.role_name, v.object_name, 'DELETE') as can_delete
from (values
  ('anon',          'public.admin_sessions'),
  ('authenticated', 'public.admin_sessions'),
  ('anon',          'public.employee_sessions'),
  ('authenticated', 'public.employee_sessions')
) as v(role_name, object_name)
order by v.object_name, v.role_name;

-- Q-2. relacl / aclexplode: anon / authenticated CRUD direct grant is gone.
--    Expected: 0 rows. STOP if any row remains.
select
  c.relname                    as table_name,
  acl.grantee::regrole::text   as grantee,
  acl.privilege_type
from pg_class c
cross join lateral aclexplode(c.relacl) as acl
where c.relnamespace = 'public'::regnamespace
  and c.relkind = 'r'
  and c.relname in ('admin_sessions', 'employee_sessions')
  and acl.grantee::regrole::text in ('anon', 'authenticated')
  and acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
order by c.relname, grantee, acl.privilege_type;

-- Q-3. session tables RLS / policy state (unchanged).
--    Expected: rls_enabled = true, rls_forced = false; 0 policies (both tables).
--    STOP if RLS changed or any policy appeared.
select
  n.nspname             as schema_name,
  c.relname             as table_name,
  c.relrowsecurity      as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  (select count(*) from pg_policies p
    where p.schemaname = 'public' and p.tablename = c.relname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('admin_sessions', 'employee_sessions')
order by c.relname;

-- Q-4. login / logout RPC EXECUTE retained.
--    Expected: all 8 rows EXECUTE = true (unchanged by this file; table REVOKE does
--    not affect function EXECUTE grants).
select
  v.role_name,
  v.func_sig,
  has_function_privilege(v.role_name, v.func_sig, 'EXECUTE') as can_execute
from (values
  ('anon',          'public.create_admin_session(uuid, text)'),
  ('authenticated', 'public.create_admin_session(uuid, text)'),
  ('anon',          'public.revoke_admin_session(text)'),
  ('authenticated', 'public.revoke_admin_session(text)'),
  ('anon',          'public.create_employee_session(uuid, text)'),
  ('authenticated', 'public.create_employee_session(uuid, text)'),
  ('anon',          'public.revoke_employee_session(text)'),
  ('authenticated', 'public.revoke_employee_session(text)')
) as v(role_name, func_sig)
order by v.func_sig, v.role_name;


-- ============================================================
-- ROLLBACK (commented out; run manually only if needed)
--   Assuming NO other related state has been changed (policies, function / view
--   definitions, triggers, ownership, default privileges, etc.), the GRANT below
--   restores the TABLE-PRIVILEGE layer to its pre-REVOKE state -- i.e. it re-adds
--   exactly the direct SELECT / INSERT / UPDATE grant this file removed. This is NOT
--   a claim of full system restoration; it only reverses the direct grant change.
--   Roll back the just-revoked table if its smoke test fails.
-- ============================================================
-- GRANT SELECT, INSERT, UPDATE
-- ON TABLE public.admin_sessions
-- TO anon, authenticated;
--
-- GRANT SELECT, INSERT, UPDATE
-- ON TABLE public.employee_sessions
-- TO anon, authenticated;
-- ============================================================
