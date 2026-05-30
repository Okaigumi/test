-- ============================================================
-- ⚠️ まだ実行禁止 ⚠️
--
-- 以下は admin-app.html のフロント変更 + 動作確認が
-- 完全に完了するまで絶対に実行しないこと。
--
-- 実行タイミング：
--   ① create_admin_session でログインできることを確認後
--   ② saveEmployee / saveAdmin が secure RPC 経由で動くことを確認後
--   ③ Playwright での自動確認が通ることを確認後
--   上記③まで完了してからのみ実行する。
--
-- これを先に実行すると admin-app.html の従業員管理・管理者管理が
-- 即時停止するため、フロント変更より先に実行してはならない。
-- ============================================================

BEGIN;

-- employees_update_public を削除（最危険ポリシーの解消）
DROP POLICY IF EXISTS employees_update_public ON public.employees;

-- employees の直接 INSERT / UPDATE を剥奪
-- ※ SELECT は維持（pin列GRANTはコミットd751ec7にて制限済み）
REVOKE INSERT ON public.employees FROM anon, authenticated;
REVOKE UPDATE ON public.employees FROM anon, authenticated;

-- genka_admins の直接 INSERT / UPDATE を剥奪
-- ※ SELECT は維持（ログイン名前一覧の表示に必要）
REVOKE INSERT ON public.genka_admins FROM anon, authenticated;
REVOKE UPDATE ON public.genka_admins FROM anon, authenticated;

COMMIT;


-- ============================================================
-- 権限削除後の確認SQL（上記実行後に使用）
-- ============================================================

-- employees_update_public が消えていることを確認
-- 期待: 0件
SELECT policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'employees'
  AND  cmd IN ('INSERT', 'UPDATE');
