-- ============================================================
-- Phase 7-C restore post-check SQL
-- 完全 read-only。INSERT / UPDATE / DELETE / TRUNCATE / DDL 禁止。
-- Phase 7-D restore test 後に docker exec psql で実行する。
-- ============================================================
-- 実行方法（例）:
--   docker exec $DB_CONTAINER psql -U postgres -d postgres \
--     -f /tmp/phase7c-restore-postcheck.sql
-- ============================================================


-- ============================================================
-- SECTION 1: DB COUNTS
-- ============================================================

-- 1-1. public schema テーブル数（情報記録）
SELECT COUNT(*) AS public_table_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE';

-- 1-2. 主要テーブル row count（情報記録）
SELECT
  'employees'         AS tbl, COUNT(*) AS cnt FROM public.employees
UNION ALL
SELECT 'reports',              COUNT(*) FROM public.reports
UNION ALL
SELECT 'sites',                COUNT(*) FROM public.sites
UNION ALL
SELECT 'site_assignments',     COUNT(*) FROM public.site_assignments
UNION ALL
SELECT 'materials',            COUNT(*) FROM public.materials
UNION ALL
SELECT 'companies',            COUNT(*) FROM public.companies
UNION ALL
SELECT 'subcontractors',       COUNT(*) FROM public.subcontractors
UNION ALL
SELECT 'machines',             COUNT(*) FROM public.machines
UNION ALL
SELECT 'invoices',             COUNT(*) FROM public.invoices
UNION ALL
SELECT 'rates',                COUNT(*) FROM public.rates
UNION ALL
SELECT 'unit_rates',           COUNT(*) FROM public.unit_rates
UNION ALL
SELECT 'site_budgets',         COUNT(*) FROM public.site_budgets
UNION ALL
SELECT 'notices',              COUNT(*) FROM public.notices
UNION ALL
SELECT 'paid_leave_requests',  COUNT(*) FROM public.paid_leave_requests
UNION ALL
SELECT 'genka_admins',         COUNT(*) FROM public.genka_admins
ORDER BY tbl;

-- 1-3. employees pin_hash / pin 確認（PASS/FAIL）
-- 期待: total=11 / pin_hash_not_null=11 / pin_hash_null=0 / pin_not_null=11
SELECT
  COUNT(*)                                            AS employees_total,
  COUNT(pin_hash)                                     AS pin_hash_not_null,
  COUNT(*) FILTER (WHERE pin_hash IS NULL)            AS pin_hash_null,
  COUNT(*) FILTER (WHERE pin IS NOT NULL)             AS pin_not_null
FROM public.employees;

-- 1-4. bcrypt cost 12 確認（PASS/FAIL）
-- 期待: cost12_count=11（全 11件が $2[aby]$12$ で始まる）
SELECT
  COUNT(*) FILTER (WHERE pin_hash ~ '^\$2[aby]\$12\$') AS cost12_count,
  COUNT(*) FILTER (WHERE pin_hash !~ '^\$2[aby]\$12\$'
                      AND pin_hash IS NOT NULL)         AS unexpected_cost_count
FROM public.employees;

-- 1-5. session / throttle 件数（削除前に記録 → 削除後に 0 を確認）
SELECT 'employee_sessions' AS tbl, COUNT(*) AS cnt FROM public.employee_sessions
UNION ALL
SELECT 'admin_sessions',           COUNT(*) FROM public.admin_sessions
UNION ALL
SELECT 'login_throttle',           COUNT(*) FROM private.login_throttle;


-- ============================================================
-- SECTION 2: RLS / POLICIES
-- ============================================================

-- 2-1. critical テーブルの RLS 状態（PASS/FAIL）
-- 期待: Phase 3〜5 で RLS 設定されたテーブルが全て enabled
SELECT
  n.nspname  AS schema_name,
  c.relname  AS table_name,
  c.relrowsecurity   AS rls_enabled,
  c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'private')
  AND c.relkind = 'r'
  AND c.relname IN (
    'employees', 'employee_sessions', 'admin_sessions',
    'reports', 'report_summary', 'sites', 'site_assignments',
    'materials', 'companies', 'subcontractors', 'machines',
    'machine_locations', 'rates', 'unit_rates', 'site_budgets',
    'invoices', 'notices', 'notice_attachments',
    'paid_leave_requests', 'paid_leave_grants', 'genka_admins',
    'login_throttle'
  )
ORDER BY n.nspname, c.relname;

-- 2-2. public テーブルの policy 件数（情報記録）
SELECT
  schemaname,
  tablename,
  COUNT(*) AS policy_count
FROM pg_policies
WHERE schemaname IN ('public', 'private')
GROUP BY schemaname, tablename
ORDER BY schemaname, tablename;

-- 2-3. storage.objects の RLS 状態（PASS/FAIL）
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage'
  AND c.relname = 'objects'
  AND c.relkind = 'r';

-- 2-4. photos policy 定義確認（PASS/FAIL）
-- 期待: photos_read (SELECT/PUBLIC/USING: bucket_id='photos')
--       photos_upload (INSERT/PUBLIC/WITH CHECK: bucket_id='photos')
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename  = 'objects'
  AND policyname IN ('photos_read', 'photos_upload')
ORDER BY policyname;

-- 2-5. private.login_throttle owner / RLS（PASS/FAIL）
-- 期待: owner=postgres / rls_enabled=true / rls_forced=false
SELECT
  r.rolname                AS owner,
  c.relrowsecurity         AS rls_enabled,
  c.relforcerowsecurity    AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r     ON r.oid = c.relowner
WHERE n.nspname = 'private'
  AND c.relname = 'login_throttle'
  AND c.relkind = 'r';


-- ============================================================
-- SECTION 3: GRANTS
-- ============================================================

-- 3-1. public application table への anon / authenticated direct grants
-- 期待（Phase 4-F 完了後）: 0件
-- ※ 0件でなければ要調査（情報記録・直ちに FAIL にしない）
SELECT
  table_name,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;

-- 3-2. storage schema managed grants（情報表示のみ・0件を期待しない）
SELECT
  table_name,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'storage'
  AND grantee IN ('anon', 'authenticated')
ORDER BY table_name, grantee, privilege_type;


-- ============================================================
-- SECTION 4: photos bucket 設定（PASS/FAIL）
-- 期待: public=true / file_size_limit=5242880 / allowed_mime_types={image/jpeg}
-- ============================================================
SELECT
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
FROM storage.buckets
WHERE id = 'photos';


-- ============================================================
-- SECTION 5: RPC existence / fingerprint
-- ============================================================

-- 5-1. critical RPC 一覧（存在確認・owner・SECURITY DEFINER・volatility・search_path）
SELECT
  p.proname                                            AS func_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS args,
  r.rolname                                            AS owner,
  p.prosecdef                                          AS security_definer,
  CASE p.provolatile
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
  END                                                  AS volatility,
  p.proconfig                                          AS config  -- search_path 等
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r     ON r.oid = p.proowner
WHERE n.nspname = 'public'
  AND p.proname IN (
    'create_employee_session',
    'revoke_employee_session',
    'create_report_secure',
    'update_report_photo_secure',
    'list_my_reports_secure',
    'create_admin_session',
    'revoke_admin_session',
    'list_admin_reports_secure',
    'list_sites_secure',
    'list_materials_secure',
    'list_subcontractors_secure',
    'list_notices_secure',
    'list_my_paid_leave_secure',
    'list_genka_reports_secure'
  )
ORDER BY p.proname;

-- 5-2. anon / authenticated の RPC EXECUTE grant 確認
SELECT
  r.routine_name,
  g.grantee,
  g.privilege_type
FROM information_schema.routine_privileges g
JOIN information_schema.routines r
  ON r.routine_schema = g.routine_schema
  AND r.specific_name = g.specific_name
WHERE r.routine_schema = 'public'
  AND g.grantee IN ('anon', 'authenticated')
  AND r.routine_name IN (
    'create_employee_session',
    'revoke_employee_session',
    'create_report_secure',
    'update_report_photo_secure',
    'list_my_reports_secure',
    'create_admin_session',
    'revoke_admin_session',
    'list_admin_reports_secure',
    'list_sites_secure',
    'list_materials_secure',
    'list_subcontractors_secure',
    'list_notices_secure',
    'list_my_paid_leave_secure',
    'list_genka_reports_secure'
  )
ORDER BY r.routine_name, g.grantee;

-- 5-3. create_employee_secure / update_employee_secure / create_employee_session
--      body 長・md5 fingerprint（known baseline）
-- 期待（repo記録）:
--   create_employee_secure:  len=1433 / md5=33ea12279533b4a808a4d14bf11bb0a9
--   update_employee_secure:  len=1915 / md5=848eec0d7310c84cdffd05939b6c7a3b
--   create_employee_session: len=3798 / md5=006550c3455e34aa9d1d61bd60bb85ad
SELECT
  p.proname                                            AS func_name,
  length(p.prosrc)                                     AS body_len,
  md5(p.prosrc)                                        AS body_md5
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'create_employee_secure',
    'update_employee_secure',
    'create_employee_session'
  )
ORDER BY p.proname;
