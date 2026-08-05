-- ============================================================
-- Phase 7-C restore post-check SQL
-- 完全 read-only。INSERT / UPDATE / DELETE / TRUNCATE / DDL 禁止。
-- Phase 7-D restore test 後に docker exec psql で実行する。
-- ============================================================
-- 実行方法（例）:
--   docker exec $DB_CONTAINER psql -U postgres -d postgres \
--     -f /tmp/phase7c-restore-postcheck.sql
-- ============================================================
-- 実行条件（Phase 7-D follow-up / PR-2 で確定）:
--   - ON_ERROR_STOP は ON（fail-fast）を維持する。本ファイル冒頭で明示的に設定する。
--   - SECTION 0（schema drift 検出）を本体より先に実行する。
--     SECTION 0 は to_regclass() ベースのため、テーブルが存在しなくてもエラーにならず、
--     drift を「データとして」報告する。本体が fail-fast で停止した場合でも、
--     停止原因となった drift は SECTION 0 の出力から特定できる。
-- ============================================================
-- Phase 7-D（2026-08-05）での実行結果と修正:
--   - SECTION 1-2 / SECTION 2-1 が存在しないテーブル public.rates を参照しており、
--     stale 参照により途中停止した（restore の失敗ではない）。
--   - 現行スキーマの単価テーブルは public.employee_rates / public.unit_rates である。
--   - SECTION 2-1 は relkind='r'（通常テーブル）のみを対象とするため、
--     VIEW である public.report_summary は構造上返らない。RLS は VIEW に適用されない概念のため、
--     RLS 確認リストからは除外し、存在確認は SECTION 0 で行う。
-- ============================================================

\set ON_ERROR_STOP on


-- ============================================================
-- SECTION 0: SCHEMA DRIFT 検出（本体より先に実行する）
-- 期待オブジェクトの実在・種別・RLS 状態を一覧化する。
-- 不存在でもエラーにはならない（to_regclass は NULL を返す）。
-- ============================================================

-- 0-1. 期待オブジェクトの実在確認
-- obj_exists=false があれば、以降の SECTION が fail-fast で停止する原因となる
-- 期待状態（Phase 7-D / PR-2 S-5 再検証で確定）:
--   expected object 合計 23 件（base table 22 件＋VIEW 1 件）／obj_exists 全件 true
--   public.report_summary は VIEW として存在確認の対象に含める（RLS 対象には含めない）
SELECT
  v.qname                              AS expected_object,
  (to_regclass(v.qname) IS NOT NULL)   AS obj_exists,
  c.relkind                            AS relkind,   -- r=table / p=partitioned / v=view
  c.relrowsecurity                     AS rls_enabled
FROM (VALUES
  ('public.employees'),
  ('public.employee_sessions'),
  ('public.admin_sessions'),
  ('public.reports'),
  ('public.report_summary'),
  ('public.sites'),
  ('public.site_assignments'),
  ('public.site_categories'),
  ('public.materials'),
  ('public.companies'),
  ('public.company_categories'),
  ('public.subcontractors'),
  ('public.machines'),
  ('public.machine_locations'),
  ('public.employee_rates'),
  ('public.unit_rates'),
  ('public.site_budgets'),
  ('public.invoices'),
  ('public.notices'),
  ('public.paid_leave_requests'),
  ('public.paid_leave_grants'),
  ('public.genka_admins'),
  ('private.login_throttle')
) AS v(qname)
LEFT JOIN pg_class c ON c.oid = to_regclass(v.qname)
ORDER BY v.qname;

-- 0-2. 期待リストに無い実在オブジェクト（新規追加テーブル・VIEW の検出）
-- 0件を期待しない（情報記録）。件数が増えた場合は 0-1 の期待リスト更新を検討する
SELECT
  n.nspname  AS schema_name,
  c.relname  AS object_name,
  c.relkind  AS relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'private')
  AND c.relkind IN ('r', 'p', 'v')
  AND (n.nspname || '.' || c.relname) NOT IN (
    'public.employees', 'public.employee_sessions', 'public.admin_sessions',
    'public.reports', 'public.report_summary', 'public.sites',
    'public.site_assignments', 'public.site_categories',
    'public.materials', 'public.companies', 'public.company_categories',
    'public.subcontractors', 'public.machines', 'public.machine_locations',
    'public.employee_rates', 'public.unit_rates', 'public.site_budgets',
    'public.invoices', 'public.notices',
    'public.paid_leave_requests', 'public.paid_leave_grants',
    'public.genka_admins', 'private.login_throttle'
  )
ORDER BY n.nspname, c.relname;

-- 0-3. public / private の base table 総数と RLS サマリ（PASS/FAIL）
-- 期待値（Phase 7-D 実測・2026-07-26 backup 世代）:
--   base_tables=22 / rls_enabled=22 / rls_disabled=0 / views=1（public.report_summary）
--   ※ base table 22 = public 21 + private 1
SELECT
  COUNT(*) FILTER (WHERE c.relkind IN ('r', 'p'))                              AS base_tables,
  COUNT(*) FILTER (WHERE c.relkind IN ('r', 'p') AND c.relrowsecurity)         AS rls_enabled,
  COUNT(*) FILTER (WHERE c.relkind IN ('r', 'p') AND NOT c.relrowsecurity)     AS rls_disabled,
  COUNT(*) FILTER (WHERE c.relkind = 'v')                                      AS views
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'private');


-- ============================================================
-- SECTION 1: DB COUNTS
-- ============================================================

-- 1-1. public schema テーブル数（情報記録）
SELECT COUNT(*) AS public_table_count
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE';

-- 1-2. 主要テーブル row count（情報記録）
-- ⚠️ 実行時点の区別（重要）:
--   - 「restore 直後 baseline」と「application / write smoke 実施後の再検証値」は区別する。
--   - smoke 後は reports / employee_rates / session 系などが変化し得る（local での正常な操作結果）。
--   - したがって、件数差だけをもって restore 失敗とは判定しない。
--   - 判定にあたっては、どの時点で実行した post-check かを必ず記録する。
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
SELECT 'employee_rates',       COUNT(*) FROM public.employee_rates
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
-- ⚠️ 0 件を期待できるのは「削除直後」のみ。
--    その後に application / write smoke でログインすると session が再作成されるため、
--    smoke 後の再検証では 0 でない値になり得る。これは restore 失敗ではない。
SELECT 'employee_sessions' AS tbl, COUNT(*) AS cnt FROM public.employee_sessions
UNION ALL
SELECT 'admin_sessions',           COUNT(*) FROM public.admin_sessions
UNION ALL
SELECT 'login_throttle',           COUNT(*) FROM private.login_throttle;


-- ============================================================
-- SECTION 2: RLS / POLICIES
-- ============================================================

-- 2-1. critical テーブルの RLS 状態（PASS/FAIL）
-- 期待: 22 件すべて rls_enabled=true
--       （public 21 + private 1 の base table 全件。SECTION 0-3 の base_tables / rls_enabled と一致する）
-- ※ relkind='r' のみを対象とするため VIEW（public.report_summary）は含めない。
--    VIEW の存在確認は SECTION 0-1 で行う。
-- ※ public / private 全体の RLS サマリは SECTION 0-3 と突き合わせる。
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
    'reports', 'sites', 'site_assignments', 'site_categories',
    'materials', 'companies', 'company_categories',
    'subcontractors', 'machines', 'machine_locations',
    'employee_rates', 'unit_rates', 'site_budgets',
    'invoices', 'notices',
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
