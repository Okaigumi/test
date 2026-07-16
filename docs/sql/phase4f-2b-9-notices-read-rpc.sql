-- ============================================================
-- Phase 4-F-2B-9-a: add a secure read RPC for public.notices
--   (list_notices_secure) so that index.html can stop reading
--   public.notices directly (loadNotice).
-- ============================================================
-- [STATUS] EXECUTED 2026-07-16
--   - This file ONLY adds ONE new read RPC (additive). It does NOT touch any table
--     grant, RLS, policy, existing routine, or the front-end.
--   - DB execution is done by the user, manually, in the Supabase SQL Editor.
--     Claude Code CLI performs NO DB connection / NO SQL execution / NO Supabase CLI /
--     NO psql. All pre-check / body / post-check / smoke were run by the user.
--   - Run order was: PRE-CHECK -> EXECUTION BODY (single transaction) -> POST-CHECK ->
--     SMOKE TEST. ROLLBACK not used. (Only the confirmed POST-CHECK items are recorded
--     under [POST-CHECK RESULT] below; not every POST-1..POST-16 is asserted as executed.)
--
--   [DB EXECUTION RESULT] (Supabase SQL Editor, by the user, 2026-07-16)
--     - The user ran the EXECUTION BODY manually ONCE (single transaction,
--       BEGIN..COMMIT; one plain CREATE FUNCTION + owner / EXECUTE settings).
--       Result: Success. No rows returned. The body was NOT re-run afterwards.
--     - Created: public.list_notices_secure(text).
--     - No DB connection / Supabase CLI / psql from Claude Code CLI.
--     - The EXECUTION BODY must NOT be re-run. If re-creation is ever needed, prepare a
--       separate, independently reviewed dedicated SQL (do NOT re-run this BODY).
--
--   [PRE-CHECK RESULT] (P-1..P-9 / P-8b, Supabase SQL Editor, 2026-07-16 -- matched C-1..C-12)
--     - notices: relkind 'r', RLS true, FORCE RLS false, owner postgres.
--     - anon / authenticated: SELECT = true, other 7 privileges = false; raw ACL
--       {postgres=arwdDxtm, anon=r, authenticated=r, service_role=arwdDxtm}; no PUBLIC,
--       no grant option; column-level ACL 0 rows.
--     - notices columns 9 / constraints 2 (notices_pkey, notices_attachment_type_check,
--       both validated) / index notices_pkey only (valid/ready/unique/primary).
--     - policy notices_read_all: PERMISSIVE, {public}, SELECT, qual true, with_check null.
--     - counts: total 4 / active 1 / inactive 3 / null 0.
--     - list_notices_secure did NOT pre-exist (P-8 = 0 rows) -> plain CREATE safe.
--     - employee-session verification columns present; existing notices RPCs (5) baseline
--       recorded (SECURITY DEFINER / VOLATILE / owner postgres / search_path; KNOWN PUBLIC
--       EXECUTE present).
--
--   [POST-CHECK RESULT] (Supabase SQL Editor, 2026-07-16 -- only the checks actually run
--    and confirmed are recorded below; NOT asserting every POST-1..POST-16 was executed)
--     - list_notices_secure attributes / return type: SECURITY DEFINER = true, STABLE,
--       owner postgres, search_path public, extensions; identity arg
--       "session_token_input text"; RETURNS TABLE content text / attachment_url text /
--       attachment_type text / attachment_name text.
--     - list_notices_secure EXECUTE ACL: anon / authenticated / postgres / service_role
--       EXECUTE, is_grantable = false; NO PUBLIC EXECUTE.
--     - notices anon / authenticated table privileges UNCHANGED (SELECT only, other 7 false).
--     - policy notices_read_all UNCHANGED.
--     - notices counts UNCHANGED (total 4 / active 1 / inactive 3 / null 0).
--     - existing notices RPCs (5) attributes / return type UNCHANGED.
--     - existing notices RPCs (5) EXECUTE ACL UNCHANGED (KNOWN PUBLIC EXECUTE left as-is,
--       as baseline).
--
--   [SMOKE TEST RESULT] (2026-07-16; no real token recorded)
--     - NEGATIVE (Supabase SQL Editor): list_notices_secure rejected an invalid token with
--       SQLSTATE P0001 'Invalid or expired session'; the DO block returned
--       "Success. No rows returned" (no unexpected success).
--     - POSITIVE (valid employee session): status 200, error null, count = 1 (matches the
--       active notices count 1); returned columns exactly content / attachment_url /
--       attachment_type / attachment_name (only_expected_columns = true).
--
--   [OUTCOME]
--     - list_notices_secure is created and verified. This completes ONLY the
--       "read RPC DB execution" stage (2B-9-a) of Phase 4-F-2B-9.
--     - ROLLBACK: NOT executed (kept as commented reference only).
--
--   [STILL NOT DONE] (Phase 4-F-2B-9 is NOT complete; separate, later steps)
--     - 2B-9-b: front-end migration of index.html loadNotice() (still a direct read).
--     - 2B-9-c: REVOKE SELECT ON notices FROM anon, authenticated (NOT done; SELECT kept)
--       and DROP POLICY notices_read_all (NOT done; policy still exists).
--     - Next step is 2B-9-b (front-end migration).
--
-- [PURPOSE]
--   index.html currently reads public.notices via a direct SELECT (the only direct read):
--     index.html loadNotice():
--       sb.from('notices').select('*').eq('is_active', true)
--         .order('created_at', { ascending: false })
--   loadNotice() runs only inside startApp() (after an employee session is created /
--   restored); there is NO pre-login read path. The front-end only displays 4 columns
--   (content / attachment_url / attachment_type / attachment_name) and uses is_active /
--   created_at solely as filter / order.
--   This step adds a SECURITY DEFINER read RPC so the direct read can later be migrated
--   (front-end step) and the direct SELECT grant can later be revoked (revoke step).
--   This is the standard 3-stage migration (read RPC -> front-end move -> direct read
--   shutdown), matching phase4f-2b-7-subcontractors-read-rpc.sql and
--   phase4f-2b-8-sites-site-assignments-read-rpc.sql.
--
--   ONE RPC:
--     public.list_notices_secure(text)  -- employee session, index.html loadNotice
--       -> verifies the employee session INLINE (same method as list_sites_secure /
--          list_subcontractors_secure / list_machines_secure), returns active notices,
--          only the 4 columns the worker screen renders.
--
--   THIS FILE IS ADDITIVE ONLY. The following are SEPARATE, LATER steps and are
--   explicitly NOT performed here:
--     - front-end migration of loadNotice() (2B-9-b),
--     - any REVOKE on notices (SELECT stays granted) (2B-9-c),
--     - any policy change / DROP POLICY (notices_read_all left exactly as-is) (2B-9-c),
--     - any change to existing notices RPCs (5) or Storage (notice-attachments bucket).
--
-- [SCOPE]
--   Add ONE function and set owner + EXECUTE privileges on that NEW function only.
--
-- [NON-GOALS] (intentionally NOT touched here)
--   - index.html / admin-app.html / genka-app.html (front-end step comes later).
--   - public.notices table grants (SELECT NOT revoked here; anon / authenticated keep SELECT).
--   - policy notices_read_all (NO change, NO drop).
--   - RLS / FORCE RLS on notices.
--   - notices data / columns / constraints / indexes.
--   - existing notices RPCs (list_notices_admin_secure / create_notice_secure /
--     update_notice_secure / update_notice_attachment_secure /
--     delete_notice_attachment_secure) -- NOT modified.
--   - Storage notice-attachments bucket / its policies.
--   - docs/db-migrations.md, docs/roadmap.md (updated separately in a record step).
--
--   [KNOWN, INTENTIONALLY UNCHANGED] PUBLIC EXECUTE currently exists on the 5 existing
--   notices RPCs (they were created with GRANT ... TO anon, authenticated but NO
--   REVOKE ... FROM PUBLIC). This is recorded as baseline in P-8b / POST-16 but is OUT OF
--   SCOPE for this additive file and is NOT modified here (and is NOT a stop condition).
--
-- [MEASURED PRE-CHECK RESULT] (Supabase SQL Editor, by the user, before this file --
--   C-1..C-12; expected values referenced by the P-* queries below and POST-* invariants)
--   - C-1: notices -- relkind 'r', RLS true, FORCE RLS false, owner postgres.
--   - C-2/C-3: anon SELECT = true / authenticated SELECT = true, other 7 = false;
--     raw ACL {postgres=arwdDxtm/postgres, anon=r/postgres, authenticated=r/postgres,
--     service_role=arwdDxtm/postgres}; NO PUBLIC table privilege; no grant option.
--   - C-4: column-level ACL 0 rows.
--   - C-5: columns -- id uuid NOT NULL default gen_random_uuid(); content text NOT NULL;
--     is_active boolean NOT NULL default true; created_at timestamptz NOT NULL default now();
--     attachment_url text NULL; attachment_path text NULL; attachment_type text NULL;
--     attachment_name text NULL; updated_at timestamptz NULL.
--     (The 4 returned columns content / attachment_url / attachment_type / attachment_name
--      are all text -- matches the RPC RETURNS TABLE below.)
--   - C-6: constraints -- notices_pkey PRIMARY KEY(id) validated;
--     notices_attachment_type_check (attachment_type IS NULL OR
--     attachment_type IN ('image','pdf')) validated.
--   - C-7: index -- notices_pkey only; valid / ready / unique / primary = true.
--   - C-8: policy -- notices_read_all: PERMISSIVE, roles {public}, cmd SELECT, qual true,
--     with_check null. (Left exactly as-is here.)
--   - C-9: existing notices RPCs (5): list_notices_admin_secure(text),
--     create_notice_secure(text, text, boolean),
--     update_notice_secure(text, uuid, text, boolean),
--     update_notice_attachment_secure(text, uuid, text, text, text, text),
--     delete_notice_attachment_secure(text, uuid) -- all SECURITY DEFINER, VOLATILE,
--     owner postgres, search_path public, extensions, 9-column return; EXECUTE ACL for
--     PUBLIC / anon / authenticated / postgres / service_role, no grant option.
--     KNOWN PUBLIC EXECUTE (baseline only, NOT changed here).
--   - C-10: employee-session inline verification columns present --
--     employee_sessions.employee_id uuid NOT NULL / token_hash text NOT NULL /
--     expires_at timestamptz NOT NULL; employees.id uuid NOT NULL /
--     is_active boolean NOT NULL. _verify_employee_session does NOT exist (inline method).
--   - C-11: public.list_notices_secure -- 0 rows, no overload.
--   - C-12: notices total 4 / active 1 / inactive 3 / null_active 0. (Counts are CONTEXT
--     baseline; ordinary data changes alone are NOT a stop condition. Use the value from
--     the PRE-CHECK run IMMEDIATELY before the body as the POST-CHECK / SMOKE reference.)
--
-- [RE-RUN SAFETY]
--   - The body uses plain CREATE FUNCTION (NOT CREATE OR REPLACE). P-8 must return 0 rows
--     (no pre-existing function of this name). Plain CREATE is the second line of defence:
--     an unexpected pre-existing function makes the body ERROR OUT (and the whole
--     BEGIN..COMMIT roll back) instead of being silently replaced (fail closed).
--   - The whole body runs as ONE transaction (BEGIN..COMMIT), so a failure rolls back the
--     entire step and leaves nothing half-created.
--   - FIRST-run only. Do NOT re-run the body as-is after it has succeeded (a second run
--     stops with "function already exists" and rolls back). Re-creating requires an
--     explicit ROLLBACK (DROP FUNCTION; see the end) first.
--   - PRE-CHECK / POST-CHECK / SMOKE are OUTSIDE this transaction (run separately).
--
-- [STOP CONDITIONS] (if any is hit in the pre-check, do NOT run the body; stop & report)
--   - P-1: notices missing, relkind <> 'r', RLS <> true, FORCE RLS <> false,
--          or owner <> postgres.
--   - P-3: any of content / attachment_url / attachment_type / attachment_name missing or
--          not of type text (the RPC returns these 4 as text).
--   - P-8: public.list_notices_secure already exists (collision / overload).
--   - P-9: employee_sessions (employee_id / token_hash / expires_at) or employees
--          (id / is_active) verification columns missing / wrong type.
--   - The body would change any table grant / policy / RLS / existing routine -> STOP.
--   NOTE: C-12 count drift by ordinary data changes is NOT a stop condition.
--   NOTE: KNOWN PUBLIC EXECUTE on the 5 existing notices RPCs is baseline only and is NOT
--   a stop condition for this file.
--
-- [ROLLBACK] (commented section at the end -- NOT executed)
--   DROP FUNCTION for exactly the one function this file adds. Additive-only, so dropping
--   it fully reverses this step (front-end not yet migrated; nothing depends on it).
-- ============================================================


-- ============================================================
-- PRE-CHECK (SELECT only; does NOT modify DB state)
--   Run each query and record the result BEFORE the body. Any STOP condition -> stop.
-- ============================================================

-- P-1. notices table attributes.
--    Expected: 1 row, relkind = 'r', rls_enabled = true, rls_forced = false,
--      owner = postgres. STOP if the table is missing or anything differs.
select
  n.nspname                   as schema_name,
  c.relname                   as table_name,
  c.relkind                   as relkind,          -- expected 'r'
  c.relrowsecurity            as rls_enabled,      -- expected true
  c.relforcerowsecurity       as rls_forced,       -- expected false  (STOP if true)
  pg_get_userbyid(c.relowner) as owner             -- expected postgres
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

-- P-2. anon / authenticated table grants.
--    Expected: SELECT = true; INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES /
--      TRIGGER / MAINTAIN = false, for both roles.
--    NOTE: 'MAINTAIN' needs PG17+; if it errors on an older server, re-run without it.
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.notices', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.notices', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.notices', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.notices', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.notices', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.notices', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.notices', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.notices', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- P-2b. raw ACL / PUBLIC / grant option (context; this file changes NO table grant).
--    Expected: postgres (owner, all), anon SELECT, authenticated SELECT, service_role
--      (all); is_grantable = false; NO PUBLIC row.
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'notices'
order by grantee, acl.privilege_type;

-- P-3. columns / types / NULL / default.
--    Expected (STOP if the 4 returned columns differ): content text NOT NULL,
--      attachment_url text NULL, attachment_type text NULL, attachment_name text NULL;
--      plus id uuid NOT NULL, is_active boolean NOT NULL, created_at timestamptz NOT NULL,
--      attachment_path text NULL, updated_at timestamptz NULL.
select
  a.attname                            as column_name,
  a.attnum                             as ordinal,
  format_type(a.atttypid, a.atttypmod) as data_type,
  a.attnotnull                         as not_null,
  pg_get_expr(d.adbin, d.adrelid)      as default_expr
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where n.nspname = 'public'
  and c.relname = 'notices'
  and a.attnum > 0
  and not a.attisdropped
order by a.attnum;

-- P-4. constraints (context only; this file changes NO constraint).
--    Expected: notices_pkey PRIMARY KEY(id) validated; notices_attachment_type_check
--      (attachment_type IS NULL OR attachment_type IN ('image','pdf')) validated.
select
  con.conname                   as constraint_name,
  con.contype                   as type,       -- p=PK, c=CHECK, f=FK, u=UNIQUE
  con.convalidated              as validated,  -- expected true
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname = 'notices'
order by con.contype, con.conname;

-- P-5. indexes valid / ready (context only).
--    Expected: notices_pkey only; indisvalid = true, indisready = true,
--      indisunique = true, indisprimary = true.
select
  idx.relname    as index_name,
  i.indisvalid   as is_valid,     -- expected true
  i.indisready   as is_ready,     -- expected true
  i.indisunique  as is_unique,
  i.indisprimary as is_primary
from pg_index i
join pg_class rel on rel.oid = i.indrelid
join pg_class idx on idx.oid = i.indexrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname = 'notices'
order by idx.relname;

-- P-6. all policies (context only; this file changes NO policy).
--    Expected: notices_read_all -- PERMISSIVE, roles {public}, cmd SELECT, qual true,
--      with_check null. NOT changed here.
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
order by cmd, policyname;

-- P-7. counts baseline (CONTEXT; INVARIANT vs POST-14 within the same run window only).
--    Reference (C-12): total 4 / active 1 / inactive 3 / null 0. Ordinary data changes
--    alone are NOT a stop condition; use THIS run's value as the POST-14 / SMOKE reference.
select
  count(*)                                  as total,
  count(*) filter (where is_active = true)  as active,
  count(*) filter (where is_active = false) as inactive,
  count(*) filter (where is_active is null) as null_active
from public.notices;

-- P-8. list_notices_secure does not already exist. Expected: 0 rows (MANDATORY).
--    STOP if any row is returned (plain CREATE would otherwise error and roll back).
select p.oid::regprocedure::text as function_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_notices_secure';

-- P-8b. existing notices RPC baseline (5) -- attributes + EXECUTE ACL (context only).
--    Expected: SECURITY DEFINER = true, volatility 'v', owner postgres, fixed search_path.
--    KNOWN: PUBLIC EXECUTE present (baseline only, NOT a stop condition, NOT modified here).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
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
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;

-- P-9. employee-session verification columns exist (STOP if any missing / wrong type).
--    Expected: employee_sessions.employee_id uuid / token_hash text / expires_at
--      timestamptz; employees.id uuid / is_active boolean.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
        (table_name = 'employee_sessions' and column_name in ('employee_id','token_hash','expires_at'))
     or (table_name = 'employees'         and column_name in ('id','is_active'))
      )
order by table_name, column_name;


-- ============================================================
-- EXECUTION BODY
--   NOTE: first place that modifies DB state. Run ONLY after PRE-CHECK P-1..P-9 are
--         confirmed with no STOP condition hit (especially P-8 = 0 rows).
--   NOTE: additive only -- one plain CREATE FUNCTION (NOT CREATE OR REPLACE) plus owner /
--         EXECUTE settings on that NEW function. No table grant, no RLS, no policy, no
--         existing routine is touched.
--   NOTE: FIRST-run only (NOT idempotent). One transaction (BEGIN..COMMIT): a failure
--         rolls back the entire step.
--   Execution order: CREATE -> ALTER OWNER -> REVOKE PUBLIC -> GRANT.
-- ============================================================

BEGIN;

-- list_notices_secure (employee session, index.html loadNotice)
--   Employee-session inline verification (same as list_sites_secure /
--   list_subcontractors_secure): token_hash = encode(digest(session_token_input,'sha256'),
--   'hex'), expires_at > now(), employees.is_active = true; invalid / expired ->
--   RAISE 'Invalid or expired session'.
--   Returns active notices, only the 4 columns the worker screen renders
--   (content / attachment_url / attachment_type / attachment_name), newest first
--   (created_at DESC, id). id / is_active / created_at / attachment_path / updated_at are
--   server-side only and are NOT returned.
CREATE FUNCTION public.list_notices_secure(
  session_token_input text
)
RETURNS TABLE (
  content         text,
  attachment_url  text,
  attachment_type text,
  attachment_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_employee_id uuid;
BEGIN
  SELECT es.employee_id
  INTO   v_employee_id
  FROM   public.employee_sessions es
  JOIN   public.employees e ON e.id = es.employee_id
  WHERE  es.token_hash = encode(digest(session_token_input, 'sha256'), 'hex')
    AND  es.expires_at > now()
    AND  e.is_active   = true
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired session';
  END IF;

  RETURN QUERY
    SELECT n.content, n.attachment_url, n.attachment_type, n.attachment_name
    FROM   public.notices n
    WHERE  n.is_active = true
    ORDER  BY n.created_at DESC, n.id;
END;
$$;

ALTER  FUNCTION public.list_notices_secure(text) OWNER TO postgres;
REVOKE ALL     ON FUNCTION public.list_notices_secure(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.list_notices_secure(text) TO anon;
GRANT  EXECUTE ON FUNCTION public.list_notices_secure(text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.list_notices_secure(text) TO service_role;

-- Commit the CREATE FUNCTION plus its owner / EXECUTE settings as one atomic unit.
-- If anything above failed (incl. a "function already exists" collision), roll back.
COMMIT;


-- ============================================================
-- POST-CHECK (SELECT only; does NOT modify DB state)
-- ============================================================

-- POST-1. The function exists exactly once; no unexpected overload. Expected: 1 row.
select
  p.proname,
  count(*) as overloads,
  string_agg(p.oid::regprocedure::text, ' | ' order by p.oid) as signatures
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
group by p.proname;

-- POST-2. Attributes: SECURITY DEFINER = true, STABLE ('s'), owner postgres, fixed
--    search_path. Expected: 1 row, is_security_definer = true, volatility = 's',
--    owner = postgres, config contains search_path=public, extensions.
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as is_security_definer,   -- expect true
  p.provolatile               as volatility,            -- expect 's'
  pg_get_userbyid(p.proowner) as owner,                 -- expect postgres
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_notices_secure';

-- POST-3. Identity arguments (input signature). Expected: "session_token_input text".
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as identity_arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'list_notices_secure';

-- POST-4. RETURNS TABLE columns, correct ordinal from 1.
--    Expected: 1 content text, 2 attachment_url text, 3 attachment_type text,
--      4 attachment_name text.
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
  and p.proname = 'list_notices_secure'
  and t.argmode = 't'   -- TABLE (OUT) columns only
order by return_ordinal;

-- POST-5. Effective EXECUTE for anon / authenticated / service_role / postgres = true.
select
  v.grantee,
  has_function_privilege(v.grantee, 'public.list_notices_secure(text)', 'EXECUTE') as list_notices
from (values ('anon'), ('authenticated'), ('service_role'), ('postgres')) as v(grantee)
order by v.grantee;

-- POST-6. Explicit ACL rows: exactly postgres / anon / authenticated / service_role with
--    EXECUTE, is_grantable = false, explicit (proacl non-NULL); NO PUBLIC row.
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
  and p.proname = 'list_notices_secure'
order by grantee, acl.privilege_type;

-- POST-7. PUBLIC EXECUTE absent. Expected: 0 rows.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(p.proacl) as acl
where n.nspname = 'public'
  and p.proname = 'list_notices_secure'
  and acl.grantee = 0                 -- 0 = PUBLIC
  and acl.privilege_type = 'EXECUTE';

-- POST-8. notices table attributes UNCHANGED (mirror P-1).
select
  c.relname                   as table_name,
  c.relkind                   as relkind,
  c.relrowsecurity            as rls_enabled,
  c.relforcerowsecurity       as rls_forced,
  pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'notices';

-- POST-9. anon / authenticated table privileges UNCHANGED (mirror P-2:
--    SELECT = true; other 7 = false).
select
  v.role_name,
  has_table_privilege(v.role_name, 'public.notices', 'SELECT')     as can_select,
  has_table_privilege(v.role_name, 'public.notices', 'INSERT')     as can_insert,
  has_table_privilege(v.role_name, 'public.notices', 'UPDATE')     as can_update,
  has_table_privilege(v.role_name, 'public.notices', 'DELETE')     as can_delete,
  has_table_privilege(v.role_name, 'public.notices', 'TRUNCATE')   as can_truncate,
  has_table_privilege(v.role_name, 'public.notices', 'REFERENCES') as can_references,
  has_table_privilege(v.role_name, 'public.notices', 'TRIGGER')    as can_trigger,
  has_table_privilege(v.role_name, 'public.notices', 'MAINTAIN')   as can_maintain
from (values ('anon'), ('authenticated')) as v(role_name)
order by v.role_name;

-- POST-10. raw ACL UNCHANGED (mirror P-2b: postgres / anon SELECT / authenticated SELECT /
--    service_role; no PUBLIC).
select
  case when acl.grantee = 0 then 'PUBLIC' else r.rolname end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) as acl
left join pg_roles r on r.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'notices'
order by grantee, acl.privilege_type;

-- POST-11. policies UNCHANGED (mirror P-6: notices_read_all only, not added / dropped /
--    altered).
select
  schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'notices'
order by cmd, policyname;

-- POST-12. constraints UNCHANGED (mirror P-4).
select
  con.conname                   as constraint_name,
  con.contype                   as type,
  con.convalidated              as validated,
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname = 'notices'
order by con.contype, con.conname;

-- POST-13. indexes UNCHANGED (mirror P-5).
select
  idx.relname    as index_name,
  i.indisvalid   as is_valid,
  i.indisready   as is_ready,
  i.indisunique  as is_unique,
  i.indisprimary as is_primary
from pg_index i
join pg_class rel on rel.oid = i.indrelid
join pg_class idx on idx.oid = i.indexrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname = 'notices'
order by idx.relname;

-- POST-14. counts UNCHANGED vs the PRE-CHECK P-7 value from THIS run window (mirror P-7).
--    (Ordinary data changes between runs are tolerated; compare against the immediately
--     preceding P-7 result, not the C-12 snapshot.)
select
  count(*)                                  as total,
  count(*) filter (where is_active = true)  as active,
  count(*) filter (where is_active = false) as inactive,
  count(*) filter (where is_active is null) as null_active
from public.notices;

-- POST-15. existing notices RPC baseline UNCHANGED (mirror P-8b attributes). KNOWN PUBLIC
--    EXECUTE remains as-is (NOT modified by this file).
select
  p.oid::regprocedure::text   as function_signature,
  p.prosecdef                 as security_definer,
  p.provolatile               as volatility,
  pg_get_userbyid(p.proowner) as owner,
  p.proconfig                 as config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
order by p.proname, p.oid::regprocedure::text;

-- POST-16. existing notices RPC EXECUTE ACL UNCHANGED (mirror P-8b ACL). KNOWN PUBLIC
--    EXECUTE on the 5 RPCs remains as-is.
select
  p.proname,
  case when acl.grantee = 0 then 'PUBLIC' else acl.grantee::regrole::text end as grantee,
  acl.privilege_type,
  acl.is_grantable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
where n.nspname = 'public'
  and p.proname in ('list_notices_admin_secure', 'create_notice_secure',
                    'update_notice_secure', 'update_notice_attachment_secure',
                    'delete_notice_attachment_secure')
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee;


-- ============================================================
-- SMOKE TEST (manual; performed by the user AFTER the body + post-check)
--
--   (a) NEGATIVE check -- run in the SQL Editor with a bogus token. The new RPC must
--       RAISE 'Invalid or expired session'. The DO block below catches ONLY the expected
--       raise (sqlstate P0001) around the call, then FAILS loudly OUTSIDE that inner block
--       if no raise occurred -- so a self-generated "SMOKE FAIL" is never swallowed by a
--       WHEN OTHERS. (No WHEN OTHERS is used.)
DO $$
DECLARE v_raised boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.list_notices_secure('smoke-invalid-token');
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      -- Only the exact auth rejection counts as PASS; any other P0001 is re-raised.
      IF SQLERRM <> 'Invalid or expired session' THEN
        RAISE;
      END IF;
      v_raised := true;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'SMOKE FAIL: list_notices_secure did not reject an invalid token';
  END IF;
  RAISE NOTICE 'SMOKE OK: list_notices_secure rejected invalid token';
END $$;

--   (b) POSITIVE check -- requires a VALID employee session token. Do NOT paste any real
--       token into this file or the run log. Run in the browser DevTools Console of a
--       logged-in employee app session, or in the SQL Editor with a token pasted at run
--       time only.
--       Expected: row count = the active notices count from the PRE-CHECK P-7 run in the
--       same window (C-12 reference: active = 1), and each row has exactly the 4 columns
--       content / attachment_url / attachment_type / attachment_name.
--
--       -- SQL Editor example (replace <...> at run time; never save a real token) --
--       select count(*) from public.list_notices_secure('<valid employee token>');   -- expect = P-7 active
--
--       -- browser Console example (employee app; anon key context, valid session) --
--       // const t = state.currentUser.session_token;
--       // console.log((await sb.rpc('list_notices_secure',{session_token_input:t})).data?.length);
-- ============================================================


-- ============================================================
-- ROLLBACK (commented out; NOT executed -- reference only)
--   Removes exactly the one function this file adds. Safe at this stage because the
--   front-end has not been migrated, so nothing depends on it yet. Touches NO table
--   grant, NO policy, NO existing RPC.
-- ============================================================
-- DROP FUNCTION public.list_notices_secure(text);
-- ============================================================
