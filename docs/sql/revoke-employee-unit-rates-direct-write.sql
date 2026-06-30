-- ============================================================
-- Phase 3-3: employee_rates / unit_rates direct write REVOKE
-- (Phase 3 優先順位3)
-- Run in Supabase SQL Editor
--
-- Purpose:
--   Revoke direct INSERT / UPDATE on public.employee_rates and
--   public.unit_rates from anon / authenticated.
--   The front-end (admin-app.html / genka-app.html) already writes
--   via the 2 secure RPCs (upsert_employee_rate_secure /
--   upsert_unit_rate_secure), and production has been verified:
--     - /admin 従業員日当保存 OK
--     - /admin 単価保存 OK
--     - /genka 従業員日当保存 OK
--     - /genka 単価保存 OK
--
-- Kept (NOT touched by this script):
--   - SELECT privilege (needed by admin-app.html / genka-app.html
--     list & read views; NOT revoked)
--   - REFERENCES / TRIGGER / TRUNCATE privileges
--   - EXECUTE privilege on the 2 secure RPCs
--   - _verify_management_session (external EXECUTE stays disabled)
--   - RLS enabled state
--   - existing POLICY definitions
--   - table definitions
--
-- Not included (privilege revoke only):
--   - no REVOKE SELECT / no REVOKE EXECUTE
--   - no DROP / ALTER TABLE / CREATE|ALTER|DROP POLICY
--   - no DELETE / TRUNCATE / standalone INSERT / standalone UPDATE
--   - no RPC function change / no RLS change
-- ============================================================


-- ============================================================
-- 1. REVOKE (direct INSERT / UPDATE on employee_rates / unit_rates)
-- ============================================================
REVOKE INSERT, UPDATE ON TABLE public.employee_rates FROM anon, authenticated;
REVOKE INSERT, UPDATE ON TABLE public.unit_rates     FROM anon, authenticated;


-- ============================================================
-- 2. Post-apply verification (read-only SELECT only)
--    Running these does not change DB state.
-- ============================================================

-- 2-1. employee_rates / unit_rates table privileges for anon / authenticated
--      Expected: INSERT / UPDATE gone; SELECT still present.
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('employee_rates', 'unit_rates')
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;

-- 2-2. EXECUTE privilege on the 2 secure RPCs for anon / authenticated
--      Expected: 4 rows (2 functions x 2 roles).
SELECT routine_name, grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN (
    'upsert_employee_rate_secure',
    'upsert_unit_rate_secure'
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
--      Expected: unchanged (relrowsecurity = true for both).
SELECT relname AS table_name,
       relrowsecurity      AS rls_enabled,
       relforcerowsecurity AS rls_forced
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname IN ('employee_rates', 'unit_rates')
ORDER BY relname;

-- 2-5. policy list
--      Expected: unchanged (existing policies remain).
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('employee_rates', 'unit_rates')
ORDER BY tablename, policyname;
