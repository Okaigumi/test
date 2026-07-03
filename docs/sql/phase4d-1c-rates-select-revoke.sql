-- ============================================================
-- Phase 4-D-1c：単価系 SELECT REVOKE（unit_rates / employee_rates）
-- ============================================================
-- 【実行ステータス】★実行済み★
--   - 実行日：2026-07-03（Supabase SQL Editor 手動実行）
--   - 実行内容：
--       REVOKE SELECT ON TABLE public.unit_rates     FROM anon, authenticated; … Success. No rows returned
--       REVOKE SELECT ON TABLE public.employee_rates FROM anon, authenticated; … Success. No rows returned
--   - 事前確認A〜E：すべて合格
--       A unit_rates / employee_rates とも anon/authenticated に SELECT 残存（REVOKE前）。
--         INSERT/UPDATE なし。★PUBLIC に SELECT なし → PUBLIC 向け REVOKE は未実行★
--       B read RPC 2本：存在・SECURITY DEFINER=true・search_path=public, extensions
--       C read RPC 2本 EXECUTE：anon/authenticated/service_role あり・PUBLIC なし
--       D write RPC 2本（upsert_unit_rate_secure / upsert_employee_rate_secure）：存在
--       E RLS 有効・policy 現状把握（今回は変更しない）
--   - 事後確認F〜J：すべて合格
--       F unit_rates / employee_rates の anon/authenticated SELECT：消滅（行が出ない）
--       G read RPC 2本 EXECUTE：anon/authenticated/service_role 維持・PUBLIC なし
--       H read RPC 2本：SECURITY DEFINER=true・search_path=public, extensions 維持
--       I write RPC 2本：不変で存在
--       J RLS 有効のまま・policy 不変
--   - 本番 Network 確認 OK：
--       genka / admin とも list_unit_rates_secure / list_employee_rates_secure が 200、
--       unit_rates?select / employee_rates?select は出ない。画面表示OK・Console 赤エラーなし。
--
--   【この段の状態】
--   - unit_rates / employee_rates の anon/authenticated direct SELECT は遮断完了。
--     読み取りは read RPC 経由に一本化（新旧併存の解消）。
--   - RLS / policy は未変更（policy 整理は別工程候補）。
--   - 記録先：docs/db-migrations.md「2026-07-03 Phase 4-D-1c 単価系 SELECT REVOKE（実行済み）」/
--     docs/roadmap.md Phase 4 セクション参照。これにより Phase 4-D-1（単価系 読み取り保護）完了。
--
-- 【前提（すべて完了済み）】
--   - 4-D-1a：read RPC 2本追加済み（list_unit_rates_secure /
--     list_employee_rates_secure・SECURITY DEFINER・search_path 固定・
--     EXECUTE=anon,authenticated,service_role・PUBLIC なし）。
--   - 4-D-1b：フロント移行済み（admin-app.html / genka-app.html の
--     unit_rates / employee_rates direct SELECT 5箇所を read RPC へ置換）。
--     PR #42 merge 済み（merge commit 8a227d6）。
--   - ★4-D-1b 本番 Network 確認 OK★：
--       genka / admin とも list_unit_rates_secure / list_employee_rates_secure
--       が呼ばれ（200）、unit_rates?select / employee_rates?select は出ない。
--       画面表示OK・Console 赤エラーなし。
--   → Phase 4-C-1 の教訓（フロント本番反映前に REVOKE しない）を満たしており、
--     REVOKE 実施の前提が整っている。
--
-- 【このファイルの方針（重要）】
--   - anon / authenticated の direct SELECT を REVOKE して読み取りを
--     secure read RPC 経由に一本化する。
--   - PUBLIC は事前確認A で SELECT が存在した場合のみ追加 REVOKE する
--     （既定では PUBLIC への SELECT 付与は想定しない）。
--   - service_role / postgres(owner) は触らない。
--   - read RPC / write RPC の EXECUTE は維持する（変更しない）。
--   - 既存 RLS 有効状態・既存 policy は今回変更しない（把握のみ）。
--     ※ SELECT privilege を REVOKE すると privilege は RLS より手前の関門のため、
--       read 系 policy が残っても direct SELECT は失敗する（policy は inert 化）。
--       policy の整理は別工程候補として残す。
--
-- 【このファイルに含めない（意図的・禁止）】
--   - DROP POLICY / CREATE|ALTER POLICY
--   - ALTER TABLE / DROP TABLE
--   - DELETE / TRUNCATE / INSERT / UPDATE（DML）
--   - unit_rates / employee_rates 以外のテーブルへの変更
--   - REVOKE EXECUTE（RPC の EXECUTE は維持）
--   - docs 更新 / commit / push（本工程では行わない）
--
-- 実行方法：
--   Supabase SQL Editor で「事前確認A〜E」→「REVOKE」→「事後確認F〜J」
--   の順に実行。事前確認・事後確認は必須。
-- ============================================================


-- ============================================================
-- 事前確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- A. 2テーブルの anon / authenticated / PUBLIC 権限
--    期待：SELECT が anon / authenticated に残存（REVOKE 前）。
--          INSERT / UPDATE は無し（Phase 3-3 で REVOKE 済み）。
--    ★PUBLIC に SELECT があるかを必ず確認する。
--      あった場合のみ、後述 REVOKE に PUBLIC を追加する。
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('unit_rates', 'employee_rates')
  AND  grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND  privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP  BY table_name, grantee
ORDER  BY table_name, grantee;

-- B. read RPC 2本の存在・SECURITY DEFINER・search_path
--    期待：2本とも security_definer=true / search_path=public, extensions。
SELECT p.proname,
       p.prosecdef,
       p.proconfig,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure', 'list_employee_rates_secure')
ORDER  BY p.proname;

-- C. read RPC 2本の EXECUTE 権限
--    期待：anon / authenticated / service_role に EXECUTE。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_unit_rates_secure', 'list_employee_rates_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER  BY routine_name, grantee;

-- D. write RPC 2本の存在（壊さない基準）
--    期待：2本とも security_definer=true で存在。
SELECT p.proname,
       p.prosecdef,
       pg_get_function_identity_arguments(p.oid) AS args
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('upsert_unit_rate_secure', 'upsert_employee_rate_secure')
ORDER  BY p.proname;

-- E. 現状の RLS 状態・policy 一覧（今回は変更しない・把握のみ）
--    期待：RLS 有効（relrowsecurity=true）。policy は現状のまま（変更しない）。
SELECT relname AS table_name,
       relrowsecurity      AS rls_enabled,
       relforcerowsecurity AS rls_forced
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname IN ('unit_rates', 'employee_rates')
ORDER  BY relname;

SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('unit_rates', 'employee_rates')
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- 変更（REVOKE SELECT × 2）
--   ※ ここで初めて DB 状態を変更する。事前確認 OK 後に実行。
-- ============================================================

-- 直接 SELECT の遮断（anon / authenticated）。読み取りは read RPC 経由に一本化。
REVOKE SELECT ON TABLE public.unit_rates     FROM anon, authenticated;
REVOKE SELECT ON TABLE public.employee_rates FROM anon, authenticated;

-- ※ 事前確認A で PUBLIC に SELECT が存在した場合のみ、追加で以下も実行する。
--    （PUBLIC に SELECT が無ければ実行しない＝そのままコメントアウト）
-- REVOKE SELECT ON TABLE public.unit_rates     FROM PUBLIC;
-- REVOKE SELECT ON TABLE public.employee_rates FROM PUBLIC;


-- ============================================================
-- 事後確認（SELECTのみ・DB状態は変更しない）
-- ============================================================

-- F. anon / authenticated の SELECT が消えたか
--    期待：unit_rates / employee_rates とも anon / authenticated の SELECT 行が出ない。
--          （PUBLIC も出ない）
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  table_name IN ('unit_rates', 'employee_rates')
  AND  grantee IN ('anon', 'authenticated', 'PUBLIC')
  AND  privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
GROUP  BY table_name, grantee
ORDER  BY table_name, grantee;

-- G. read RPC 2本の EXECUTE 権限が維持されているか
--    期待：anon / authenticated / service_role に EXECUTE 残存。PUBLIC は無し。
SELECT routine_name,
       grantee,
       privilege_type
FROM   information_schema.role_routine_grants
WHERE  specific_schema = 'public'
  AND  routine_name IN ('list_unit_rates_secure', 'list_employee_rates_secure')
  AND  grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC')
ORDER  BY routine_name, grantee;

-- H. read RPC 2本の SECURITY DEFINER / search_path が維持されているか
--    期待：2本とも security_definer=true / search_path=public, extensions。
SELECT p.proname,
       p.prosecdef,
       p.proconfig
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('list_unit_rates_secure', 'list_employee_rates_secure')
ORDER  BY p.proname;

-- I. write RPC 2本が不変で存在しているか（壊していない）
--    期待：2本とも引き続き security_definer=true で存在。
SELECT p.proname,
       p.prosecdef
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('upsert_unit_rate_secure', 'upsert_employee_rate_secure')
ORDER  BY p.proname;

-- J. RLS / policy が不変であること（今回変更していない）
--    期待：RLS 有効のまま。policy 一覧は事前確認E と同じ。
SELECT relname AS table_name,
       relrowsecurity AS rls_enabled
FROM   pg_class
WHERE  relnamespace = 'public'::regnamespace
  AND  relname IN ('unit_rates', 'employee_rates')
ORDER  BY relname;

SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename IN ('unit_rates', 'employee_rates')
ORDER  BY tablename, cmd, policyname;


-- ============================================================
-- ロールバック（必要時のみ・一時復旧用）
--   ※ 通常は実行しない。REVOKE 後に想定外の direct SELECT 依存が本番で発覚し、
--     単価 / 日給が空表示・401 になった等の緊急時にのみ使用する。
--   ※ Phase 4-C-1 で実績のある復旧手順（REVOKE→復旧→原因対処→再REVOKE）。
--     復旧後は原因（未移行の direct read 残存など）を特定・修正し、再度 4-D-1c を実施する。
-- ============================================================
-- GRANT SELECT ON TABLE public.unit_rates     TO anon, authenticated;
-- GRANT SELECT ON TABLE public.employee_rates TO anon, authenticated;


-- ============================================================
-- 本番確認項目（REVOKE 実行後・ブラウザ / Network）
-- ============================================================
--   genka：
--     - ログイン → 原価画面で list_unit_rates_secure / list_employee_rates_secure が 200
--     - 単価・日給・原価サマリー表示 OK
--   admin：
--     - ログイン → 現場一覧（startApp）／「単価」ページで両 read RPC が 200
--     - 従業員日給・ダンプ / 警備単価の表示 OK・保存（upsert_*_secure）OK
--   共通：
--     - unit_rates?select=... / employee_rates?select=... が 401 / 出ないこと（direct SELECT 遮断）
--     - Console 赤エラーなし（favicon 404 等の無関係ノイズを除く）
--     - npm run test:smoke = 4 passed（ログイン画面・csv-viewer 回帰なし）


-- ============================================================
-- 触らないもの（この工程の非対象）
-- ============================================================
--   - read RPC / write RPC の EXECUTE 権限（維持）
--   - service_role / postgres(owner) の権限（維持）
--   - RLS 有効状態・既存 policy（変更しない。整理は別工程候補）
--   - helper _verify_management_session（非公開のまま・確認もE/事後に含めていない＝不変前提）
--   - unit_rates / employee_rates 以外のテーブル
--
-- 次工程（本ファイル実行後）：
--   - docs/db-migrations.md /（roadmap.md）へ「Phase 4-D-1c 実行済み」を記録
--   - Phase 4-D-1 完了。以降は 4-D-2 予算（site_budgets）／4-D-3 請求書（invoices）
-- ============================================================
