-- ============================================================
-- Phase 4-A-1：subcontractors write 穴塞ぎ
-- 対象：public.subcontractors のみ
--
-- 状態：実行済み（2026-06-30 Supabase SQL Editor で適用）
--   - 適用結果：Success. No rows returned
--   - 事後確認OK：anon/authenticated は SELECT のみ／sub_read 残存／
--     sub_write・sub_update 削除済み／INSERT・UPDATE・DELETE 残存なし
--   - 本番画面確認OK：index.html / admin-app.html / genka-app.html の業者一覧表示
--   - 記録：docs/db-migrations.md「2026-06-30 Phase 4-A-1 subcontractors write lockdown 完了」
--
-- 目的：
--   フロントは subcontractors を SELECT でしか使っていないのに、
--   anon / authenticated に INSERT / UPDATE GRANT と
--   緩い write policy（sub_write / sub_update = public true）が残存している。
--   この orphan な書き込み経路（API直叩きで通る）を塞ぐ。
--
-- スコープ厳守：
--   - 触るのは public.subcontractors のみ。他テーブルには一切触れない。
--   - SELECT 権限と sub_read policy は残す（業務上の一覧表示を維持）。
--   - DELETE には触れない（既に public 全テーブルで REVOKE 済みのため対象外）。
--
-- 含めない：
--   - photos / reports / report_summary / paid_leave / invoices /
--     site_budgets / employee_rates / unit_rates 等は対象外
--   - テーブル定義変更（ALTER TABLE）・RLS有効/無効の切替・RPC変更は含めない
--
-- 実行方法：
--   セクション 1（事前確認）→ セクション 2（変更）→ セクション 3（事後確認）の順。
--   SQL Editor で全実行すると最後の結果しか出ないため、各セクションを分けて実行する。
-- ============================================================


-- ============================================================
-- 1. 事前確認（読み取り専用・DB変更なし）
-- ============================================================

-- 1-1. subcontractors の anon/authenticated/PUBLIC テーブル権限
--      期待（変更前）：SELECT に加えて INSERT / UPDATE が残っている
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'subcontractors'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 1-2. subcontractors の policy 一覧
--      期待（変更前）：sub_read（SELECT）/ sub_write（INSERT）/ sub_update（UPDATE）が存在
SELECT schemaname, tablename, policyname, permissive, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'subcontractors'
ORDER BY cmd, policyname;


-- ============================================================
-- 2. 変更SQL案（レビュー後に実行）
--    - anon / authenticated から INSERT / UPDATE を REVOKE
--    - 緩い write policy（sub_write / sub_update）を削除
--    - SELECT 権限・sub_read policy・DELETE には触れない
-- ============================================================

-- 2-1. 直接 INSERT / UPDATE 権限の剥奪
REVOKE INSERT, UPDATE ON TABLE public.subcontractors FROM anon, authenticated;

-- 2-2. 緩い write policy の削除
--      （policy が残っていても 2-1 の GRANT 剥奪で書き込みは通らないが、
--       死蔵ポリシーを残さず整理する。IF EXISTS で冪等に）
DROP POLICY IF EXISTS sub_write  ON public.subcontractors;
DROP POLICY IF EXISTS sub_update ON public.subcontractors;


-- ============================================================
-- 3. 事後確認（読み取り専用・DB変更なし）
-- ============================================================

-- 3-1. anon/authenticated/PUBLIC のテーブル権限
--      期待（変更後）：SELECT のみ。INSERT / UPDATE / DELETE は無し
SELECT table_schema, table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'subcontractors'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 3-2. policy 一覧
--      期待（変更後）：sub_read（SELECT）は残存、sub_write / sub_update は消滅
SELECT schemaname, tablename, policyname, permissive, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'subcontractors'
ORDER BY cmd, policyname;

-- 3-3. 念のため：書き込み権限が残っていないことの明示チェック
--      期待：0行（INSERT / UPDATE / DELETE が anon/authenticated に無い）
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'subcontractors'
  AND grantee IN ('anon', 'authenticated')
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
ORDER BY grantee, privilege_type;

-- ============================================================
-- 実行後の進め方：
--   3-1〜3-3 の結果を確認し、SELECT のみ残存・write policy 消滅を確認する。
--   問題なければ Phase 4-A の次（photos upload 制限）へ進む。
--   ※ 本ファイルは subcontractors 限定。他テーブルの整理は別ファイルで扱う。
-- ============================================================
