-- ============================================================
-- Phase 4 (roadmap)：RLSポリシー整理 — 現状スナップショット取得用
-- READ-ONLY INTROSPECTION SQL
-- Run in Supabase SQL Editor
--
-- ⚠️ このSQLは読み取り専用です。
--    - SELECT のみ。CREATE / ALTER / DROP / GRANT / REVOKE /
--      INSERT / UPDATE / DELETE / TRUNCATE は一切含みません。
--    - DB状態は一切変更しません（権限・ポリシー・データは不変）。
--    - 目的：Phase 4 着手前に、RLS・POLICY・GRANT・View・RPC・Storage の
--      現状スナップショットを取得すること。
--    - 実行結果を進捗管理チャットへ貼り戻してから、整理方針（REVOKE/POLICY整理）を判断すること。
--    - この段階では整理用SQL・REVOKE案・POLICY削除案・migration案は作らない。
--
-- 実行方法（重要）：
--    Supabase SQL Editor で「全実行」すると最後のクエリ結果しか表示されません。
--    各セクション（1〜13）を1つずつ選択して実行し、結果を順に貼り戻してください。
--
-- 注記：
--    - PUBLIC 疑似ロールは information_schema の grantee に 'PUBLIC' として現れます。
--    - 列単位 GRANT は role_column_grants に「明示的に許可された列」だけが現れます。
--    - reports / paid_leave_requests / employees / employee_sessions は
--      日報カレンダーMVP前の重点対象として各セクションに含めています。
-- ============================================================


-- ============================================================
-- 1. 全 public テーブルの RLS 状態
--    relrowsecurity = RLS有効 / relforcerowsecurity = 強制RLS
-- ============================================================
SELECT n.nspname            AS schema_name,
       c.relname            AS table_name,
       c.relrowsecurity     AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'           -- 通常テーブルのみ
ORDER BY c.relname;


-- ============================================================
-- 2. pg_policies 全件（public schema）
--    USING(qual) / WITH CHECK(with_check) と、true相当かの判定列つき
-- ============================================================
SELECT schemaname,
       tablename,
       policyname,
       permissive,
       cmd,
       roles,
       qual,
       with_check,
       (qual IS NULL OR btrim(qual) = 'true')             AS using_is_true_or_null,
       (with_check IS NULL OR btrim(with_check) = 'true')  AS withcheck_is_true_or_null
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;


-- ============================================================
-- 3. anon / authenticated / PUBLIC のテーブル権限（public schema 全件）
--    SELECT / INSERT / UPDATE / DELETE の付与状況
-- ============================================================
SELECT table_schema,
       table_name,
       grantee,
       privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
ORDER BY table_name, grantee, privilege_type;


-- ============================================================
-- 3-b. テーブル権限のピボット俯瞰（テーブル×ロールで S/I/U/D を集約）
--      どのテーブルに何が残っているか一覧で見たい場合
-- ============================================================
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;


-- ============================================================
-- 4. 列単位 GRANT（pin / session_token など機微列の露出確認）
--    4-a：機微テーブルの列定義一覧（どの列が存在するか）
-- ============================================================
SELECT table_name, ordinal_position, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('employees', 'genka_admins', 'employee_sessions', 'admin_sessions')
ORDER BY table_name, ordinal_position;

-- 4-b：anon / authenticated / PUBLIC に明示付与された列単位 SELECT
--      （pin / session_token 等が現れたら要確認）
SELECT table_name,
       grantee,
       column_name,
       privilege_type
FROM information_schema.role_column_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND table_name IN ('employees', 'genka_admins', 'employee_sessions', 'admin_sessions')
ORDER BY table_name, grantee, column_name;

-- 4-c：テーブル全体に SELECT が付いているか（true なら pin 含む全列が読める）
--      機微テーブルで anon/authenticated が true の場合は要警戒
SELECT 'employees'         AS table_name,
       has_table_privilege('anon',          'public.employees',         'SELECT') AS anon_select,
       has_table_privilege('authenticated', 'public.employees',         'SELECT') AS auth_select
UNION ALL
SELECT 'genka_admins',
       has_table_privilege('anon',          'public.genka_admins',      'SELECT'),
       has_table_privilege('authenticated', 'public.genka_admins',      'SELECT')
UNION ALL
SELECT 'employee_sessions',
       has_table_privilege('anon',          'public.employee_sessions', 'SELECT'),
       has_table_privilege('authenticated', 'public.employee_sessions', 'SELECT')
UNION ALL
SELECT 'admin_sessions',
       has_table_privilege('anon',          'public.admin_sessions',    'SELECT'),
       has_table_privilege('authenticated', 'public.admin_sessions',    'SELECT')
ORDER BY table_name;


-- ============================================================
-- 5. View 一覧と View への権限（public schema）
--    5-a：public schema の view 一覧
-- ============================================================
SELECT table_name AS view_name,
       view_definition
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

-- 5-b：view に対する anon / authenticated / PUBLIC の SELECT 権限
SELECT g.table_name AS view_name,
       g.grantee,
       g.privilege_type
FROM information_schema.role_table_grants g
JOIN information_schema.views v
  ON v.table_schema = g.table_schema
 AND v.table_name   = g.table_name
WHERE g.table_schema = 'public'
  AND g.grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY g.table_name, g.grantee, g.privilege_type;


-- ============================================================
-- 6. RPC / Function の EXECUTE 権限（public schema）
--    6-a：secure RPC・認可ヘルパーを含む全関数の EXECUTE 付与（anon/authenticated/PUBLIC）
-- ============================================================
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY routine_name, grantee;

-- 6-b：認可ヘルパーの外部 EXECUTE 確認（0行が期待）
--      内部専用関数が anon/authenticated/PUBLIC から実行可能になっていないか
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND routine_name IN ('_verify_management_session', '_verify_employee_session')
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY routine_name, grantee;

-- 6-c：全関数の SECURITY DEFINER / search_path / 実行ACL の俯瞰
--      proacl が NULL の場合はデフォルト（PUBLIC EXECUTE 付き）を意味する点に注意
SELECT p.proname        AS function_name,
       p.prosecdef      AS security_definer,
       p.proconfig      AS config,           -- search_path 等
       p.proacl         AS execute_acl       -- NULL = デフォルト(PUBLIC実行可)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.proname;


-- ============================================================
-- 7. Storage bucket の公開状態
-- ============================================================
SELECT id,
       name,
       public,
       file_size_limit,
       allowed_mime_types,
       created_at,
       updated_at
FROM storage.buckets
ORDER BY id;


-- ============================================================
-- 8. Storage policy 一覧（storage.objects に対する RLS ポリシー）
--    bucket ごとの SELECT / INSERT / UPDATE / DELETE policy、roles、using/with_check
-- ============================================================
SELECT schemaname,
       tablename,
       policyname,
       permissive,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
ORDER BY policyname;

-- 8-b：storage.objects / storage.buckets の RLS 状態
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c.relrowsecurity      AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'storage'
  AND c.relname IN ('objects', 'buckets')
ORDER BY c.relname;


-- ============================================================
-- 9. Phase 3 で REVOKE 済みの対象との整合性確認
--    期待：anon / authenticated に INSERT / UPDATE / DELETE が無く、SELECT のみ残存
--    （SELECT の要否は Phase 4 で別途判断）
-- ============================================================
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  AND table_name IN (
        'sites', 'site_assignments',
        'materials', 'machines',
        'employee_rates', 'unit_rates',
        'reports',
        'paid_leave_requests', 'paid_leave_grants',
        'invoices', 'site_budgets',
        'machine_locations',
        'notices'
      )
GROUP BY table_name, grantee
ORDER BY table_name, grantee;


-- ============================================================
-- 10. 日報カレンダーMVP前の重点対象（個別深掘り）
--     reports / paid_leave_requests / employees / employee_sessions
--     10-a：4テーブルの RLS 状態
-- ============================================================
SELECT c.relname AS table_name,
       c.relrowsecurity      AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('reports', 'paid_leave_requests', 'employees', 'employee_sessions')
ORDER BY c.relname;

-- 10-b：4テーブルの POLICY（SELECT が誰に・どの行に開いているか）
SELECT tablename,
       policyname,
       permissive,
       cmd,
       roles,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('reports', 'paid_leave_requests', 'employees', 'employee_sessions')
ORDER BY tablename, cmd, policyname;

-- 10-c：4テーブルの anon/authenticated/PUBLIC 権限（SELECT 残存の有無）
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND table_name IN ('reports', 'paid_leave_requests', 'employees', 'employee_sessions')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;


-- ============================================================
-- 11. 参考：public テーブルで RLS 無効のまま anon/authenticated に
--     SELECT 以外（I/U/D）が残っているものの抽出（リスク早見）
--     期待：Phase 3 後は I/U/D 残存なし。残っていれば要精査。
-- ============================================================
SELECT g.table_name,
       g.grantee,
       string_agg(g.privilege_type, ', ' ORDER BY g.privilege_type) AS write_privileges
FROM information_schema.role_table_grants g
WHERE g.table_schema = 'public'
  AND g.grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND g.privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
GROUP BY g.table_name, g.grantee
ORDER BY g.table_name, g.grantee;


-- ============================================================
-- 12. 参考：RLS が無効なのに anon/authenticated に SELECT がある public テーブル
--     （RLS無効＝行制限なし。広い読み取り露出の早見）
-- ============================================================
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       bool_or(g.grantee = 'anon')          AS anon_has_select,
       bool_or(g.grantee = 'authenticated') AS auth_has_select
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN information_schema.role_table_grants g
       ON g.table_schema = 'public'
      AND g.table_name   = c.relname
      AND g.privilege_type = 'SELECT'
      AND g.grantee IN ('anon', 'authenticated')
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
GROUP BY c.relname, c.relrowsecurity
HAVING bool_or(g.grantee IN ('anon', 'authenticated'))
ORDER BY c.relrowsecurity, c.relname;


-- ============================================================
-- 13. 参考：secure RPC 群の EXECUTE 俯瞰（Phase 3 で追加した関数の確認）
--     PUBLIC EXECUTE = true の最小権限化検討material
-- ============================================================
SELECT routine_name,
       grantee,
       privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND routine_name LIKE '%_secure'
ORDER BY routine_name, grantee;

-- ============================================================
-- 実行後の進め方：
--   1〜13 の結果を進捗管理チャットへ貼り戻す
--   → RLS/POLICY/GRANT/View/RPC/Storage の確定スナップショットを評価
--   → そのうえで Phase 4 の整理方針（SELECT制限・POLICY整理・PUBLIC EXECUTE縮小等）を判断
--   ※ 整理用SQL・REVOKE案・POLICY削除案・migration案は本ファイルには含めない
-- ============================================================
