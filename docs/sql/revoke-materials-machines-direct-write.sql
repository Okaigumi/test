-- ============================================================
-- Phase 3-3: materials / machines direct write REVOKE
-- Run in Supabase SQL Editor
--
-- Purpose:
--   Revoke direct INSERT / UPDATE on public.materials and
--   public.machines from anon / authenticated.
--   The front-end (index.html / admin-app.html) already writes
--   via the 7 secure RPCs, and production has been verified.
--
-- Kept (NOT touched by this script):
--   - SELECT privilege (needed by index.html / admin-app.html /
--     genka-app.html list & read views; NOT revoked)
--   - EXECUTE privilege on the 7 secure RPCs
--   - RLS enabled state
--   - existing POLICY definitions
--
-- Not included (privilege revoke only):
--   - no REVOKE SELECT / no REVOKE EXECUTE
--   - no DROP / ALTER TABLE / CREATE|ALTER|DROP POLICY
--   - no DELETE / TRUNCATE / standalone INSERT / standalone UPDATE
--   - no RPC function change / no RLS change
-- ============================================================


-- ============================================================
-- 1. REVOKE (direct INSERT / UPDATE on materials / machines)
-- ============================================================
REVOKE INSERT, UPDATE ON TABLE public.materials FROM anon, authenticated;
REVOKE INSERT, UPDATE ON TABLE public.machines  FROM anon, authenticated;


-- ============================================================
-- 2. Post-apply verification (read-only SELECT only)
--    Running these does not change DB state.
-- ============================================================

-- 2-1. materials / machines table privileges for anon / authenticated
--      Expected: INSERT / UPDATE gone; SELECT still present.
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('materials', 'machines')
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;

-- 2-2. EXECUTE privilege on the 7 secure RPCs for anon / authenticated
--      Expected: 14 rows (7 functions x 2 roles).
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN (
    'create_material_secure',
    'deactivate_material_secure',
    'create_machine_secure',
    'update_machine_secure',
    'deactivate_machine_secure',
    'create_machine_admin_secure',
    'update_machine_admin_secure'
  )
  AND grantee IN ('anon', 'authenticated')
ORDER BY routine_name, grantee;

-- 2-3. _verify_management_session external EXECUTE check
--      Expected: 0 rows (no EXECUTE for anon / authenticated / public).
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name = '_verify_management_session'
  AND grantee IN ('anon', 'authenticated', 'public')
ORDER BY grantee;

-- 2-4. RLS state
--      Expected: unchanged (same as before the REVOKE).
SELECT relname AS table_name,
       relrowsecurity      AS rls_enabled,
       relforcerowsecurity AS rls_forced
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname IN ('materials', 'machines')
ORDER BY relname;

-- 2-5. policy list
--      Expected: unchanged (same as before the REVOKE).
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('materials', 'machines')
ORDER BY tablename, policyname;
